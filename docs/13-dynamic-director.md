# 运行时 AI 世情导演

2026-10-24。修正上一批的范围误解：用户要求的是游玩中滚动规划未来几天的动态系统。文档 12 的离线策划只是作者工具，不能算运行时导演；邻居求药保留为稳定支线。

## 玩法方向

玩家经营宅院，世界也在行动。AI 基于真实库存、身份、关系、已发生事件和玩家选择，规划接下来三天；规则系统负责验证与兑现成本和后果。

下表保留最初首版的设计边界；危机、NPC、主线、身份专法、可变开局与轮回调查的后续实际交付见本文件后续阶段记录和文档18—23。

| 玩法 | 有趣之处 | 最初首版范围（历史设计） |
|---|---|---|
| 记得选择的人 | 上次不肯借粮的人，下次可能要求以物易物；先前帮忙的人可给欠条或引荐 | 关系记账、选择记忆和后续事件动态生成 |
| 真正的承诺 | 今日借出木料，明日收到柴炭；AI 后来改写计划也不能撤销已经承诺的回报 | 选择后锁定延迟后果，存档与回溯同步恢复 |
| 会变化的困境 | 粮多柴少与粮少柴多的玩家收到不同机会，而非固定每日抽签 | 未来三天的机会、交易、风险由实际状态规划 |
| 传闻与准备 | 得知两天后井口封冻，可抢修井台、囤水或向邻人买水 | 后续扩展成显式危机时钟；首版只生成有明确成本的事件，不暗改天气和尸潮 |
| 有自身目标的 NPC | 木匠想保住工棚，药师想转移伤员；不帮他们也会自行选择 | 首版记录关系与承诺；独立 NPC 行动模拟在后续阶段 |
| 补救与反转 | 拒绝不是永远锁线；能用另一种代价补救，或因连续失信失去机会 | AI 根据选择历史规划后续，不能篡改已经发生的事实 |
| 生活与调查的冲突 | 带药出城会错过修门；追查线索需要别人照看院子 | 已有固定链承接；动态地图目标和跨系统危机另行扩展 |

## 首版执行结构

新增跨轮回输入：游戏每轮完结更新根 `Memory.md`，后续规划实际读回文件，通过 `state.archive` 提供正文与 SHA-256，作为 AI 编剧的前世背景。`state.recollections` 仍只包含最多两位本世已觉醒角色的事实与回应，限定 NPC 知情；编剧可以从完整档案埋伏笔，不能让未觉醒 NPC 全知。规则本地安排觉醒并兑现选项效果；完整机制见 [14-past-lives.md](14-past-lives.md)。

1. Godot 内异步客户端每秒做轻量检查，不在点击、物理帧、存档函数中等模型。
2. 本地后台桥接器独占一个生成任务，调用已认证 ARK Agent Plan CLI，固定 low reasoning；API 凭据不进入游戏或仓库。
3. 开局采购期间就开始预取灾后剧情；每次计划覆盖未来三个游戏日。每天补足缓冲，重要选择后带上新事实重新规划；短时间多次操作合并。
4. 正在展示的事件与已经做出的承诺锁定。未来候选可以重排，过期或基于旧选择的响应丢弃；新一局、读档和回溯不能接上旧请求。
5. AI 输出受限事件数据，不输出可执行脚本。允许有限物资交换、心神变化、关系变化、1–2 日后的有限回报；必须有不花资源也能选择的出口。
6. 运行时再次检查要求、时间、预算、重复发奖和节点结构。存档保留已准备事件、关系、选择历史和待兑现承诺。
7. 网络慢、套餐不可用、输出不合规或快进超过生成速度时，现有事件与固定支线继续运行，不显示等待框，不冻结游戏。

## 频率与边界

