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
