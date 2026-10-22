# 《Survival Log / 生存日志》逆向分析报告

> 分析对象：Steam AppID 4164790，本地安装版本 1.1（资源清单 1.1.19131，分析当天 Steam 正在更新）
> 开发 / 发行：Midnight Workshop / Lilith Games
> 分析方法：REA（reverse-engineer-anything）CLI + 文件级静态分析。没有运行游戏，所以下文全部是**静态证据**，不代表观察到的运行时行为。

## 0. 证据来源与可信度

| 来源 | 内容 | 可信度 |
|---|---|---|
| REA `analyze-javascript-application`，Evidence `ev_cc15fbb0f209d3f635786798f1b04c2f5048ba1404c6f494c24902117c15d0db` | WebUI 目录：109 个相关文件，13 个 JS 文件解析成功，44 个通信边界，覆盖率 **partial** | 已观察（静态） |
| `global-metadata.dat`（IL2CPP v31，未加密） | 34,055 条字符串字面量（其中 3,805 条中文）、197,949 个标识符 | 已观察（静态） |
| `WebUI/UI/*/*.html`（约 100 个面板） | Vue 3 模板 + 内联脚本 + 中文文案 | 已观察（静态） |
| YooAsset 资源清单 | 511 个资源包，其中有 124 张配置表的文件名 | 已观察（静态） |
| Steam 商店页 | 官方玩法描述 | 第三方陈述 |

**没能拿到的：**
- 配置表的**具体数值**。511 个 `.bundle` 都做了**按文件派生密钥的流加密**：文件头不是 `UnityFS`，每个包的密钥流都不同，只有两个同组的包共用一条。要拿到数值，得在 `GameAssembly.dll` 里逆向 YooAsset 的解密服务，用 Ghidra 或 IDA 做原生分析。本次没做。
- 每个 HTML 面板里的**内联脚本**，REA 声明没有分析（见它的 limitations）。面板逻辑是我直接读源码得出的。
- 反编译后的 C# 游戏逻辑。下文的系统描述都是从类名、日志字符串和 UI 文案**推断**出来的。

## 1. 技术架构

```
SurvivalLog.exe（Unity 6000.2.7f2，URP，IL2CPP）
├─ GameAssembly.dll（105 MB，IL2CPP 原生代码）+ il2cpp.usym（符号）
├─ HotUpdate.dll（HybridCLR 热更新程序集）
├─ 资源：YooAsset（511 个加密 bundle，约 5.3 GB）
├─ 配置：MemoryPack 二进制表 Config_*.bytes（124 张）+ LocalTxt（中/英）
├─ 实体：Unity DOTS/Entities + ProjectDawn 寻路/避障（丧尸群）
├─ 音频：FMOD Studio
├─ AI：行为树（BtThinkingManager / FucBtManager / "Think*" 配置表）
└─ UI：Vuplex WebView（内嵌 Chromium）+ Vue 3 + Tailwind
       Root.html 管理多个全屏 iframe，每个面板一个 iframe
       面板 ⇄ C#：postMessage({ type, data, sourcePageId }) → Root → Vuplex 桥
```

UI 通信协议（`webui-core.js`，REA 边界节点在第 42–64 行和第 441–585 行）：
- 面板 → 游戏：`UnitySendEvent(action, data)` → `window.parent.postMessage`
- 游戏 → 面板：`registerHandlers({ 消息类型: fn })`，`data` 可以是 JSON 字符串
- 保留消息：`__CLICK_PASSTHROUGH__`（点击穿透）、`__QUALITY_TIER__`、`__CHEAT_MARK__`、`__INSPECT_MODE__`
- 所有文案先经过 `escapeHtml` / `safeHtml`，只放行 `<b> <br> <color>`

**对复刻的启发：** 原版是"数据驱动 + 事件总线 + UI 和逻辑完全分离"。复刻版可以照搬这个分层：配置表 → 管理器（Manager）→ 信号/事件 → UI。

## 2. 核心循环（推断）