- 目标预取窗口三天，最多每天一个动态事件；固定任务、夜战和天亮结算优先。
- 选择变化后去抖 15 秒、生成最短间隔 45 秒；桥接器最多串行一项、滚动 24 小时最多尝试 24 项。正在选择或当日已有待触发事件时暂不补充，减少即将被选择作废的请求。
- 持久记录请求 ID 与正文摘要，同一请求成功后重放缓存，失败/丢失后不自动重试；不同正文复用 ID 被拒。后台空闲 10 分钟退出，后续按需启动。
- 玩家每次选择的资源/关系/延迟后果必须可见；效果由规则执行，AI 只能在预算内策划。
- 每日一局保持固定事件，不启用非种子生成的 AI 内容。普通局设置可开关动态世情，关闭不取消已承诺回报。
- 首版不包含危机时钟；后续 [18](18-crisis-clocks.md) 已交付三类危机，[19](19-npc-autonomy.md) 已交付三人有限库存和自主决定、受控对话，[20](20-mainline-endings.md) 已接通首条道士—义庄—青云观主线与真实三结局，[21](21-identity-paths.md) 已接入M4首批身份专法。迁居/出城队伍等更复杂NPC行动、全地图动态任务生成仍未实现；主线整局节奏和长期平衡未验收。

## 主线公开事实边界（当前）

`state.mainline` 只含 `schema/published/start_day/stage/evidence/route/interventions/ending/history`：本世公开进度、已交回证据、已完成干预时刻、锁定路线及实际结案。施工私有数据、未来脚本、危机隐藏真假和未觉醒前世不放入这个字段。完整旧世档案仍只供编剧背景使用，不能当作本世取证；未觉醒NPC也不能因此全知。

义庄、青云观调查各需20分钟，证物另经60分钟真实返程才入账；青云观封阵90分钟完工即现场生效。AI不能用一句话提前取证、断运、封阵或撤离；锁定撤离/破阵路线也不等于已经完成结局。主线公开后，普通AI事件的标题、正文、按钮、结果和配送文字使用本地效果说明，保留已校验的数值与承诺；本地真实前世觉醒不受这项文案隔离影响，NPC受控对话仍可编排目录ID。

输出权限维持原有有限物资/心神/关系/延期回礼及受审对话ID，不开放 `mainline/clue/flag/unlock/wave/ending/complete`。既有报价、赊欠、回礼和已经开始的一整晚尸潮不能被重新规划改写。

## 身份与前世经验边界（M4首批）

四身份八种专法由本地规则提供，完成今世义庄交证后才能花料开工。基础法不需要旧世经历；另外四种替代法分别要求真实封阵、实际撤离、给阿宁交药、义庄交证的封存事实。来源固定在新世开场，`Memory.md`自由文案只供编剧背景使用，不能发放能力；每日局关闭前世替代法，当前身份基础方法仍可使用。

新增可选 `state.identity` 的白名单固定为 `schema/role/chosen/completed_t/learned/legacy_tags/history`，只传本世公开方法、实际完工时刻/能力、有效旧世资格标签与最多12条事实。来源ID、私有工作与未觉醒NPC的往事不放入该字段。未完工的能力不能宣称已学会；旧世标签只代表新选择资格，不代表今世已经取证、制作、断运、撤离或封阵。NPC仍只依据自己的 `recollections` 知情。

身份选择或有效旧世备选公开后，普通AI事件的标题、正文、选项、结果与配送同样使用本地经济效果说明，既有数值和承诺不变；真实觉醒及受控NPC目录短句保留。AI输出继续禁止 `identity/learned/recipe/route/effect` 等新字段，不得代办3种配方、轻装/旧路早行/纸阵筹备或改写实际波次。新方法仍需今世青云观交证与后续真实行动，详见[21](21-identity-paths.md)。玩家旧路早行不包含NPC队伍模拟、护送AI或地图战斗。

## 可变开局与下一轮规划边界（M4第二批）

开新世时固定可用的真实旧世来源，玩家在首次出门前从十五种目录筹备中选一种；不同身份显示自己的三条，加上普通开局和符合资格的两条通用经验解法。选择实际消耗银钱、原随身物和采购时间，发放已列明物资，并通过今世送物、出力、引荐或婉拒改变具体人物的信任与人情。前世失约只解锁「今世先付现款」的备选，不把原欠账、逾期、失约加价、旧人情或待收回礼搬到新世；未觉醒NPC不知道玩家过去的选择。完整目录见[22](22-variable-openings.md)。

