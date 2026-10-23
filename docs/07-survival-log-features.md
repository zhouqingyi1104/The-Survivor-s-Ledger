# 《生存日志》功能清单

> 这份是**功能清单**，不是设计文档。目的是把原作到底有哪些功能、各自由什么构成，列成可核对的表，
> 用来对照《劫余录》缺什么。分析方法和架构推断见 `docs/01-survival-log-analysis.md`。

## 0. 证据与口径

| 项 | 值 |
|---|---|
| REA 命令 | `rea analyze-javascript-application "<…>/StreamingAssets/WebUI" --json` |
| REA 证据号 | `ev_cc15fbb0f209d3f635786798f1b04c2f5048ba1404c6f494c24902117c15d0db` |
| 提供方 | rea-javascript-application v1，confidence `derived`，authority `shipped-artifact` |
| 静态口径 | 109 个相关文件、13 个 JS 解析成功、416 条 finding、120,656 个 AST 节点、323 个图节点 / 645 条边 |
| 面板数 | `UI/*/*.html` 共 **95 个**，其中 **86 个**主动发消息，9 个纯展示（数据由 C# 推） |
| 接口规模 | 面板→游戏 `UnitySendEvent` **370 种**；游戏→面板 `registerHandlers` **410 个** key |
| 配置表 | 124 张（只有名称，数值加密，见文档 01 第 4 节） |

**边界（必须带着看）：**
- REA 把 JS/HTML 当惰性文本解析，**没有执行**；上面所有"有某功能"都是静态存在，不代表运行时一定走到。
- REA 明确列了 102 条 limitations，其中：`Root.html` 第 48、67 两处内联脚本**未分析**；CommonJS/ESM 的绑定关系只在这个目录内解析；图覆盖不完整，"没找到"不等于"没有"。
- 配置表的**数值**拿不到（YooAsset 按文件派生密钥加密），所以清单里只有机制名，没有数值。
- 面板里的内联脚本逻辑是直接读源码得出的，不是 REA 的输出。

---

## 1. 总览

| 系统 | 面板 | 消息种类 | 主要配置表 | 劫余录现状 |
|---|---|---|---|---|
| 灾前采购 | 9 | 68 | Shop、ShopFurniture、StrangerStock、PlayerSelect | **有**（赶路/宵禁/涨价/递减/关门/清单/当铺/营造坊工期；v0.8 补难度预设） |
| 据点经营 | 37 | 252 | Furniture*、Cooking*、Plant*、Trap*、RobotModule、MaterialRack | **部分有**（种植 / 烹饪 / 家具 / 制造 / 捕鼠笼；v0.7 补上发电机 + 暖气） |
| 外出探索 | 5 | 13 | MapPoint、MapRoom、MapSlot、ExploreLv | **有**（废墟探索） |
| 守夜战斗 | 1 | 1 | TowerWave、TowerDevice、TowerZombieType | **有**（院门攻防 + 架刀格挡） |
| 叙事与图鉴 | 10 | 21 | Event、Story、SMS、Wish、Codex、NpcMonologue | **弱**（只有事件文本） |
| 轮回 meta | 13 | 32 | Difficulty*、Challenge*、Endless*、Talent、Achievement | **有**（翻生死簿 + 天赋） |
| 系统与设置 | 11 | 39 | — | **有** |

---

## 2. 灾前采购（9 个面板 / 68 种消息）

原作是"灾变倒计时 → 在城区地图上跑店采购 → 带有限的人和物回据点"。

**劫余录已经实现了这一整段**（`scripts/core/pre.gd` + `pre_screen.gd`），而且埋得不浅：