```
 ┌─────────── 轮回（死亡 / 结局 → 信念点 → 学能力 → 重来）──────────┐
 ▼                                                                │
【灾前】倒计时 → 城区地图采购（超市 / 五金 / 农贸 / 装修公司 / 当铺）
   │  往返消耗倒计时；地点会"拥挤 → 骚乱 → 关门"
   ▼
【灾变】开场演出
   ▼
【灾后】每天循环：
   ├─ 维持属性：生命 / 饱腹 / 水分 / 心态 / 精力 / 体温
   ├─ 生产：种植 → 烹饪；陷阱捕鼠；工作台制造；酿造 / 染色 / 压缩 / 粉碎
   ├─ 能源：柴油发电机 / 人力发电 / 太阳能 → 储电 → 电器、暖气
   ├─ 外出探索：废墟超市、学校……（暴露值、昏暗、每日次数、地点会沦陷）
   ├─ 社交：手机短信委托、无人机交易、邻居救助（吊篮送食物）、高利贷、营地结盟
   ├─ 防守：每隔几天来一波尸潮（塔防：门窗耐久 + 电锯 / 电网 / 尖刺 / 沙包）
   ├─ 天气：暴风雨、寒潮、停电
   └─ 日结算 → 生存点 → 买"生存规划"卡（每天 3 选，可刷新，可锁定 1 张）
   ▼
【结局】坚守（转无尽）/ 带记忆重走（耗一次重生机会）/ 合上日志 / 安居（休闲模式）
```

## 3. 系统拆解

### 3.1 角色与属性
- 开局身份（`Config_PlayerSelect`）：打工仔、上班族、大学生、仓库管理员等，每个身份带"特质"。
- 属性（标识符）：`Health`、`Satiety`、`Water`、`Mood`、`Stamina/Energy`、`TemperatureUpdate`；外出时有 `ExposureValue/ExposureLimit`。
- 暴露值：走动、翻找会让它上涨，跑步涨得最快；涨满就会被丧尸发现、围攻受伤，随时可以撤退。
- 熟练度六条线：制造 / 种植 / 烹饪 / 捕猎 / 探索 / 防御。获取途径是做对应的事、首次解锁、读专业书、用家具"研究"（每天 1 次）。

### 3.2 灾前阶段（`PreDisasterMap`、`ShopUI`、`TradeUI`、`ChecklistManager`）
- 有倒计时，出门往返会消耗时间。
- 地点状态会随时间推进：正常 → 拥挤 → 骚乱 → 已关门。
- 必去：装修公司，决定灾后有哪些功能设施。推荐顺序：先订设施 → 囤食物 → 补种子。
- "囤货清单"按类别评估储备（不足 / 适当 / 宽裕），灾变后清单冻结。

### 3.3 灾后据点
- 多层安全屋 + 自由摆放家具（`FreeBuildMenu`、`BuildTips`、布局模式）+ 装修（墙纸 / 地板 / 染色）。
- 网格背包（俄罗斯方块式）：有负重；食物有保质期；**霉菌每隔几小时向相邻格蔓延**，可以喷消毒剂；冰箱冷藏。
- 烹饪（`Cooking`）：锅 + 食材 + 调味料 + 燃料队列。出锅前预测饱腹度和美味度，做好的菜分多次吃，每次加心态；组合不当会出"黑暗料理"；已知菜谱必定成功，新组合要出锅才揭晓。
- 种植（`PlantPanel`、`GreenhouseBuild`、`AddFertilizer`）：盆栽和温室，肥料加速，作物会出现异常，有一键巡田。
- 陷阱（`TrapPanel`）：诱饵（按保质期自动补位）、房间加成、捕获概率明细、储物仓。
- 电力（`PowerGridManager`、`FuelGenerator`）：储电、发电、停电。暖气有体感温度、区域系数，部分区域是锁温区。

### 3.4 尸潮塔防（`TowerWaveManager`、`TowerCombatManager`、`Config_TowerWave/Device/ZombieType`）
- 开波前会预告，波次带词缀：人海 / 铁壁 / 双线 / 夜袭。
- 门窗有耐久，装置有耐久和停转阈值，波后出战报（击杀数、装置损耗、门窗损耗）。
- 可以向结盟营地求援（营地会帮你引走一部分丧尸，有冷却）。
- 休闲模式按"旬"（10 天）推进，节奏分平静 / 事件期 / 高峰 / 休整，可以调整警戒等级。