`state.opening` 恰含六字段：`schema/role/choice/applied/effects/legacy_tags`。`effects` 恰含 `silver_cost/hours/spent/gained/contacts/first_warning`，只记本世已应用的真实增量；未确认开局及迁移旧卷公开零空效果。`contacts` 只有人物与信任、人情增量，`first_warning` 为空或包含 `kind/actor/warning_day`，不包含 `real/protected`。出生库存、私有来源ID/世次、继承全文和内部历史不进入这个字段；它不能冒充本世证物、已学习能力或NPC记忆。

开局锁定第一场危机的目录类型、线人和第2或3日预兆槽位，真假仍由本地种子规则固定并保密，玩家仍须核实、准备、求助、观望或补救。导演不能重排这个首场槽位，之后的可规划槽位继续遵守 `state.crisis.can_plan` 与公开后锁定规则；已展示报价、债务、回礼与已发生事件不改写。AI输出没有 `opening/birth/inherited/effects/first_warning` 等新权限，不得替选、切换或重复补发开局物资，也不能宣称危机已成真或已经免疫。

非普通开局已应用，或出生旧世资格可见时，普通AI事件标题、正文、选项、结果和延迟配送改用本地经济效果说明，原数值和已许承诺保持；真实本地觉醒及受控NPC目录短句保留。运行时继续使用 **ARK Plan、low reasoning** 在后台预规划未来三日，不在玩家点击时等待网络或模型；本批契约、离线失败路径和来源校验没有新增真实ARK调用，不能据此宣称本批模型叙事质量已经实测。

## 跨轮回事件与调查边界（M4第三批）

真实封存的旧约、失约与实际救助，出生固定为最多两宗、人物不重复的本世调查；每人最新原因另有最多三条的永久索引，详细八世裁切不抹掉已确认来源。玩家的残梦是调查起点，不是NPC觉醒；只有本人实际觉醒、世次与事实ID都对应的片段，才能用来互证，仍需付水与完成查证工作。未觉醒时可以自行查访与核对今世账页，不等待角色或模型，见[23](23-cycle-inquiry.md)。

可选 `state.cycle_inquiry` 恰含七字段：`schema/revision/published/work/history/planning/last_result`。`published` 最多两宗且只传已公开阶段、人物、来源世次、时限、真实调查证据、互斥选择与固定回礼。`evidence={}` 不能宣称已查清；处境 `need/stable` 完成今世查证后才公开。`work` 只含案ID、动作、完工时间和标签；原料投入不等于已经完成。`delivery.done=false` 仍是待送，不能再次发放。私有来源ID/正文、出生来源全文、尚未查出的处境及未公开案件不放入 `published`。`planning` 只提供未来合法案ID、人物、类型、时间窗口与审核提示ID，不授予NPC旧世知识。

AI在采购期和游玩后台预取未来三天时，可返回顶层 `cycle_plan` 数组，最多两行且每案唯一；每行恰为 `{case_id,day,cue}`，只能拷贝对应slot案ID、选择窗口内日期及 `old_note/familiar_dream/folded_page` 审核ID。排期接受一次即锁定，已公开案、期限、现有调查、已选方案与固定回礼不受重规划改写。无可调度slot时必须省略或给空数组；旧客户端与缺此字段的旧快照继续可用。模型不能创造新案、真相、调查进度、NPC觉醒、代价或奖品，也不能通过普通事件代办调查、偿债或补发回礼；受控案文由本地规则说明。

线程HTTP、15秒选择去抖、45秒请求间隔、持久去重与旧run/session/revision/档案哈希丢弃机制继续使用。没有合格规划、断网、慢请求或关闭动态世情时，本地第3/6日方案仍完整推进，查访、核对、选择和回礼均不发同步网络请求。当前schema与本地行为检查不等于真实模型叙事质量验收。

## 必须验证的反例

慢请求下角色仍可行走；离线可以继续；旧响应不污染重开/读档/回溯；选择后旧计划失效；已承诺回报不会被重规划撤销；缺资源有退出选项；重复点击/请求不能重复发奖/重复消耗套餐；不合规 JSON/越权物品/超预算数值被拒；测试使用本地模拟服务且不会意外消耗真实套餐；真实 ARK 生成与接入结果单独报告。

## 首版实测与证据（历史记录，2026-10-24）

