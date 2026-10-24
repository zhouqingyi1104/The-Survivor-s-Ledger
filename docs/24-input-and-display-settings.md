# 输入动作化与设置界面

2026-10-24。承接路线图 M5「操作/画面一致性」。验收以玩家能改键、改画面设置且重启后仍生效为准，默认键位行为与改前逐项一致。

## 问题（第一性原理）

玩家对操作的两个基本要求：**键位能合自己的手感**、**画面设置能合自己的机器**。当前两者都做不到：

- `project.godot` 没有 `[input]` 节，一个输入动作都没定义（项目检查唯一的 warning：「输入只能靠裸按键判断」）。代码里三处直接读裸按键：
  - `scripts/world/player.gd`：`Input.is_physical_key_pressed(KEY_W/KEY_UP)` 等 8 个判断管移动；
  - `scripts/ui/screens/post_screen.gd`：`_unhandled_input` 里 `match key.keycode` 管 11 个热键（E/空格/1/2/3/N/I+Tab/J/K/R/F/Esc）；
  - `scripts/ui/screens/explore_screen.gd`：`_unhandled_input` 里 E/空格管翻找。
- 设置弹窗（`Dialogs.settings`）只有音量滑块和动态世情开关，没有按键重绑、没有画面选项。

**验收条件**：① 默认键位下，现有每个热键/移动行为与改前一致（自动测试逐项覆盖）；② 玩家能把任一动作改到其他键，立即生效、重启后仍生效；③ 恢复默认一键还原；④ 冲突（一个键绑给两个动作）被拒绝并说明给了谁；⑤ 全屏/分辨率/垂直同步可改、立即生效、重启后仍生效。

## 方案

分三层，全部数据单一来源：

1. **输入动作化**：`project.godot` 新增 `[input]` 节定义全部动作，代码只读动作名。已实证引擎语义（一次性探针，`tests/probe_input.gd`，用完即删）：**动作事件用 `physical_keycode` 定义时，只认带 `physical_keycode` 的事件；用 `keycode` 定义时只认 keycode 事件，两者零互通**。选 physical（布局无关，WASD 在 AZERTY 上位置不变），代价是推 keycode-only 事件的测试要补 `physical_keycode`（真实按键事件本就两者都带，改后更贴近现实）。
2. **持久化内核**（`scripts/core/`，纯逻辑、可无界面测试）：重绑写入 `user://input.cfg`，画面选项写入 `user://video.cfg`，都是 ConfigFile。启动时先**快照** project.godot 里的默认绑定（Runtime 改 InputMap 后默认值从内存里没了，恢复默认要靠这份快照），再套用 cfg 覆盖。
3. **设置界面**：`Dialogs.settings` 增加「画面」「按键」两节。改键用临时捕获节点收下一个按键（Esc 取消），冲突先查后绑。

## 动作清单

| 动作 | 默认键 | 中文名 | 用在哪 |
|---|---|---|---|
| move_up / move_down / move_left / move_right | W/S/A/D + 方向键 | 走路上/下/左/右 | player.gd 移动 |
| interact | E | 翻找/查看 | post_screen 开地点菜单、explore_screen 翻找 |
| confirm | 空格 | 确认 | explore_screen 翻找（与 E 等价） |
| speed_pause | 空格 | 暂停/继续 | post_screen 速度归零切换 |
| speed_1 / speed_2 / speed_3 | 1/2/3 | 速度一/二/三 | post_screen 直接调速 |
| sleep | N | 就寝 | post_screen |
| inventory | I、Tab | 行囊 | post_screen |
| journal | J | 劫余录 | post_screen（夜战中为挥击） |
| guard | K | 招架 | post_screen 夜战 |
| rotate | R | 转个方向 | post_screen 摆放家具时 |
| night_panel | F | 夜面 | post_screen 夜间面板 |
| cancel | Esc | 取消/设置 | post_screen 关菜单/开设置 |

说明：`confirm` 与 `speed_pause` 默认都是空格但语义不同（翻找界面的「确认」vs 宅院里的「暂停」），各自独立重绑；界面上是两行，玩家能看见。Esc 同时是引擎内置 `ui_cancel`，自定义 `cancel` 与它并存互不影响。

## 持久化设计

- `user://input.cfg`：`[binding]` 节，每行一个动作 = 物理键码数组（如 `inventory=[73, 4194306]`）。只存**被改过的**动作；没改的不写，恢复默认即删行/删文件。
- `user://video.cfg`：`[video]` 节，`fullscreen`（bool）、`resolution`（int 索引：0=1280×720、1=1600×900、2=1920×1080）、`vsync`（bool）。
- 启动顺序：快照默认绑定 → 读 input.cfg 套用 → 读 video.cfg 套用（`DisplayServer.window_set_mode` / `window_set_vsync_mode`；分辨率只改窗口大小，内容走既有 `canvas_items`+`expand` 拉伸）。
- 恢复默认：删 input.cfg，把快照重新写回 InputMap。重绑界面同时提供「全部恢复默认」。

