# 风声与危机时钟

2026-10-24。先规划再开发。承接人情交易，做「预兆 → 核实 → 筹备/请人/观望 → 发生 → 补救/后果」的完整可玩循环，不靠无提示扣属性制造危机。

## 玩家能看见的结果

宅院 HUD 常驻紧凑危机卡，显示预兆、来源、核实状态与游戏时间倒计时；「劫余录 → 风声与危机」查看证据、影响、行动成本和历史。一次只处理一场危机，约每七个游戏日一场。公开预兆后至少两天才发生；发生后最多持续到第二天后的 08:00，可提前解决。通常前二十日能遇到三场，类型与真假可不同。

本地规则和种子提供完整离线安排；运行时 AI 可以提前从目录选择下一场类型、线人、真伪。公开后不改类型、真假和期限，重规划不能推迟或抹除。未核实的真伪不会出现在玩家界面或已知事实输入中；AI 编剧选过的真假也不代表 NPC 已经核实。

## 三类危机与实际影响

| 危机 | 预兆与核实 | 提前处置 | 若成真且未防住 | 事后补救 |
|---|---|---|---|---|
| 井口冻裂 `well_freeze` | 井沿结薄冰、汲水绳发硬；花 30 分钟、精力 4 检查井口 | 木料 1、柴 1；60 分钟、精力 6，为井口保温 | 暂停玩家打水、孩子打水和顺带浇田；已有家中清水不变 | 柴 2、木料 1；90 分钟、精力 8，凿通井口 |
| 运柴中断 `fuel_shortage` | 运柴车变少、路口积雪；花 30 分钟、精力 4 查验便道 | 木料 1、铁钉 1；60 分钟、精力 6，加固运柴便道 | 老周、过路客尚未形成的新日报价加收米 1；已显示报价、已签欠账和回礼不变 | 木料 2、铁钉 2；90 分钟、精力 8，抢修便道 |
| 药草挤兑 `herb_shortage` | 医馆排队、药篮渐空；花 30 分钟、精力 4 核实需求 | 艾草 2、清水 1；60 分钟、精力 6，支援药材分装 | 阿宁尚未形成的新日报价不含艾草并加收米 1；家中药品与已签约物资不变 | 艾草 3、清水 2；90 分钟、精力 8，追加药材 |

发生时间为预兆日之后第 2 日 18:00；自然结束为发生日之后第 2 日 08:00。已形成的当日报价冻结，筹备和修复不会追溯修改报价。玩家也可以通过已有打水、采购、加工、交易提前囤物资，不强迫每场都出手。

## 每个选择的后续

- **核实**：花时间和精力，完成后才得知真假及证据。虚惊可以提前结案，避免浪费筹备物资；若属实仍可选择不同应对。
- **提前处置**：按上表先收物资和精力，工作完成后才防住该场危机。未核实也可准备，但若虚惊，花掉的时间和物资不退。处置完成后不能再叠加另一条准备收益。
- **请线人帮忙**：消耗该线人人情 1、米 1；30 分钟、精力 4，完成后防住本场，节省自行施工所需材料。已使用的人情不能再次兑换货物，报价令牌随之失效。
- **本次观望**：不扣物资，放弃本场后续提前核实/筹备/求助机会；若成真承担实际影响，只能事后补救。界面先提示这一限制，不把拒绝当作失约惩罚。
- **事后补救**：危机真实发生后按表追加材料与时间，完成后提前恢复行动/供给；若来不及在自然结束前完成则不允许开工，避免无意义消耗。
- 未选择也会按时发生；不会无限等待玩家。没有材料仍可观望，危机有自然结束，不存在必须点付费或联网选项才能继续的死锁。

所有耗时动作都走真实 `run.busy`；中断施工不生效，已耗材料/精力/人情不退，记录中断并允许在仍来得及时重新选择。提前动作要求完成时刻严格早于发生时刻，避免边界顺序歧义。假传闻也保留来源与核实过程，不能临时掷骰惩罚玩家。

## 接口与数据契约

