# `dialogs.gd` 拆第三批：劫余录（2026-11-19）

承接 [58](58-dialogs-split-house.md) 与 [59](59-dialogs-split-stock-shrine-event.md)。同一个办法再搬一块，
这次搬的是劫余录——它和三页 fill、页签状态、面板高度、日志落底四件事绑在一起，是「连状态一起搬」的第一个样本。

## 0. 结论

| 项 | 结果 |
|---|---|
| `scripts/ui/dialogs.gd` | 1943 → **1817** 行（这批移出 139、补进 13；三批合计 2280 → 1817，减 463） |
| 新增 `scripts/ui/dialogs/journal.gd` | 156 行：今世 / 人 / 前世三页、页签、面板高度、日志落底 |
| 调用点 | 一个没改。`Dialogs.journal()` 仍是入口，内部转发；`post_screen` / `pre_screen` / `explore_screen` 的 HUD 与快捷键都不动 |
| 劫余录面板的控件树 | 拆分前后 **逐字节相同**（108 行，含三页的内容、页签文字、尺寸、禁用态、可见性） |
| `check_scripts` | 99 个脚本，失败 0 |
| `ui_smoke` | **1 处失败，且在 HEAD 上同样复现**，不是本批造成的（见 4 节） |
| `journal_tabs`（窗口） | 19 项，失败 0 |
| 七条从劫余录入口进去的窗口用例 | `social_trade_ui` / `past_lives_ui` / `cycle_ui` / `identity_ui` / `crisis_ui` / `mainline_ui` / `opening_ui` 全部 PASS_WITH_WARNINGS |
| `npc_ui`（窗口） | 本机**不稳定**：停在 `await RenderingServer.frame_post_draw` 上（见 4 节）；**HEAD 上同样失败** |

## 1. 这次多出来的活：三页的 fill 要连状态一起搬

劫余录和前面七块不一样的地方在于，它不是「一个面板一段代码」，而是一个**有状态**的面板：

- 翻到哪一页存在 `_journal_tab`；
- 今世页最下面的日志滚动区存在 `_journal_log_scroll`；
- 外层滚动区与内容根存在 `_journal_scroll` / `_journal_content`，切页后要按当前页重算高度；
- 打开时和切页时各发一次 `call_deferred`（日志落底、重算高度）。

所以这次是四条一起走：`JOURNAL_TABS` 常量、四个状态、`_journal()` 建面板、`_paint_journal_tabs()` 重画页签，
外加三个 fill。搬完以后：

- 四个状态从 **Dialogs 实例上的 var** 改成 **Journal 里的 static var**。这是等价的——Dialogs 是自动加载单例，
  本来就是整个进程一份（和 [59](59-dialogs-split-stock-shrine-event.md) 处理存货分类页签同一个道理）。
- `get_viewport()` 改成 `UI.host.get_viewport()`。`UI.host` 就是 main 场景根（`scripts/ui/main.gd:110` 的
  `UI.host = self`），它和 Dialogs 都在同一个根 Window 下，取到的是同一个视口。
- 三页里的九个入口按钮（主线、危机、开局、邻里、纸鹤、邻人、身份、轮回、前世记忆）指向的弹窗**还没搬家**，
  所以这里只能写 `Dialogs.mainline` 这样的可调用引用，而不是原来的 `self.mainline`。行为一样：都是绑在那个
  autoload 实例上的 Callable。

**两个 `call_deferred` 留了壳。** 延后回调需要一个节点实例，Journal 是 RefCounted，没有节点可以承接，
硬凑成 `Callable(Journal, "...")` 去 defer 是没把握的写法。所以 `_journal_log_to_bottom` / `_fit_journal_height`
这两个名字留在 Dialogs 上，各一行转发到 Journal；Journal 里照原样 `Dialogs.call_deferred("...")`。
**延后动作仍发在同一个对象上、同一帧、同样顺序**，这是这次唯一一处「外壳」，写在这里免得以后看不懂。

## 2. 控件树对照：这次的面板能不能直接比

方法和前两批一样：固定 `--demo=journal` → 逐节点导出 `类名 | 文本 | disabled | 可见性 | 尺寸` → 前后逐行 diff。
这次先连跑两遍确认可重复（108 行逐字节相同），再拿去当基线。

劫余录里确实有**看起来会变**的东西：今世页底部是流水账（`run.log`），三页都读 `Game.run`。
但 `--demo=journal` 摆出来的局面是固定的，两遍导出又完全一致，所以这一页不需要像 [59](59-dialogs-split-stock-shrine-event.md)
的神龛那样先钉住随机源——**先跑两遍验可重复性，比猜它是不是随机的更省事**。

| 面板 | 拆分前 | 拆分后 |
|---|---|---|
| 劫余录 `journal`（三页全导） | 108 行 | **逐字节相同** |

对照覆盖了：三个页签的文字与选中态、今世页的目标 / 今日要务 / 人情往来 / 三个入口 / 日志区、人页与前世页的六个入口
（虽然当前不可见，但子节点、文本、尺寸都在导出里）、以及外层滚动区与内层日志滚动区的尺寸。

## 3. 搬动是否等于行为不变：五条独立证据

1. **控件树逐字节相同**（含尺寸、禁用态、可见性），说明版面与可点性没动；
2. **`journal_tabs` 19 项全过**——它真的开劫余录、点三页、验可见入口数、关掉再开验回到今世页，
   正好把这次搬的「页签 + 三页 + 高度」整条链走了一遍；
