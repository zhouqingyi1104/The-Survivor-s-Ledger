# 测试不再写进玩家存档目录（2026-11-10）

对应 [37 优化路线图](37-optimization-roadmap.md)「并行：工程债」第 2 条：测试残留不再落到玩家数据目录根下。

## 0. 结论

看完真实目录后发现了比"垃圾文件"更严重的东西：

```
%APPDATA%\Godot\app_userdata\劫余录\
  save.json.bak      87 KB   ← 主档不存在，只剩备份
  meta.json.bak     327 B
  ...另有 160 多个文件
```

`save.json.bak` 的杀伤力在 `Game.has_save()`：

```gdscript
return FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path + SaveFile.BAK)
```

**备份也算有存档**。所以一个从没玩过的人打开游戏，标题界面会认为"还有旧卷"，停在「另起一卷」的确认上——而那个备份其实读不出来完整的一局。这批修的就是这条路径。

## 1. 为什么会写进真实目录

`tools/run_tests.ps1` 是会隔离的：`tools/run_tests.py:238` 的 `isolated_environment()` 把 `APPDATA`、`LOCALAPPDATA` 都指到项目 `build/` 下。走运行器跑的测试从来没污染过真实目录。

漏的是**裸跑**：

```
godot --headless --path . res://tests/xxx.tscn
```

开发和查问题时几乎都这么跑。这时 `Game.save_path` 还是默认的 `user://save.json`，任何一次 `save_game()` 都会落到玩家的真实目录，并按"临时档 → 回读比对 → 改名轮换"把旧档变成 `.bak`。

## 2. 改法：裸跑时把默认路径挪到临时目录

`Game._isolate_test_storage()` 在 `_ready` 最前面跑：

- 命令行参数里出现 `res://tests/`（场景或 `--script`）就认定是测试进程；
- 把 `save_path` / `meta_path` / `memory_path` 改成 `系统临时目录/ledger_test_<pid>/` 下的同名文件；
- `OS.has_feature("template")` 时直接返回——发布包里的探针（`windows_release_probe`）要检查默认路径确实是 `user://save.json`，不能被动过。

`memory_path` 也一起挪，因为它是空值时落到**项目根** `Memory.md`（写给 AI 的背景档案），测试不该改它。

## 3. 试过但放弃的：全量重定向

只挪默认值有个缺口：50 个测试会自己把 `save_path` 改成 `user://xxx-<pid>.json`，绕过隔离。我试过给 `save_path` 加 setter，把任何 `user://` 路径都搬到临时目录——**这条路走不通**。

`close_safety` 的写法是"先自己在 `user://close.tmp` 造一个可疑文件，再让 Game 去读同一路径"。重定向把两边拆散，一次掉 49 个失败（`close.tmp: could not lock test file`）。

结论：测试对"文件在哪"的控制有两种风格，重定向只能服务其中一种。**保留默认隔离，不动显式指定路径的测试**，并在代码注释里写清原因，免得以后有人再试一遍。

## 4. 新增测试 `tests/storage_isolation.tscn`

8 项，盯的是落盘位置本身：

- 三个路径都不以 `user://` 开头、都在系统临时目录下；
- `memory_path` 非空（为空会写项目根 `Memory.md`）；
- 路径里不含 `app_userdata`；
- 真写一次 meta，确认文件进了临时目录，且 `user://` 根下没有探针文件。

这条测试的价值是防回归：谁把 `_isolate_test_storage()` 删了，它会立刻红。

## 5. 验证

| 用例 | 结果 |
|---|---|
| `check_scripts` | 93 个脚本，失败 0 |
| `storage_isolation`（新增） | 8 项 0 失败 |
| `close_safety` | 86 / 0 |
| `save_pack_io` | 21 / 0 |
| `continue_safety` | 21 / 0 |
| `journal_tabs` | 19 / 0 |
| `crisis_ui`（窗口） | 198 / 0 |

实测证据：

- 裸跑 `close_safety`、`crisis_ui` 前后，真实目录文件数 **166 → 166**（改之前同样两次会涨到 166 以上，并新出现 `crisis-ui-<pid>.json.bak`）。
- 探针打印：`save_path = C:/Users/.../Temp/ledger_test_45124/save.json`，`user://` 仍解析到 `app_userdata/劫余录/`。

## 6. 未解决的与未验收的

- **历史残留没清**：真实目录里还有 166 个文件，包括那个 `save.json.bak`。这批只防新的，不动旧的——那是用户的数据目录，删之前要本人确认。清单见下。
- **50 个显式指定 `user://` 路径的测试仍会留 `.bak`**：它们的文件名带 pid，不会和真实存档 `save.json` 冲突，所以**不会再造成"以为有旧卷"**，只是垃圾文件。根治要给每个测试改清理逻辑，属于另一批。
- **`rewind_safety` 2 处失败、`ui_smoke` 2 处失败与这批无关**：临时关掉隔离后重跑，结果一模一样（`重启后底稿回溯死亡数不是一次`、`找不到可按的按钮：接着守夜`）。是 11-04 那批夜战/回溯改动留下的，另行处理。
- **没跑 full**：只跑了与本批相关的定向用例。

## 7. 残留清单（待确认后清理）

`app_userdata/劫余录/` 调查时共 **180 项**（含 7 个目录）：

| 类型 | 数量 | 说明 |
|---|---|---|
| `*.bak` | 73 | 测试存档轮换留下的备份，含 `save.json.bak`、`meta.json.bak` |
| `*.json` | 60 | 测试夹具（`c4-rules-<pid>.json`、`c5-floor-<pid>.json` 等） |
| `*.md` | 26 | 测试的 `Memory.md` 副本 |
| `*.png` | 9 | 截图（`brief_hud.png`、`death_shot.png`、`export_shot.png` 等） |
| 目录 | 7 | `backups/`、`shots/`、`hero_shots/`、`logs/`、`objectdb_snapshots/`、`shader_cache/`、`vulkan/` |
| 其它 | 3 | `video.cfg`、`rewind`、`*.vulkan` |

其中 **`backups/` 可能是真实存档备份，配置类（`video.cfg`、`input.cfg`、着色器/管线缓存）是用户设置，都不能删**。

建议只清 `.bak`、测试夹具 `.json`、测试 `.md`、测试截图；执行前先把整个目录复制一份。这批没有动它们。