- 核心 `scripts/core/crisis.gd` 只依赖 State/Inv/Data/Past，不依赖 Post/Director/Trade，避免引用环。持久 `run.crisis`，存档 v15；旧局和旧快照从当前日之后安排预兆，不补扣历史危机。
- `state(run)` 保存 `schema/revision/serial/next_warning_day/pending/active/history/last_result`。下一场本地回退按 `run.seed + serial` 的独立 RNG 确定，不消耗尸潮/搜寻 RNG。首次预兆日 `max(2, pday+1)`，下一场在公开预兆日 +7；仅在上一场已结案后公开下一场。
- `poll(run) -> String` 公开预兆、确认发生、结案和发现中断，返回本次新事实；重复调用不重复兑现。Post 推进时间前后和开新日调用，新增事实经 Director.note_choice 作废未展示规划。
- `view(run)` 只返回当前公开危机，包含 `id/title/sign/source/stage/confirmed/investigated/response/protected/outcome/warning_day/impact_t/end_t/token` 及展示文字；无公开危机返回空字典。`options(run)` 返回 `id/text/hint/block`，动作名 `investigate/prepare/aid/ignore/emergency`。
- `act(run, action, token) -> String`：成功空串，失败为原因；动作令牌绑定本世 ID、危机 ID 和 revision，资源/时间/睡眠/忙碌/出门/事件/战斗/选择锁定均由核心再判。耗时动作写入 `busy.kind=crisis`、`data={id,action}`，`complete(run,data) -> String` 在完成时才兑现。人情求助按已存在交易账本原子扣减该人 favors 并推进交易 revision，记录实际用途，不创造欠债。
- `well_block(run) -> String` 查询当前断井；必须同时约束玩家开工、跨发生点的打水完成以及帮手打水/浇田。`market_effect(run,actor) -> {price_add,omit,reason}` 只作用新报价，不回改旧价和已签约物资。
- `context(run)` 精简公开事实：`{schema:1,next_warning_day,can_plan,active,history}`。active 空或 `{id,kind,actor,stage,warning_day,impact_t,end_t,investigated,confirmed,response,protected,outcome}`；kind 上表三种，actor 为 ning/zhou/traveler，stage 为 warning/impact/resolved，confirmed 为 unknown/real/false，response 为空或 prepare/aid/ignore/emergency，outcome 为空或 averted/false_alarm/endured/repaired。history 最多12条 `{day,kind,actor,action,result}`，result<=160字。不存在公开片段时不输出 pending/real。
- `valid_proposal(proposal,base_day)` 与 `propose(run,proposal,base_day) -> bool`：AI 顶层可选 `plan.crisis={kind,actor,warning_day,real}`，warning_day 在 `max(2,base_day+1)..base_day+3` 内，应用时必须等于本地 `next_warning_day` 且未公开、仍有完整预告期。AI可修改未公开的类型/线人/真伪，不可改本地槽位、重置期限、日局或已公开事实。省略字段兼容历史计划与本地回退。
- AI 输入增加可选 `state.crisis`，桥接严格校验上述字段/枚举/时刻一致性；提示词要求只在 can_plan 为真时提议，warning_day 等于 next_warning_day，不在其他事件中泄露未核实真假或重复结算危机效果。接受真实提案后存档，点击和时间推进没有网络等待。
- 不把结构校验当成自然语言事实审核。含私有危机提案的事件，以及存在未公开提案/未结案危机时的普通 AI 来信，使用已校验的物资、人情、心神和延迟回报生成本地标题、选项、结果与配送文字，保留 AI 决策数据但不展示可夹带真假或代办危机的自由文案。危机证据始终由本地调查产生；本地前世觉醒不受此限制。
- `state.completed` 保留最多六场公共结案。最终 `Memory.md` 单列旧世危机和仍未核实的公开传闻，排除私有 pending/real/work；旧世危机不成为新世处罚，不会因有限历史被挤掉而遗失所有结局。
- 最终危机行动/结案作为真实事实进入历史与前世；本阶段不开发独立 NPC 生存目标、自由地图任务或危机修改尸潮规则。

## 分批实现与验收

1. 规划文档独立提交。
2. 危机核心、v15迁移与规则测试；覆盖三类/真假/五种动作/重复/中断/边界/缺材料/每日公平/存档/回溯。
3. 游戏时钟、打水与帮手、冻结交易、导演实际提案接入与跨系统验证，避免只做文案。
4. 常驻 HUD 与滚动面板，真实鼠标点击、调查和筹备工作完成、发生/补救/结案、1280×720布局、隔离存档和截图。
5. AI桥接与本地契约测试，真实 ARK low reasoning 提案→规则接受→预兆锁定→分支回放，记录回答和用量。用户本轮已授权调用，无需再逐次申请；不改凭据或默认模型。只用虚构局面，不提交密钥、玩家存档或真实 Memory。