| 原作面板 | 劫余录的对应 |
|---|---|
| `PreDisasterMap` 城区地图 + 倒计时 | `pre_screen` 的铺子列表，左上常驻"距宵禁 N 个时辰 · 距尸劫 N 日" |
| `ShopUI` 四类店分页买 | `buy()` / `max_buy()`，货量、银子、车负重三者取小 |
| `TradeUI` 以物易物 | 无（只有银钱交易） |
| `PawnShop` 当铺 | `pawn()`，家传物按 0.9、其余按 0.6 折算 |
| `VehicleShop` 载具店 | **v0.9 已补**：板车（600/+20）、独轮车（1200/+40）、驴车（3200/+70 且远路一个时辰），杂货铺有售 |
| `SelectPeople` 选择带走谁 | **无** |
| `DifficultySelect` 难度预设 | **v0.8 已补**：`data/difficulty.json` 四档（暖冬 / 寻常年景 / 荒年 / 永夜），乘数落到开局银两、气血上限、食量、水量、寒冷、尸潮规模 |
| `ChallengeSetup` 挑战自选 | **无** |
| `RogueSelect` 肉鸽入口 | **无**（无尽模式有，但是劫满后才转，不是开局可选） |

原作这一段的设计要点，劫余录已有的：赶路耗时辰、酉时宵禁、铺子逐日"正常→拥挤→哄抢"、货量按日递减（`DEPLETE` 70% / 40%）、饥荒类铺子涨价更狠、米行第三日关门、营造坊要第二日前订、独轮车负重上限、回家才能卸货、囤货清单。

> 这份清单的早期版本写"灾前采购劫余录没有"，**是错的**。已改正。

**给《劫余录》的启发：** 真正还能加的是**载具**（板车减赶路时辰）和**挑战自选**（开局勾选能力 / 减益 / 目标，像原作 `ChallengeAbility/Debuff/Target` 那样参数化）。难度预设已经补上，这一条的优先级从"最大缺口"降到"挑战自选 + 载具"。

---

## 3. 据点经营（37 个面板 / 252 种消息）

这是原作最大的一块，也是《劫余录》已经铺开一半的地方。

### 3.1 生存属性与 HUD
- `CoreUI0`：倒计时、金币、系统解锁提示、暂停、场景旁白、时间缩放、引导
- `CoreUI1`：六大属性、时钟同步、Buff 提示、游戏计数、快捷行动槽（`QUICK_ACTION_SET_SLOT` / `EXECUTE` / `REQUEST_CANDIDATES`）
- `MainUI`：主菜单（新游戏 / 读档 / 设置 / 成就 / 休闲 / 无尽 / 纯无尽 / 轮回保存）
- **属性六项**：生命 / 饱腹 / 水分 / 心态 / 精力 / 体温

**劫余录六项全有**（`scripts/core/post.gd` 的 `RATE` 和 `_tick`）：

| 属性 | 劫余录的实现 |
|---|---|
| 生命 | 气血，掉血来源有饿 / 渴 / 尸瘟 / 冻 / 三面溃破 |
| 饱腹 / 水分 | 每小时掉，睡着掉得慢；归零开始掉气血 |
| 心态 | 每小时缓掉，睡觉回香；香炉、摆设、舒适度都能补 |
| **精力** | 每小时掉 1.2，睡觉回 7、小憩回 10；**每个行动都标了精力消耗**（`ACTIONS` 表：做饭 6、营造 10、翻找 4……），翻一处废墟再扣 6，夜战出一招扣 8；精力 < 20 翻找会出事，不够就连工都开不了；**守夜战斗力还按精力缩放**（`defense.gd`） |
| **体温** | 白天靠日头回暖（上限 60，有地窖 75）；冷夜按天气 `cold` 掉温，地窖减半；生火后上限 100，只有一捆柴是"弱火"（后半夜减半、上限 70）；体温 < 30 掉气血掉心态，< 15 掉得更狠，能直接冻死；**冻着睡觉回暖只有六成、气血也不长** |

> 这份清单的早期版本把精力和体温写成"缺失"，**是错的**——两项都实现得很深。已在此改正。
> 真正缺的是**产出手段的多样性**：原作有发电机 / 暖气 / 无人机 / 机器人一整套，我们只有炭盆和地窖。

### 3.2 生产链（做得多、做得细）
| 面板 | 功能 | 劫余录 |
|---|---|---|
| `ToolTable` | 工作台制造：配方、批量、连续制造、笔记分类、材料架互倒 | **有**（recipes.json） |
| `Cooking` | 烹饪：配方、加燃料、开始 / 停止、冰箱引导 | **有** |
| `BrewPanel` | 酿造 | **无** |
| `DyePanel` | 染色（`PlantPigment` 植物颜料） | **无** |
| `Compressor` | 压缩（减重 / 减体积） | **无** |
| `Shredder` | 粉碎（回收材料） | **无** |
| `MaterialRack` | 材料架：物品上架、按类目取用 | **无** |