### 3.5 外出探索（`ExploreMap`、`ExploreManager`、`Config_MapPoint`）
- 探索点有主要产出、每日进入次数、单程耗时。
- 地点会"沦陷"（有倒计时）或"被啃过"（货架要几天才恢复）。
- 昏暗地点需要手电。

### 3.6 叙事与社交
- 手机短信（`PhoneSMS`、`Config_SMS*`）：委托、交易信、事件气泡。
- NPC 对话表：五金店老板、农贸市场、邻居姑娘、恶邻、囤货男、当铺店员……
- 邻居救助（`NeighborRescue*`）：用吊篮给邻居送吃的，有好感度，她会回礼。
- 动态事件（`Config_Event`、`DynamicEventManager`）：事件分类有主线、危机、需求、救援、真相、陪伴、陌生人……
- 心愿（`Config_Wish`）：吃到某种食物等，完成后加生存点。
- 真相记录（`TruthRecorder`）、图鉴（`Codex`）、成就。

### 3.7 Meta 循环（Roguelite）
- **日结算**（`DailySettlement`）：生存点 = 每日基础 +5 + (心态 − 50) ÷ N（心态低于 50 不计）+ 心愿数 × 1 + 事件奖励 + 存量利息（5%，最少 1、最多 10）。
- **生存规划**（`RogueSelect`）：花生存点激活规划卡，每天 3 张，可以刷新，可以锁定 1 张。
- **信念点 / 能力**（`PlanTalent`、`SettleBeliefPoints`）：死亡后结算信念点，轮回时学能力。
- **重生**（`RebirthChoice`）：可以翻回昨天、五天前或扉页（代价是生命上限降低），也可以撕掉这一轮重写（不消耗重生机会）。重生次数有限。
- **结局后**：转无尽存档 / 带记忆重走 / 合上日志 / 转休闲存档（每 5 天一波，30 天一季）。
- 模式：剧情（生存 20 天）→ 解锁无尽 → 极限挑战；另有休闲"安居"模式。

## 4. 124 张配置表（只有名称，数值已加密）

按系统分组：
- **角色/属性**：Player、PlayerSelect、PlayAttribute、AttributeStandard、Buff、Effect、Talent、DeathInfo
- **物品/背包**：Item、ItemSubCategory、Bag、Package、FoodType、RewardSet、RandomGroup、GroundLoot
- **家具/建造**：Furniture、FurnitureCook/Electrical/Func/Partner/Plant/State/SubSlot/Tag、RenovationStyle、Color、MaterialRack、Structure
- **生产**：CookingRecipe、CookingLv、Plant、PlantLv、PlantPigment、ProductionList、ProductionLv、Trap、TrapBait、TrapLv、TrapRoomBias、TrapSlot
- **时间/天气**：Date、DateTimeline、DayLight、DailyWeather、Weather、EnvArea、EnvAreaWeather
- **地图/探索**：MapPoint、MapRoom、MapSlot、ExploreLv、Instance、Vehicle、Shop、ShopFurniture、StrangerStock、StrangerProfile
- **防御**：TowerWave、TowerWaveReward、TowerDevice、TowerZombieType、DefenseLv、Crisis
- **叙事**：Event、EventLog、Story、Chapter、SMS、SMSGroup、SMSSender、CityChat、Broadcast、NpcMonologue、Wish、Goals、Achievement、Codex
- **难度/模式**：DifficultyParam、DifficultyPreset、ChallengeAbility/Debuff/Target、EndlessTier、EndlessCrisisPool、EndlessWeatherPool、DailyScore、DailyRandom
- **AI**：ThinkActionType、ThinkEvent、ThinkExplore、ThinkFloor、ThinkOpen、ThinkTime、Action、ConditionSet
- **机器人/救援**：RobotModule、RobotAttribute、AidCommission、AidDemandPool、NeighborRescue*

## 5. 结论

1. 这款游戏的核心是**"灾前限时采购"和"灾后据点经营"两段式**，外加以日志为叙事载体的**轮回 meta**。复刻的重点是这个结构，不是 3D 表现。
2. 原版规模很大（约 100 个 UI 面板、124 张表、5 GB 资源），复刻要做**垂直切片**：先跑通"灾前 → 灾后 N 天 → 尸潮 → 死亡/结局 → 轮回"这一个闭环。
3. 数值没拿到。复刻版的数值需要自己设计，这也避免了直接搬运原作内容。
