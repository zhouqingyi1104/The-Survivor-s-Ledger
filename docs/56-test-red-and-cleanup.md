# 修掉两个基线测试失败，并清理测试残留（2026-11-11）

承接 [55](55-test-storage-isolation.md)。那批只防新的残留，留下两处基线测试失败和历史文件没动；这批把两件事一起了结。

## 0. 结论

| 问题 | 根因 | 状态 |
|---|---|---|
| `ui_smoke` 2 处失败（找不到「接着守夜」/ 守住的场次没记上） | B3 给每轮夜战加了演出，headless 里演不出画面、等不到 `finished`，轮间结算就停在那儿 | 已修 |
| `rewind_safety` 2 处失败（重启后死亡数不是一次 / 重启未恢复） | **上一批的隔离造成的**：测试手动再调一次 `Game._ready()` 模拟重启，隔离又把它的存档路径重置回默认 | 已修 |
| 玩家数据目录 183 项残留 | 历史裸跑测试累积 | 已清（移到项目内保留） |

## 1. `ui_smoke`：headless 等不到夜战演出

B3（`b6e9f9c`）之后，每轮夜战结算先放一段演出：`_hold_show()` 置 `Game.hold_screen = true`，`RoundShow.finished` 才 `_end_show()` 并打开轮间面板。演出靠真实帧推进，headless 里既看不见也等不到。

测试原来只 `await _frames()` 就断言战报出现，于是卡住：

```
assert Game.run.wave_day == 2   → 还是 1
UI_has("接着守夜")              → false
```

修法是让测试点演出自带的「跳过」按钮（B3 本来就给了这个出口）：

```gdscript
func skip_show() -> void:
	if UI_has("跳过"):
		await press("跳过")
```

在两次 `advance()` 之后各调一次。**这修的是测试，不是产品**——真人玩家本来就有「跳过」可点。

## 2. `rewind_safety`：隔离只该做一次

上一批的 `_isolate_test_storage()` 在 `_ready()` 里无条件重设三个路径。`rewind_safety` 用「再调一次 `Game._ready()`」来模拟进程重启：

```gdscript
Game.run = {}
Game.meta = {}
Game._ready()          # ← 这里路径被重置了
check(int(Game.meta.deaths) == 1, ...)   # 读回来的是空档案，deaths = 0
```

测试先把自己的存档写在 `user://rewind-...`，重启时路径被改到临时目录，于是读了个不存在的文件、拿到全新 meta。

修法：加 `_test_isolated` 标志，**只做一次**。首次 `_ready` 时测试还没设路径，隔离生效；测试随后设自己的路径，再调 `_ready` 时直接返回。全项目只有 `rewind_safety` 会手动调 `_ready()`（已 grep 确认）。

## 3. 一个要记住的教训：验证补丁是否生效，本身也要验证

上一批我判断「这两个失败与本批无关」的依据是：临时改代码关掉隔离，重跑，结果一样。**那次判断是错的**——我的 Python 替换字符串没匹配上，文件根本没变，等于什么都没验证，却被我当成了证据写进提交信息和文档。

这次重做时加了校验才露馅：

```
changed        ← 文件真的变了
NOT CHANGED    ← 没匹配上，等于没测
```

结果一关隔离，`rewind_safety` 立刻 96 / 0 全过——根因正是隔离本身。

**以后凡是「临时改代码验证」这类动作，改完必须先确认改动落到文件上了**，否则得到的是假阴性，而且会被当成结论写进文档。

## 4. 清理

清的是 `%APPDATA%\Godot\app_userdata\劫余录\`。**没有直接删**：全部移到项目 `build/appdata-removed-20261111/`（保留原目录结构），需要时整份搬回即可。清之前另有一份完整快照在 `build/appdata-backup-20261111/`（141 MB）。

移出 192 项：

| 类别 | 数量 | 依据 |
|---|---|---|
| `*.bak` | 73 | 测试存档轮换留下的备份 |
| `*.json` | 60 | 夹具，文件名都带 pid（`mainline-ui-34520.json`、`c4-rules-43132.json`…） |
| `*.md` | 26 | 测试的 `Memory.md` 副本 |
| `*.png` | 9 | 根目录截图 |
| `*.bad` / `*.bad-N` | 6 | `continue_safety` 的坏档留底（每个 56 字节） |
| `*.interrupted` | 1 | `rewind_safety` 的回溯事务文件 |
| `shots/`、`hero_shots/` 里的图 | 17 | 测试与出图产物 |

保留：

- `video.cfg`（玩家的视频设置）；
- `logs/`、`shader_cache/`、`vulkan/`（运行日志与引擎缓存，删了也会重建，留着不碍事）；
- `backups/` 与 `objectdb_snapshots/` 本来就是空的，没动。

清理后根目录剩 **8 项**（7 个目录 + `video.cfg`），**没有 `save.json`、`meta.json` 及其任何备份**——`has_save()` 现在返回 false，标题界面不会再假装"还有旧卷"。

## 5. 验证

| 用例 | 结果 |
|---|---|
| `check_scripts` | 93 个脚本，失败 0 |
| `ui_smoke` | 失败 0（改前 2） |
| `rewind_safety` | 96 / 0（改前 94 / 2） |
| `storage_isolation` | 8 / 0 |
| `close_safety` | 86 / 0 |
| `save_pack_io` | 21 / 0 |
| `continue_safety` | 21 / 0 |
| `journal_tabs` | 19 / 0 |
| `sim_test` | 16 / 16 项，不变量失败 0（耗时 17m45s，比 10-31 的 6m40s 长，事件池扩到 72 条后模拟变重，未深查） |

未跑 full，也没跑窗口类测试（本批改动只在 `Game._ready` 的隔离分支和两个测试文件）。

## 6. 未验收范围

- **真人试玩仍是 0 局**，A4/A5/B5/阶段 D 的前置没有变化。
- 清理只是"挪走"，`build/appdata-removed-20261111/` 与 `build/appdata-backup-20261111/` 共约 150 MB 还占着盘，确认没问题后可以自己删。
- 50 个自己指定 `user://` 路径的测试仍会在裸跑时留下新文件；隔绝它们的办法是走 `tools/run_tests.ps1`（那里会隔离 `APPDATA`），或者等哪天逐个改清理逻辑。