### 3.3 种植
`PlantPanel`（主面板，108 KB）、`PlantingDetails`、`GreenhouseBuild`、`AddFertilizer`、`DailyFert`
- 功能：种植 / 浇水 / 施肥 / 补种 / 批量农事（`PLANT_CHORE_BATCH`、`PLANT_CHORE_REPLANT_TOGGLE`）、成熟点击收获、温室建造、每日施肥结算
- 配置表：`Plant`、`PlantLv`、`PlantPigment`、`ProductionList`、`ProductionLv`

**劫余录已有**：菜畦种植 + 浇水 + 生长，缺施肥、补种、温室。

### 3.4 陷阱与捕鼠
`TrapPanel`（162 KB）、`TrapSelectPanel`、`TrapFloatPopup`、`RatCage`
- 功能：放陷阱、选饵、收陷阱、捕鼠、老鼠逃脱（`RAT_CATCH` / `RAT_ESCAPE`）
- 配置表：`Trap`、`TrapBait`、`TrapLv`、`TrapRoomBias`、`TrapSlot`

**劫余录已有雏形**：`rat_trap` 捕鼠笼是一件可摆放的家具，21:00 自动从粮仓抓一把粮作饵，天亮按概率收到老鼠（`home.gd` 的 `bait_traps` / `dawn`）。
缺的是**饵的选择**和**陷阱种类**（原作分房间、分饵、分等级），现在只有一种笼子、一种饵。

### 3.5 能源与电器
`FuelGenerator` + `PowerUI/*FloatPopup`、`Heater`
- 功能：柴油发电机加燃料 / 退燃料、暖气开关、电力设施聚焦（`FOCUS_POWER_FACILITY`）

**劫余录（v0.7 已补上第一条）**：
- `diesel` 柴油（55 号物品，杂货铺有售，300 文 / 桶 / 负重 6）
- `generator` 柴油发电机（营造坊设施，2500 文）：**冷夜**自动烧一桶油转一整夜，`run.powered` 记着，天亮停机
- `heater` 装暖气（营造坊设施，1800 文）：发电机转着才起作用，体温每小时 +3（普通火是 +2，弱火 +1），上限 100，且**冻着睡觉不再打折扣**
- 没油就退回原来的炭 / 柴路径，night_lines 里会写"发电机里没有柴油"
- 仍缺：电器（原作有能开的电器）、太阳能 / 人力发电、无人机、机器人自动干农活

### 3.6 自动化（机器人 + 无人机）
| 面板 | 功能 |
|---|---|
| `RobotPanel` | 装机模块（`INSTALL_MODULE` / `UNINSTALL_MODULE`）、设自动修门 / 修地面 / 收割 / 收餐 / 播种施肥预设 / 修理阈值 / 主人指派 |
| `DroneHub` | 无人机机队、仓库对碰、商店、屏幕、高亮持有物 |
- 配置表：`RobotModule`、`RobotAttribute`

**劫余录没有**。这是原作的"减负"设计：中后期让机器人干重复农活，玩家去干别的。复刻可以先只做"自动修门 + 自动收割"两个模块。

### 3.7 仓储与物流
`BackpackUI`（410 KB，最大面板之一）、`AidDepot`、`GroundDock`
- 功能：双栏背包（A/B 两套）、拖拽移动、整类转移、快速转移、整理、丢弃全部、消毒喷雾、家具命名 / 打标签、标签规则、篮子愿望、污染值、老鼠来访、机器人标签引导
- 配置表：`Bag`、`Package`、`Item`、`ItemSubCategory`、`GroundLoot`

**劫余录已有**：背包 + 家具摆放，缺标签系统、污染值、双栏分流。

