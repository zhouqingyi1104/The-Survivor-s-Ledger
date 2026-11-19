# `dialogs.gd` 拆第四批：主线 / 危机 / 轮回调查（2026-11-19）

承接 [58](58-dialogs-split-house.md)、[59](59-dialogs-split-stock-shrine-event.md)、[60](60-dialogs-split-journal.md)。
这一批搬的是三条调查线；它们也是第一次出现「搬出去的面板还要回头用没搬走的入口」和
「没搬走的面板也要用搬走的小工具」，所以多留了几个一行的壳，都写在下面。

## 0. 结论

| 项 | 结果 |
|---|---|
| `scripts/ui/dialogs.gd` | 1817 → **1615** 行（这批删 212、加 10；四批合计 2280 → 1615，减 665） |
| 新增 `scripts/ui/dialogs/inquiry.gd` | 259 行：尸劫来历（主线）、风声与危机、轮回调查 |
| `kit.gd` | 47 → 54 行：多了 `clock_text()`（原来 dialogs.gd 的 `_trade_clock`） |
| 调用点 | 一个没改。`Dialogs.mainline()` / `crisis()` / `cycle_inquiry()` 仍是入口，内部转发 |
| 三个面板的控件树 | 拆分前后 **逐字节相同**（mainline 40 行、crisis 48 行、cycle_inquiry 42 行） |
| `check_scripts` | 100 个脚本，失败 0 |
| `mainline_ui` / `crisis_ui` / `cycle_ui`（窗口） | **364 + 198 + 611 = 1173 项检查，失败 0** |
| `identity_ui` / `opening_ui` / `social_trade_ui` / `past_lives_ui`（窗口） | 4/4 通过 |
| `ui_smoke` | 3 次复跑**全过**（失败 0 处）；上一批记过的「翻回后不在清晨」这次没复现（见 5 节） |
| `npc_ui` | 本机仍是不稳定（上一批已查明是窗口不出帧），见 5 节 |
| 三个转发壳 + `clock_text` | 无头探针 6 项，失败 0（**这是本批唯一运行时验过 `_crisis_when` 的一次**，因为 `npc_ui` 又没出帧） |

## 1. 为什么三块放一个文件

`dialogs.gd` 里这三块本来就是一串，硬拆成三个文件反而会多出互相调用：

- 主线的面板里有「身份与前世」和「外出地点」两个跳转——前者还没搬家（`Dialogs.identity_paths`），
  后者走的是 `explore_pick()`（也还没搬家，`Dialogs.explore_pick`）；
- 主线和危机共用**同一个时刻写法**（「第 N 日 08:00」），原来叫 `_crisis_when`；
- 轮回调查是「前世」那一页的第三个入口，与前两块共用一个 `_*_do` 回调加 token 的形状。

放一起以后，这三块之间怎么互调都还是文件内的静态函数，省掉一堆跨文件引用。

## 2. 这次多出来的壳，都是别人要用的

搬之前先 grep 了要动的符号，找出**三处外面还在用**的东西，各留一行转发（测试与 HUD 一行没改）：

| 谁在用 | 用什么 | 处理 |
|---|---|---|
| `scripts/ui/screens/post_screen.gd:1113/1118/1512/1513` | `Dialogs.crisis_status(view)` / `Dialogs.crisis_clock_text(view)`（宅院 HUD 的风声卡与倒计时） | `crisis_status` / `crisis_clock_text` 留转发 |
| `dialogs.gd` 自己的邻人面板（`_npc_autonomy`，还没搬家，三处） | `_crisis_when(t)` 那个时刻写法 | `_crisis_when` 留转发 |
| `dialogs.gd` 自己的身份页 / 邻人页 / 纸鹤往来（四处） | `_trade_clock(t)`（同一个时刻写法） | 挪进 `kit.gd` 叫 `clock_text`，`_trade_clock` 留一行转发 |

第三行说明一下：`_trade_clock` 其实是个通用的「几点几分」格式化，`clock_text` 这个名字更贴它的用处，
而 `kit.gd` 本来就是弹窗公用小工具的家（第一批的 `_act / _start / _action / fx_text / req_text` 都在那儿）。
搬完以后 `dialogs.gd` 和 `inquiry.gd` 各用一份实现，不再互相指。三个壳都只在前几批没搬完之前存在，
剩下两块搬完就该删。

另外 `dialogs.gd` 里原来 `const Cycle = preload(...)` 已经没有使用者了（轮回调查整块搬走），
顺手删掉——**这是这批唯一一处「删掉而不是搬走」的代码**。

## 3. 控件树对照：这次要给三个面板各摆一个局面

三个面板都随局面变（主线看进度与路线、危机看有没有风声、轮回调查看旧案），
所以不能像劫余录那样直接用 `--demo=post` 拍——那样危机只会落在「近日没有风声」的空分支上。
做法是把 `tests/crisis_ui.gd` / `cycle_ui.gd` 的 `fresh()` 夹具搬进对照探针（`build/panel_dump.gd`，未入库）：

| 面板 | 探针摆出来的局面 |
|---|---|
| `mainline` | 第 3 日；主线已进入「接待道士」；证据、三条期限、出路、两条选项卡都在 |
| `crisis` | 第 2 日；发布一场「药草挤兑」的风声（真），四个应对选项卡都在 |
| `cycle_inquiry` | 第 3 日；带三宗旧案来源（承诺 / 失约 / 救助），两宗卡片与今世记录都在 |