必要反例：调查前不能看到隐藏真假；AI改变主意不能取消已公开危机；来不及的开工不扣资源；已签报价/借债/回礼不变；外出、睡觉、快进仍推进；孩子不能绕过断井；跨发生点打水不能凭空产水；双击和新世旧令牌拒绝；中断无免费准备；每日局无跨世情报优势；模型慢/失败/离线仍能完整玩。仅跑本次相关测试，失败先修最先真实失败，再重跑受影响项；不运行发布全量。

## 实测记录

Godot 4.7.2。本地场景命令前缀 `tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/`；窗口项去掉 `--headless`、加 `--rendering-method gl_compatibility`。

| 实测 | 结果与范围 |
|---|---|
| `crisis_rules.tscn` | 254 检查，0 失败；三类真假、五动作、中断/期限/材料/精力、种子公平、公开锁定、跨世令牌与v14局/快照升级 |
| `crisis_integration.tscn` | 64 检查，0 失败；真实时钟、跨发生点打水、帮手与浇田、冻结报价/借债、实际人情、不同选择后果；含拆分 `advance(1)` 后快进仍提前一分钟完工的调查/筹备/补救回归 |
| `crisis_ui.tscn`（窗口） | 194 检查，0 失败；真实鼠标、三类与五动作、30/60/90分钟工作、发生/补救/虚惊、存读档、缺材料、HUD首次公开及下一场自动刷新；1280×720截图检查无越界或遮挡既有卡片 |
| `crisis_memory.tscn` | 63 检查，0 失败；真实三场结案和第四场未核实、历史挤出后仍保留、隔离Markdown写读、新世无旧危机、每日知识边界与8k档案限额 |
| `crisis_recorded.tscn` | 40 检查，0 失败；真实 ARK 回答离线接受为实际 pending、公开后锁定，调查/准备、观望/补救、人情求助分支；额外夹带真假/已修复的恶意文案不能经标题/正文/按钮/结果/日志/延迟配送呈现，数值与承诺保持不变，来信保留日期以区分前世事实 |
| Node `--test --test-name-pattern="crisis" tools/director/bridge.test.mjs` | 最终 6 项通过，仅模拟 provider；提案槽位、额外字段、私有字段泄漏、公开状态、越权效果与真实失败形状回归 |
| 受影响规则回归 | 导演34、交易核心136、交易接线430、Memory文件流程68检查均通过；根玩家档案未改。新预兆会作废旧计划，旧测试先公开预兆再验证计划/交易，保留原有严格断言 |

窗口截图为开发机 TEMP 下 `ledger-crisis-hud.png`、`ledger-crisis-warning.png`、`ledger-crisis-averted.png`、`ledger-crisis-impact.png`、`ledger-crisis-false-alarm.png`。所有自动场景禁用真实生成，save/meta/Memory均隔离；真实调用只通过显式开发probe。

### 真实 ARK low 验证

用户本轮明确允许自由调用。使用 `arkcli-chat`、已认证 Agent Plan 的既有 `auto` 路由、low reasoning；未改凭据或默认模型。游戏实际导出虚构第1日库存与开放危机槽位，不上传玩家档案。

- 第1次：`crisis-explicit-probe-20261024-0-1`，危机提案本身合法，但剧情选项多出 `text_is_too_long:false`，严格拒收为 `invalid_plan`，不算通过。原始回答、usage和失败请求缓存保留在 TEMP `ledger-crisis-probe-20261024`；已收紧提示词并添加这一形状的回归，未删除字段或放宽校验。
- 第2次：Godot 重新导出 `crisis-explicit-probe-20261024-r2-0-1`，完整计划成功。`response_id=resp_021792829524793923718d11d313173fa258a554449eb871faec3`；提案为老周传来运柴中断、第2日预兆、真实危机。prompt 2194、completion 2543、total 4737 tokens；两次合计 9006 tokens，不推算金额。
- 成功原答与虚构快照在 `tests/fixtures/crisis-ark-recorded.json`，不含凭据或推理正文。回放使用原始提案，不凭测试构造假装真实生成；第1次失败不能被本地通过覆盖。probe缓存相同请求，重复运行不会自动再付费；没有第3次调用。
- 模型原始自由文字不能作为危机真假或已完成调查/修复的事实。规则隔离有恶意答案回放验证；不宣称模型自身永不编造。

### 尚未验收

玩家整局试玩、长期节奏/经济平衡、其他分辨率、导出安装包和 CI 未执行；未跑发布候选全量。部分 Godot 进程退出仍有 ObjectDB/CanvasItem/资源释放告警，不将功能断言通过等同于无告警。NPC 独立目标与行动仍未开发。本批为本地提交，未推送。