### 3.8 建造与装修
`BuildShop`、`BuildTips`、`FreeBuildMenu`、`RenovationPanel`、`FurnitureDetail`、`VasePanel`
- 功能：买家具、自由摆放、装修风格、家具详情、花瓶插花
- 配置表：`Furniture` + 11 张 `Furniture*` 子表、`RenovationStyle`、`Color`、`Structure`

**劫余录已有**：18 件家具 + 占地 / 通道 / 造价 / 重修。缺装修风格、花瓶。

### 3.9 据点里的杂项
`CampPanel`、`CasualHome`、`SignalStation`（信号台）、`PhoneSMS`（手机，361 KB）、`TVGame`（电视小游戏）、`MusicPanel`、`FeedingUI`（投喂）、`ActionEcho`（行动回显）、`TriggerUI`（触发器）

其中 **`PhoneSMS` 值得单独注意**：26 种消息，包含
- 对话 / 群聊 / 选项回复（`CLICK_REPLY_OPTION`、`CLICK_GROUP_REPLY`）
- 援助平台（`OPEN_AIDPLATFORM_APP`、`ACCEPT_AID_REQUEST`）
- 高利贷（`OPEN_LOANSHARK_APP`、`SUBMIT_LOAN`）
- 记录 App（`OPEN_RECORD_APP`、`SET_RECORD_DOT`）
- 静音 / 免打扰、清空会话、选择用途 / 档位

**这是原作把"叙事 + 经济 + 社交"全塞进一个手机 UI 的设计。**《劫余录》要做手机的话，这是一个现成的结构范本。

---

## 4. 外出探索（5 个面板 / 13 种消息）

`ExploreMap`（178 KB）、`MapPointDetailPopup`、`MapPointRiotDialog`、`RiotGrabResult`、`Minimap` / `MinimapFull`
- 功能：地图点详情、前往、昏暗度、每日次数、**地点沦陷**（`MapPointRiotDialog`）、哄抢结果
- 配置表：`MapPoint`、`MapRoom`、`MapSlot`、`ExploreLv`、`Instance`、`Vehicle`

**劫余录已有**废墟探索 + 地点状态，缺"沦陷"和"哄抢"这两个状态迁移。

---

## 5. 守夜战斗（1 个面板 / 1 种消息）

`TowerWaveReport`（尸潮战报）
- 配置表：`TowerWave`、`TowerWaveReward`、`TowerDevice`、`TowerZombieType`、`DefenseLv`、`Crisis`
- 面板只有 1 种消息，说明战斗主体在 3D 里（`TowerWaveManager` / `TowerCombatManager`），UI 只出战报

**劫余录已有**：院门攻防、撞门、啃咬、斩尸、架刀格挡、守夜方针对照（hold / fight / manual）。**这块是对得最齐的。**

---

## 6. 叙事与图鉴（10 个面板 / 21 种消息）

| 面板 | 功能 |
|---|---|
| `SurvivalLogs`（290 KB） | 生存日志本体——按日期的记录流 |
| `TruthRecorder`（94 KB） | 真相记录仪（收集线索拼真相） |
| `DossierUI`（108 KB） | 人物档案 |
| `Codex` | 图鉴（条目 + 标签页） |
| `EventChoice` | 事件选项（含 `.legacy` 旧版） |
| `NeighborMonologue` | 邻居独白 |
| `EndingChoice` / `EndingShow` | 结局选择 / 结局演出 |
| `Announcement` | 公告 |
| `WishTipsUI` / `WishFinished` | 愿望提示 / 愿望完成 |
- 配置表：`Event`、`EventLog`、`Story`、`Chapter`、`SMS`、`SMSGroup`、`SMSSender`、`CityChat`、`Broadcast`、`NpcMonologue`、`Wish`、`Goals`、`Achievement`

**劫余录弱在这一块**：现在只有 `events.json` 的随机事件文本和"生死簿残页"。原作是把叙事做成了**一整套可收集、可回看、可拼凑的档案系统**。

---

## 7. 轮回 meta（13 个面板 / 32 种消息）