本轮首次真实请求返回 503，未取得可用计划；不能确认是否消耗套餐或断言失败原因。保留失败记录，经用户明确允许后仅补做一次真实请求，成功：

- response_id：`resp_021792786447411a6cdd8247c48d753298cd4bcf5eec90efebc05`。
- `auto` 路由、`reasoning_effort=low`；prompt 860、completion 1906、total 2766 tokens。仅记录用量，不推算费用。
- 虚构第 3 日状态：米多、缺柴、此前拒绝过阿宁。返回第 4 日「以粮换工」、第 5 日「阿宁的信」、第 6 日「过路客的柴粮交易」，共 9 个选择。
- 实际响应与测试局面在 `tests/fixtures/director-ark-recorded.json`；不含玩家存档或凭据。测试只回放已有结果，不再次生成。
- 对抗审查发现叙述说归还木板、效果字段却未包含木料；另有将迁居当成既定事实的风险。保留原答案作证据，收紧后续生成提示，明确数值以可见规则字段为准。修订后的提示未额外消耗套餐重测，不能声称文案一致性已经完全解决。

| 验证 | 结果与边界 |
|---|---|
| `node --test tools/director/bridge.test.mjs` | 4 项通过；越权/超预算/空后果/空值、慢请求、缓存去重、重启后失败请求不重发、认证与频率上限；仅模拟 provider |
| `res://tests/director_rules.tscn` | 34 检查通过；三天缓冲、游戏时钟触发、选择后重排、不可撤销承诺、重复点击、新局/回溯/死亡拒收、v11 迁移、缺资源出口、夜战冲突、每日局关闭 |
| `res://tests/director_async_ui.tscn` | 真实 HTTP + 延迟 2 秒的模拟 provider；最近一次等待期间 132 帧且人物持续移动；实际存读档、延期回报、相同局面读档后拒收旧响应通过 |
| `res://tests/director_recorded_ui.tscn` | 真实 ARK 答案离线回放，3 场/9 选择、109 检查通过；检查真实窗口的按钮范围并保存 3 张截图 |
| 既有回归 | 邻居规则 8/8、419 检查通过；邻居窗口 43 检查通过；界面冒烟失败 0；整局模拟 14/14、不变量失败 0；53 脚本编译失败 0 |

所有测试场景默认禁止自动生成；窗口测试也隔离 save/meta 路径。实测后检查请求记录，仍只有上述失败与获准补测两项，没有自动测试产生的额外套餐调用。截图保存在开发机临时目录 `ledger-director-real-day-4.png` / `5.png` / `6.png` 和 `ledger-director-dynamic-event.png`。Godot 退出仍有 ObjectDB/CanvasItem 资源释放警告，本批不宣称修复这些既有问题；玩家实际试玩、离线导出安装包尚未验收。

## 动态世界阶段记录与后续方向

第一性原理：内容量来自「目标、稀缺资源、期限与相互影响的选择」，不能只增加随机对话。规则决定事实和代价，AI 提议走向；玩家应该能提前看见压力、做准备，并从后果理解原因。

1. **人情不是商店积分。** 本阶段已实现三人独立信任、人情、失约记录，影响冻结报价、赊欠资格、物资互助和付费补救；导演收到真实账本，欠账与回礼只由规则结算，见 [17](17-relationship-trade.md)。修棚行动、照看宅院与迁居取舍仍属于后续 NPC 目标玩法，没有用互助文案冒充完成。
2. **两天后的危机，现在就有迹象。** 已实现井口冻裂、运柴中断、药草挤兑三类时钟，预兆公开后两天才发生；支持核实真假、真实施工、人情求助、观望与补救。AI 提前选择目录内提案，公开后不可改写；危机自由文案经规则隔离，不靠提示词保证真假，见 [18](18-crisis-clocks.md)。
3. **NPC 会自己行动。** 首版已实现三人周转物资、08点公开意图和16点自主执行，缺粮筹措、危机备货、失信收紧、亲近回报；支援和人情改托影响实际物资及新报价。AI只编排受审目录表达，事实由规则写出，离线完整可玩。后台新事实保留当天已备好的经济机会、重规划未来，避免每天公告抹掉当天来信，见[19](19-npc-autonomy.md)。工棚维修、阿宁迁居和组织出城仍是后续方向。
4. **机会互斥，失败能补救。** 首条主线已实现坚守、筹备撤离、筹备破阵的互斥取舍；拒绝道士仍可自查，错过撤离/封阵期限转守宅且不退投入。断运和现场封阵改变真实后续尸潮，提前撤离没有守满20日奖励，只有坚守能续无尽。队伍护送、迁居与更多地图任务仍是后续方向。
5. **重来有新方法。** M4首批已实现四身份八法，三种新配方、轻装/旧路早行/纸阵筹备，以及更夫对11/17/20夜实际数量和特性的情报；没有分面兵力预测。资源、工时、身体代价和放弃的机会形成互斥取舍，真实封存经验只解锁备选。第二批已接入身份/旧世经历影响的钱物、人情与首场危机开局；更广的跨轮回事件仍待扩展。