3. **七条窗口用例全过**——`social_trade_ui`、`past_lives_ui`、`cycle_ui`、`identity_ui`、`crisis_ui`、
   `mainline_ui`、`opening_ui` 都是从劫余录的入口点进去的，它们过说明九个入口的 Callable 换法没出错；
4. **`check_scripts` 99 个脚本 0 失败**，把新模块也编了一遍；
5. **1280×720 实拍对照**：用 `res://tests/screen_shot.tscn -- --screen=post --dialog=journal` 在改动前后各拍一张，
   逐像素比。整帧有 11,119 个像素不同（占 1.2%），但**弹窗矩形（946×540，居中）内差异为 0**——
   差的全是宅院夜景里会动的背景（天光、雾、灯火），劫余录自己一个像素没变。

第 5 条要说明白：这张图**没有做人工目视**（工作机上的图像查看与分析工具都拒绝了这张游戏截图），
所以它是像素级比对，不是「我看过了」。像素级比对强在能排除「布局被悄悄挪了一格」，弱在不能判断「好不好看」。

## 4. 两处既有失败：这次都拿 HEAD 对照过

按 [56](56-test-red-and-cleanup.md) 的教训，不先归因，先在 HEAD 上原地重跑。做法是
`git stash push -u -- scripts/ui/dialogs.gd scripts/ui/dialogs/journal.gd` → 跑 → `git stash pop`，
并核对 `git stash list` 已空、`git status` 里两个文件确实回来了。

### 4.1 `ui_smoke`：1 处失败，HEAD 上一样

```
ERROR: 断言失败：翻回后不在清晨
   at: push_error … [1] run_flow (res://tests/ui_smoke.gd:330)
界面冒烟测试：失败 1 处
```

`ui_smoke.gd:330` 是死亡 → 「翻回去」之后断言 `Post.day_minute(Game.run) == 0`。
同一环境里本批改动与 HEAD 各跑一次，**报错文本与行号完全相同**，所以与劫余录搬家无关。
这一处前几批文档（[58](58-dialogs-split-house.md)、[59](59-dialogs-split-stock-shrine-event.md)）里记的是
「失败 0 处」。此次拆分前后各复现一次；下一批又连跑三次通过，最新复核将它归为偶发，详见 [61](61-dialogs-split-inquiry.md)。

### 4.2 `npc_ui`：停在等一帧画完，HEAD 上一样

这台机器上 `npc_ui` 时好时坏，坏的时候**一句输出都没有**、跑满 90 秒被测试自己的看门狗 `quit(1)` 掐掉。
为了不靠猜，临时在 `tests/npc_ui.gd` 里加了两样东西（**跑完已 `git checkout -- tests/npc_ui.gd` 还原**）：

- 一个每秒打印一次的心跳，带上 `Engine.get_frames_drawn()`；
- 在 `snapshot()` 的几个 await 前后打标记。

卡住那一次的原始输出（节选）：

```
HB t=1 frames=5
MARK snapshot-enter ledger-npc-gather at 5528
MARK snapshot-after-frames ledger-npc-gather at 5575
MARK snapshot-after-toast ledger-npc-gather at 8484
MARK snapshot-checks-done ledger-npc-gather at 8489
HB t=2 frames=5  …  HB t=89 frames=5
```

结论清楚：**主循环还活着**（心跳一直打到看门狗掐它），但 `Engine.get_frames_drawn()` 从第 5 帧起**一动不动**
——渲染器不再出帧。`npc_ui` 的 `snapshot()` 里有 `await RenderingServer.frame_post_draw`
（`tests/npc_ui.gd:154`），窗口不出帧，这个 await 就永远不返回，于是整个用例停在那里。
**这是这台机器的窗口/桌面状态问题，不是脚本逻辑问题**；同一环境下 HEAD 也失败过一次（同样的 90 秒、
同样没有输出），而窗口正常出帧时，带本批改动的 `npc_ui` 跑出 **173 checks, 0 failures**。

顺带记一句：这批第一次跑窗口用例时，`journal_tabs` 与随后七条用例都正常，只有 `npc_ui` 与 `ui_smoke` 出问题，
所以不是「所有窗口用例都挂了」，更像是跑 `npc_ui` 那个时刻窗口没在出帧。

## 5. 下一批

按 [58](58-dialogs-split-house.md) 第 5 节排的候选，还剩两块：

| 候选 | 要先处理什么 |
|---|---|
| 主线 / 危机 / 轮回调查 | 各自带 `_*_do` 回调与 token，搬的时候一并走；`crisis` 与 `mainline` 互相跳转要一起看 |
| 夜战面板 `night_panel` + 方针 `night_plan` | 共用 `_night_do` / `_charm_menu`，且与 `post_screen` 的夜间 HUD 有联动，风险最高，放最后 |

## 6. 未验收范围

- 只搬了 8 个面板（三批合计），`dialogs.gd` 仍有 1817 行、四十来个面板；三个大文件只动了第一个。
- 控件树对照与截图比对证明的是「结构、文本、禁用态、尺寸、像素一致」，但**截图比对有意排除自动作背景**，
  只对弹窗矩形下结论；弹窗本身没有人工目视（工具拒绝打开这张游戏截图）。
- 劫余录里九个入口指向的弹窗（主线、危机、前世记忆等）这次没有搬，它们与本模块仍是调用关系。
- `ui_smoke` 的 1 处既有红、`npc_ui` 的窗口不出帧，都**未修、未定位到根因**；本批只做到「在 HEAD 上复现，证明不欠本批的账」。
- 不改变玩法、数值、文案，故不产生玩家侧证据；真人试玩仍 0 局，本批未重打包，
  `build/windows-release/` 仍是 `2bca5ee` 那份。