| 面板 | 功能 |
|---|---|
| `RebirthChoice` | 死后轮回选择 |
| `RebirthUpgrade` | 轮回强化 |
| `SettleBeliefPoints` | 信念点结算 |
| `PlanTalent` / `TalentPop` / `SkillLevelUpPopup` | 天赋规划 / 弹窗 / 升级 |
| `EndlessSettlement` | 无尽模式结算 |
| `DailySettlement` / `Settlement` | 每日 / 常规结算 |
| `GameResult` / `RewardList` | 结果 / 奖励清单 |
| `Achievement` / `DataStatistics` | 成就 / 数据统计 |
| `DifficultySelect` / `ChallengeSetup` / `RogueSelect` | 难度 / 挑战 / 肉鸽入口 |
- 配置表：`DifficultyParam`、`DifficultyPreset`、`ChallengeAbility` / `Debuff` / `Target`、`EndlessTier`、`EndlessCrisisPool`、`EndlessWeatherPool`、`DailyScore`、`DailyRandom`、`Talent`、`DeathInfo`

**劫余录已有**：翻生死簿（回第 1 日 + 气血上限 + 残页）、天赋、解锁职业。缺无尽模式、每日随机、挑战自选。

---

## 8. 系统与设置（11 个面板 / 39 种消息）

`OutSetting`（88 KB）：设置项覆盖分辨率、窗口模式、帧率（含"降帧提示不再显示"）、画质档、三类音量（动作 / 环境 / 背景）、暂停时冻结渲染、加载卡死保护、按键重绑、成就、图鉴、购物车、Discord / QQ、Sentry 反馈、重开本轮、存档退出

其他：`SelectMenu`、`SpeedUp`（加速）、`ConfirmDialog`、`TipsPopup`、`GameCountTips`、`SmartRecommend`、`WorkshopUpload`（创意工坊）、`ItemDetailPopup`、`ItemPickup`、`PlanModeBtn` / `CancelPlanBtn`（计划模式）

**劫余录已有**：设置面板、加速。缺按键重绑、创意工坊、计划模式。

---

## 9. 建议的复刻优先级

按"结构价值 / 实现成本"排。**v0.7 已做完第 1 条的一半**（见 3.5：发电机 + 暖气 + 柴油）。

1. ~~补"精力 + 体温"两个属性~~ —— **已完成**（v0.5 就有了，见 3.1 的更正说明）；剩下的是给体温多加几条产出路，即本表第 4 条
2. ~~**灾前限时采购**~~ —— **已实现**（见第 2 节的更正说明）；~~载具~~ **v0.9 已补**（板车/独轮车/驴车）。剩下的是**挑战自选**（开局勾能力/减益/目标）
3. **陷阱 / 捕鼠**（`Trap` + `TrapBait` 两张表 + 一个每日检查动作，日常循环立刻充实）
4. ~~**能源 → 暖气 → 体温**~~ —— **v0.7 已做**：柴油发电机 + 暖气 + 柴油，见 3.5
5. **手机 UI**（照 `PhoneSMS` 的结构：短信 / 援助 / 借贷 / 记录四个 App）
6. **机器人减负**（先做自动修门 + 自动收割两个模块；现在所有行动都实打实耗精力，中后期会变成纯体力劳动）
7. **酿造 / 染色 / 压缩 / 粉碎**（四个小面板，机制相同，可批量做）
8. **叙事档案系统**（把现在的 `events.json` 升级成可收集、可回看的图鉴 + 档案）

---

## 10. 复刻时的注意

- **数值必须自己设计。** 原作数值全加密，抄不到；而且抄了也不合适——它的经济规模和我们的规模差一个量级。
- **面板数量不要照抄。** 95 个面板是 5 GB 资源堆出来的。劫余录应该合面板：原作的 `ToolTable` + `Cooking` + `Brew` + `Dye` + `Compressor` + `Shredder` 可以合成一个"工坊"面板带页签。
- **消息命名直接借鉴。** 原作 `WebUI_<面板>_<内容>Msg` 的 handler 命名和 `UnitySendEvent(<动作>)` 的调用方式很干净，值得照搬到 GDScript 的信号命名上。
- **这次拿到的只是 WebUI 侧。** C# 侧的类名来自 `global-metadata.dat` 的字符串推断（文档 01 已述），配置表数值仍未解密。