这些阶段先各做一条能实际行动、能失败和补救的完整链，再扩大 NPC 数量和地图。验收同一存档的不同选择在 2–3 天后产生可对照的资源、关系、行动或去留差异，并验证旁观和快进时世界仍能自洽推进。

## 本批主线相关验证（2026-10-24）

- `mainline_rules.tscn`：253检查通过；`mainline_integration.tscn`：207检查通过；`mainline_memory.tscn`：83检查通过，包含恶意AI标题/正文/选项/结果/配送隔离、原始模型内容保留、数值和承诺不变、本地觉醒仍可展示。
- `node --test --test-name-pattern="mainline" tools/director/bridge.test.mjs`：4项通过，只有模拟provider；拒绝私有字段、伪造证据、越权结局权限及新增控制字段，失败请求不自动重发。
- Godot实际导出的5份虚构快照（未公开、坚守、撤离、破阵、义庄调查）均通过Node严格快照校验；本批没有新增真实ARK调用，不将契约验证说成模型永不虚构事实。
- 邻居419、导演34、NPC接入69、危机接入64、交易接入430检查通过。主线窗口349检查通过；玩家整局、长期平衡、CI、导出发行NOT RUN。部分Godot场景仍有既有退出资源警告。

## M4身份专法相关验证（2026-10-24）

- 身份规则288、接入372、Memory127、真实窗口253检查通过；涵盖工法互斥、3配方与3后续筹备、实际撤离及纸阵施工、固定来源/每日公平、身份语义过滤、重复结算、回溯、NPC不全知和真实Markdown流程。
- 新增Node身份契约4项通过，仅模拟provider：拒绝私有来源/工作、能力与身份或资格不一致、未来完成时刻、超限历史、模型新增配方/控制字段；失败请求仍不自动重新消耗额度。实际Godot导出的9份虚构身份快照全部通过Node严格校验。
- 受影响主线规则253、接入207、Memory83，导演34、NPC规则439、Memory文件68、NPC记忆36检查通过；本轮主线窗口回归351检查通过。上节M3历史证据与原计数保持不变。
- 本批没有真实ARK调用。玩家整局、长期平衡、CI、导出发行NOT RUN，Godot既有退出资源警告未在本批修复；契约测试不代表模型叙事质量或永不虚构的保证。

## M4可变开局相关验证（2026-10-24）

- `res://tests/opening_memory.tscn`：275检查、0失败。覆盖十五种实际本地筹备应用后的公开快照、四身份来源与六种真实失约/危机来源、出生固定不追授、裁切后永久索引、每日不贡献、旧卷中立不补发、损坏来源/归档拒绝、真实Memory写读及普通AI恶意文案隔离。
- `node --test --test-name-pattern="opening" tools/director/bridge.test.mjs`：4项通过；六字段及效果白名单、非法来源标签、异身份选择、私有真假、未知控制字段在provider前拒绝，缺开局字段的旧快照兼容。这四项独立测试不依赖TEMP里是否存在Godot输出。
- Godot实际导出的十五份虚构公开快照另经显式Node命令严格验证，15/15通过；来源ID/世次、出生库存、继承全文、真假、防护与内部历史均未泄漏到 `state.opening`。不是手写JSON冒充游戏输出。
- 必要回归 `identity_memory.tscn` 127检查、`memory_file_flow.tscn` 9/9组68检查通过，根玩家Memory文件字节不变。交易、危机、NPC、主线、身份专法和开局六系统的最新一世归档保留在8000 UTF-16预算内，结构化meta不为缩篇幅而裁切。
- 本批真实ARK调用 **0次**；玩家整局、长期平衡、CI与导出发行 **NOT RUN**。Godot既有退出ObjectDB/资源释放警告仍在，不把本地契约校验表述为模型永不虚构或玩家已验收。上节历史验证数字保留。