## 分批交付与验收

1. 本方案先提交。
2. 输入动作化：`[input]` 节 + 三处处理器迁移 + 修两个推 keycode-only 的测试（`neighbor_ui`、`mainline_ui`）。回归四套件 + `player_animation`、`mainline_ui`、`neighbor_ui`、`director_async_ui`。
3. 持久化内核 + `Settings` autoload + `tests/input_settings.gd`（默认绑定齐全、改键存取往返、冲突拒绝、恢复默认、画面存取往返；`--script` 模式下 autoload 不可见，逻辑全放 core，测试只测 core）。
4. 设置界面两节 + 截图验收（1280×720 与 1920×1080 各一张）+ ui_smoke 补设置流程。

## 未做范围

- 鼠标/手柄按键重绑（本期只做键盘；捕获节点已按事件类型分流，扩鼠标是加一段匹配）。
- 一个动作绑多个键的精细编辑（重绑替换整个绑定，要多键用恢复默认后再手动加——列入后续）。
- 语言、文字速度等其他选项；画面只做全屏/分辨率/垂直同步三项。
- 玩家真人改键操作未验收（自动测试推事件不等于真人按键）；导出安装包不在本期。

## 实测与验收记录

2026-10-25 完成，分三批提交（`ab8a93d` 方案 / `dbd0124` 输入动作化 / `a27544a` 持久化内核 / 设置界面批）。

- **引擎语义探针**（一次性，用完即删）：physical 定义的动作只认 physical 事件、keycode 定义只认 keycode 事件，零互通；echo 事件到不了 `_unhandled_input`；`Input.parse_input_event` 推的事件能驱动动作状态。据此选 physical 定义，并给两个推 keycode-only 的测试补 `physical_keycode`。
- **17 个动作**全部按清单落进 `project.godot [input]`（移动四向带方向键双绑、inventory 带 I+Tab 双绑），探针核对键位与文档表一致。
- **持久化内核**：`tests/input_settings.gd`（`--headless --script`）97 项——默认绑定合同、键名显示、改绑生效（Q 按得出 interact、E 让位）、冲突拒绝、绑自己的键不动 cfg、cfg 往返、手改脏数据过滤、恢复默认、画面存取往返与 apply、真实 `user://input.cfg` 的 boot 闭环（验完还原，不残留配置）。
- **设置界面**：`tests/settings_ui.tscn`（窗口模式）54 项——17 行改键按钮、默认键显示（E、I / Tab）、改键全流程（行里变 Q、InputMap 变、cfg 落盘）、冲突提示「已经给了翻找 / 查看」且绑定不动、Esc 取消、全部恢复默认；画面三项：垂直同步翻转+落盘、分辨率三档循环+落盘、全屏真翻 `WINDOW_MODE_FULLSCREEN` 再翻回；全程不叠层。
- **截图**：`docs/screenshots/settings.png`（画面+按键前几行）、`settings_keys.png`（滚到底的按键区+音量），逐张目视检查无溢出、无截断。
- **两处测试踩坑（都是测试自身的错，不是功能错）**：① 窗口改尺寸后，控件矩形是画布空间、推送的鼠标位置要走窗口空间，`aspect=expand` 下要乘「窗口/视口」覆盖缩放比——不改就点点上一行；探针实测比值为 1.25 时乘回去精确命中。② 垂直同步默认是**开**（`VideoCfg.defaults`），断言按「关→开」写会永远失败，改成翻转前后对比。
- **回归**：编译 68/0；冒烟 0；不变量 16/16；`mainline_ui` 354、`neighbor_ui` 43、`difficulty_ui` 17、`director_async_ui` 131 帧（需先起 `tools/director/fixture-server.mjs`，60 秒自挂）、`player_animation` 18 例，全部 0 失败。
- **一致性**：宅院 HUD 的「存货 I」「设置 Esc」与外出提示「[E] 翻找」改为读 InputMap，改键后 `refresh_key_hints()` 即时刷新；劫余录行的快捷键位本就被待办计数占用，不显示键名。
- 项目检查里「工程没有定义任何输入动作」的 warning 随之消除（下次跑检查工具时确认）。
- 未验收：真人键盘改键与真人鼠标点击（测试为自动推事件）；手柄不在本期。
