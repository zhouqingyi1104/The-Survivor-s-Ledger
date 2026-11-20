# `dialogs.gd` 拆第一批：灶房 / 菜畦 / 营造 / 读书（2026-11-14）

承接 [37](37-optimization-roadmap.md) 的工程债第 1 条（"按系统把 `dialogs.gd` 拆成 `scripts/ui/dialogs/*.gd`"）。上一批 [57](57-playtest-gate-check.md) 说明过为什么试玩前不动大改：这次只搬一组、只做纯位移，用可对照的办法证明"搬完之后玩家看到的每一个字、每一个尺寸都没变"。后续批次照同一办法搬。

## 0. 结论

| 项 | 结果 |
|---|---|
| `scripts/ui/dialogs.gd` | 2280 → **2128** 行（移出 164 行，留下 12 行入口与转发） |
| 新增 `scripts/ui/dialogs/house.gd` | 179 行：灶房、菜畦、营造守具、读书四个面板 |
| 新增 `scripts/ui/dialogs/kit.gd` | 47 行：`_act / _start / _action / fx_text / req_text` 的公共实现 |
| 调用点 | **一个没改**。`Dialogs.cook() / garden() / build() / read()` 仍是入口，内部转发 |
| 四个面板的控件树 | 拆分前后 **4/4 完全相同**（文本、禁用态、可见性、尺寸逐行一致） |
| `check_scripts` | 95 个脚本，失败 0 |
| `ui_smoke` | 失败 0 处 |
| `m2_targeted_ui`（窗口） | 124 / 124，failed=0 |
| `c5_ui`（窗口） | 2 处失败，**在 HEAD 上同样复现**，不是本批造成的（见 4 节） |

## 1. 为什么是这四个

它们是一组：都在宅院里开、都只读 `Game.run`、都不碰 `_live` 这类实例状态、都不需要自己的滚动高度计算（`build` 用的是固定 480）。搬它们不需要先改架构，所以拿来做"搬家模式"的第一个样本。

反过来，存货（`inventory`）暂时没搬：它有一个 `_inventory_filter` 存在 Dialogs 上，还用了 `get_viewport()` 算高度——这类要先把状态挪成模块自己的，属于下一批的活。

## 2. 怎么搬

三层，都很薄：

1. **`kit.gd`**：把五个公共小工具（开工、做成了关窗、一行末尾按钮、效果文字、用料文字）抽成静态函数。`dialogs.gd` 里保留同名方法，函数体改成一行转发——

   ```gdscript
   func _action(row: HBoxContainer, text: String, cb: Callable, block: String) -> void:
       Kit.action(row, text, cb, block)
   ```

   **另外五十多个面板照旧调用 `_action(...)`，一行都不用动**。`FX_NAMES` 常量随之搬进 kit（全项目只被 `fx_text` 用过，已 grep 确认）。

2. **`house.gd`**：四个面板整段搬过去，`_run()` 换成 `Game.run`，`_act/_start/_action/fx_text/req_text` 换成 `Kit.*`。面板正文一个字没改、顺序没动。

3. **`dialogs.gd`**：四个入口留壳。

   ```gdscript
   func cook() -> void:
       House.cook()
   ```

## 3. 怎么证明"没改行为"

纯位移最容易出的事故是"某个字写错、某个按钮的禁用条件换了、某个面板宽了两像素"——肉眼看不出来，测试也未必覆盖。所以这次先做了一台**控件树导出**的对照工具（`build/panel_dump.gd` + `.tscn`，**未入库**）：

- 用 `--demo=xxx` 把面板摆到固定状态，逐节点导出 `类名 | 文本 | disabled | 可见性 | 尺寸`；
- 路径只用「类名#同类兄弟序号」，**不用节点名**——自动起的名字里带实例号（`@Label@4651`），跨进程会变，直接用会假报差异；
- 先验可重复性：同一状态连跑两次，导出结果逐字节相同（cook、build 各验一次），再当作基线。

结果：

| 面板 | 拆分前 | 拆分后 |
|---|---|---|
| 灶房 `cook` | 70 行 | **完全相同** |
| 菜畦 `garden` | 30 行 | **完全相同** |
| 营造守具 `build` | 140 行 | **完全相同** |
| 读书 `read` | 21 行 | **完全相同** |

尺寸也在比对范围内，所以"布局被悄悄改动"这条也被排除了。另外拍了 1280×720 的 `cook` / `garden` / `build` 三张图（`build/shots/refactor/`）目视：面板、滚动区、按钮正常。

## 4. 顺手撞见一处既有的红

`c5_ui` 报两处失败：

```
ERROR: C5 UI: 阁楼施工未完成
ERROR: C5 UI: 入口不可物理拾取 floor_attic
```

按 [56](56-test-red-and-cleanup.md) 的教训，没有直接归因，而是**把改动整个撤掉、在 HEAD 上原地重跑**：同样两处、同样文本。所以这是既有的失败（阁楼入口的物理拾取），与本批无关，本批也没修。

（撤改动的做法：`git diff scripts/ui/dialogs.gd > patch` → 把新文件挪走 → `git checkout --` → 跑 → `git apply patch` 还回来，最后核对 `git diff --stat` 和文件里的标记确实回来了。**"还回来"这一步自己也要验**，否则后面所有验证都建立在没改过的文件上。）

## 5. 下一批照这个办法搬什么

按"依赖少 → 依赖多"排，下一批的候选：

| 候选 | 需要先处理什么 |
|---|---|
| 神龛求签 `omens`、事件 `event`、读书以外的短面板 | 无，可直接搬 |
| 存货 `inventory` | `_inventory_filter` 要挪成模块内状态；`get_viewport()` 改成经 `UI.host` 取 |
| 劫余录 `journal` | 三个 fill 函数共用 `_brief_color`，先一起搬 |
| 主线 / 危机 / 轮回调查 | 各自带 `_*_do` 回调与 token，搬的时候要一起走 |

每批都跑同一套对照：控件树 4 个面板以上 + `check_scripts` + `ui_smoke` + 一个窗口用例。

## 6. 未验收范围

- **只搬了 4 个面板**，其余五十多个仍在 `dialogs.gd`；文件仍是 2128 行，最大的三个文件（`dialogs.gd` / `post.gd` / `post_screen.gd`）只动了第一个。
- 控件树对照证明的是"结构、文本、禁用态、尺寸一致"，不等于像素级渲染一致；渲染层没有改，但没有逐面板截图做像素比对。
- `read`（读书）没有窗口用例覆盖，只有控件树对照与人工目视。
- 本批复现了 `c5_ui` 的阁楼施工与入口拾取两处失败，根因待查。该用例登记在 `ui` 窗口档，可用 `./tools/run_tests.ps1 -Case c5_ui` 单项复验。
- 真人试玩仍是 0 局；本批不改变任何玩法、数值与文案，因此不产生玩家侧证据，也不重打包。