在项目根PowerShell复现实际十五份快照验证（先跑Godot导出，再执行Node；不会调用ARK）：

```powershell
& 'tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . res://tests/opening_memory.tscn
@'
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {validateSnapshot} from './tools/director/bridge.mjs';
const contexts=JSON.parse(fs.readFileSync(path.join(os.tmpdir(),'ledger-opening-public-fixtures.json'),'utf8'));
assert.equal(contexts.length,15);
for(const input of contexts){
  assert.equal(validateSnapshot(input),true,input.state.opening.choice);
  const raw=JSON.stringify(input.state.opening);
  for(const field of ['source_id','source_life','birth','inherited','real','protected','history']){
    assert.ok(!raw.includes('"'+field+'"'),field);
  }
}
console.log('Actual Godot opening contexts: 15/15 strict schema and privacy PASS; no ARK calls');
'@ | node --input-type=module
```

## M4轮回调查相关验证（2026-10-24）

- `res://tests/cycle_memory.tscn`：90检查、0失败；真实封存来源与出生固定、三人物永久索引、重复/未来/每日/自由文案拒绝、实际调查/处置/回礼和Markdown读写、未完工归档与七系统8000 UTF-16预算通过，真实根Memory字节不变。
- `node --test --test-name-pattern="cycle" tools/director/bridge.test.mjs`：5项独立契约通过。严格七字段公开上下文、排期三字段白名单、私有真相/来源/越权效果拒绝；慢模拟provider等待时health仍响应，同请求进行中拒绝重复、完成后缓存不重复调用。此命令不依赖TEMP导出文件。
- 实际Godot导出的八份公开快照单独显式校验8/8：残梦公开、查访完成、今世查证、方案工作中、方案完成、固定回礼已兑现、未查证拒绝与未查证到期。私有来源/处境没有冒充公开信息；阶段匹配不靠手写JSON推断。
- 必要回归：`past_lives_rules.tscn` 8/8组123检查、`memory_file_flow.tscn` 9/9组68检查、`node --test --test-name-pattern="archive|recollections|Memory.md" tools/director/bridge.test.mjs` 7项通过。既有Godot退出资源警告保留，没有扩大为全量发行验证。
- 本批真实ARK **low reasoning调用1次、无重试**：使用实际Godot公开调查快照，返回3场未来事件和1条第3日 `old_note` 排期，39.6秒；严格snapshot/plan契约通过，usage为prompt 4225、completion 1536、total 5761。实际Godot离线回放19检查通过（仅绑定测试局的临时生命/会话ID，模型文本、经济字段与排期不改）；不将这次契约通过推成模型永不虚构或完整叙事质量验收。玩家完整轮回、长期平衡、CI、导出发行 **NOT RUN**。上节历史计数保留。

在项目根PowerShell复现实际八份公开快照验证（不调用ARK）：

```powershell
& 'tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . res://tests/cycle_memory.tscn
@'
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {validateSnapshot} from './tools/director/bridge.mjs';
const rows=JSON.parse(fs.readFileSync(path.join(os.tmpdir(),'ledger-cycle-public-fixtures.json'),'utf8'));
assert.equal(rows.length,8);
for(const row of rows){
  assert.equal(validateSnapshot(row),true);
  const raw=JSON.stringify(row.state.cycle_inquiry);
  for(const field of ['source_id','sources','private_condition','fact_id','paid']){
    assert.ok(!raw.includes('"'+field+'"'),field);
  }
}
console.log('Actual Godot cycle contexts: 8/8 strict schema and privacy PASS; no ARK calls');
'@ | node --input-type=module
```