摆完先连跑两遍，三个面板都逐字节相同，再拿去当基线。结果：

| 面板 | 拆分前 | 拆分后 |
|---|---|---|
| 尸劫来历 `mainline` | 40 行 | **逐字节相同** |
| 风声与危机 `crisis` | 48 行 | **逐字节相同** |
| 轮回调查 `cycle_inquiry` | 42 行 | **逐字节相同** |

第一次导 `crisis` 时只有 19 行、落在空分支上——是夹具写错了（把 `next_warning_day` 顶到很远、
又没走 `Post.crisis_refresh`），修夹具重摆才对上窗口用例的状态。记在这儿：**空分支对照过了不算对照过**。

## 4. 搬动是否等于行为不变：这条最硬的一次

这一批刚好撞上工程里**最重的三条窗口用例**（它们用真鼠标点、真时钟推、真截图）：

| 用例 | 项数 | 结果 | 覆盖到什么 |
|---|---|---|---|
| `mainline_ui` | 364 | 失败 0 | 主线入口（劫余录 / HUD / E 键）、接待与婉拒、证据、三条出路、出门跳转、`explore_pick` 跳转 |
| `crisis_ui` | 198 | 失败 0 | 风声卡 HUD、四条应对、核实/防备/补救、了结四种结局 |
| `cycle_ui` | 611 | 失败 0 | 三宗旧案、查访、续约/放下、期限、今世记录 |

1173 项检查全过，覆盖了这批触碰的**每一条路径**，包括那两个「搬出去的还要回头用没搬走的」跳转
（`Dialogs.identity_paths`、`Dialogs.explore_pick`）和 HUD 直调的两个转发。

另加：

- **控件树三个面板逐字节相同**（含尺寸、禁用态、可见性）；
- `identity_ui` / `opening_ui` / `social_trade_ui` / `past_lives_ui` 4/4 通过（它们分别用到身份页、
  开局页、纸鹤往来——这批动了它们共用的 `_trade_clock`）；
- `check_scripts` 100 个脚本 0 失败。

## 5. 两处既有红：都还挂着，都还不是本批的账

- **`ui_smoke` 这次是 0 失败，不是红。** 上一批（[60](60-dialogs-split-journal.md)）记过一次「翻回后不在清晨」
  （`ui_smoke.gd:330`），但第二批记录的是 `失败 0 处`。本批提交前连跑三次，**三次都是 `界面冒烟测试：失败 0 处`**，
  那条没复现。所以判它是**偶发**，既不是稳定的既有红，也不是本批引入的——原先写成「同一条、同一行」的结论，
  在提交前复核时被推翻，如实改成现在这句。
- **`npc_ui` 在这台机器上不稳定**：上一批用心跳探针查明是窗口不出帧（`Engine.get_frames_drawn()` 卡住，
  用例停在 `await RenderingServer.frame_post_draw`），HEAD 一样。这批仍试了两次：一次 173 checks / 0 failures
  （窗口出帧就过了），提交前那次**一行输出都没有就退了**（日志只有 GL 初始化与 RID 泄漏告警），复现了这个不出帧。
  也就是说邻人面板那一侧的 `_crisis_when` 转发在实际点击路径上通过过，但**不可复跑**。

因为 `npc_ui` 靠不住，提交前又补了一个无头探针（`build/probe_forwards.tscn`，未入库）直接打这三个转发壳与
`kit.clock_text`：`_crisis_when(0)`→`第 1 日 06:00`、`_crisis_when(1530)`→`第 2 日 07:30`、
`_trade_clock(1530)`→`07:30`、`crisis_status` 的 impact/resolved 两分支、`crisis_clock_text({})`→`暂时没有风声`，
**6 项 0 失败**。这是「壳转发到新模块」这条链在运行时被证过的唯一一次可复跑证据。

## 6. 下一批

按 [58](58-dialogs-split-house.md) 第 5 节排的候选，只剩一块「重活」：

| 候选 | 要先处理什么 |
|---|---|
| 夜战面板 `night_panel` + 方针 `night_plan` | 共用 `_night_do` / `_charm_menu`，且与 `post_screen` 的夜间 HUD 有联动（`_live` 里登记了控件），风险最高，放最后 |

搬它之前要先把 `_live` 那套「弹窗里可回写的控件」查清楚——那是唯一一处会跨「弹窗 ↔ 宅院 HUD」写状态的地方。

## 7. 未验收范围

- 四批共搬 11 个面板，`dialogs.gd` 仍有 1615 行、还有三十来个面板；`post.gd` / `post_screen.gd` 一个字没动。
- 控件树对照是探针摆出来的固定局面，不是玩家真实进程；三个面板各自的空分支只覆盖到 `crisis`（第一次摆错时导过一版），
  其余状态没有逐一对照（行为面由三条窗口用例覆盖）。
- 控件树对照非人工目视；这批没有单独拍 1280×720 截图做像素比对（上一批做过，这批省略）。
- 三个转发壳（`crisis_status` / `crisis_clock_text` / `_crisis_when`）与 kit 里的 `clock_text` 都是过渡物，剩下两块搬完应删除。
- `npc_ui` 的窗口不出帧未修、未定位根因（`ui_smoke` 那条是偶发，本批三次复跑全过，不当作待修项）。
- 不改变玩法、数值、文案，故不产生玩家侧证据；真人试玩仍 0 局，本批未重打包，
  `build/windows-release/` 仍是 `2bca5ee` 那份。
