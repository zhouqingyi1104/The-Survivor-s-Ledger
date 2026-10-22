# 劫余录 · The Survivor's Ledger（原型 v0.4）

古风尸变 + 写实灾荒 + 一点东方仙侠的生存模拟。玩法结构、界面布局和交互方式参考《Survival Log / 生存日志》（灾前囤货 → 灾后经营 → 轮回），文本、数值、图标都是原创——没有从原版提取或复用任何美术资产。模型和贴图一部分是公开的免费素材（Poly Haven、cs-studio、Quaternius），其余用代码拼；来源和许可证见游戏标题页的"制作名单"和 [docs/03-art-assets.md](docs/03-art-assets.md)。

- 原版逆向分析：[01-survival-log-analysis.md](docs/01-survival-log-analysis.md)
- 中国风设计：[02-chinese-style-design.md](docs/02-chinese-style-design.md)
- 美术资源清单与接入情况：[03-art-assets.md](docs/03-art-assets.md)
- **玩法诊断（v0.4 实测）**：[04-gameplay-diagnosis.md](docs/04-gameplay-diagnosis.md)
- **玩法完善方案（v0.5）**：[05-gameplay-plan-v0.5.md](docs/05-gameplay-plan-v0.5.md)
- **夜战三式（v0.6）**：[06-night-defense-v0.6.md](docs/06-night-defense-v0.6.md)
- 截图：[docs/screenshots/](docs/screenshots/)（v0.4 的是 `*_v4.png`；v0.6 的夜战见 `night_policy.png` 与 `night_panel.png`）

## 运行

引擎是 Godot 4.7.2（Forward+ 渲染器，需要支持 Vulkan 的显卡）。本地开发时放在 `tools/godot/`；这个目录 255 MB，**不在仓库里**，克隆后要自己下一份（[godotengine.org](https://godotengine.org/download) 的 4.7.2 stable，Windows 版解开后把可执行文件放进 `tools/godot/`），或者直接用你装好的 Godot 打开 `project.godot`。

用编辑器打开：

```bash
./tools/godot/Godot_v4.7.2-stable_win64.exe --editor --path .
```

直接运行游戏：

```bash
./tools/godot/Godot_v4.7.2-stable_win64.exe --path .
```

存档在 `user://save.json`，跨轮回的记忆（道心、心法、残卷）在 `user://meta.json`。旧版本的存档读档时会自动升级（`scripts/core/migrate.gd`）。Windows 上的位置是 `%APPDATA%\Godot\app_userdata\劫余录\`。

## 一局怎么玩

有声音：古筝配乐、风雪、脚步、打更（更鼓 + 梆子）、赶尸铃、尸潮的铜锣与低吼，标题页和游戏里的"设置"可以调三路音量（宅院里按 Esc）。

三个 3D 场景，徽派风格（粉墙黛瓦、马头墙）。宅院的家具是 Poly Haven 的写实中式家具，墙、地、瓦、雪是 PBR 贴图；临川城的大半铺面是 cs-studio 的中式建筑；人物是 Quaternius 的骨骼人物换上袍服、配上走路 / 干活 / 坐卧 / 倒地等动作，僵尸平举双臂蹦着走。其余构件（屋架、马头墙、守具、冠帽黄符）还是代码拼的。

| 场景 | 操作 |
|---|---|
| **临川城**（备劫） | 点铺子（或左边的地名）走过去，到了自动打开货架。右键拖动转视角，滚轮缩放 |
| **宅院**（劫中） | 鼠标移到物件上会描边、显示名字；**左键点物件**弹出动作菜单，人自己走过去做；左键点地面走过去；也可以 WASD 走、E 对最近的物件弹菜单。右键（或中键）拖动转视角：左右转向、上下调俯仰；滚轮缩放。人被墙或屋顶挡住时会透出金色剪影。空格暂停 / 继续，1 2 3 切倍速，N 就寝，I 存货，J 劫余录；**院门口有活人时左键 / J 挥刀、K 或右键单击架刀** |
| **废墟**（外出） | 提灯笼走到发金光的地方按 E 翻找，回门口按 E 回家 |

1. **备劫三日**：在临川城里跑铺子囤货。走动耗时辰，独轮车有负重上限，酉时宵禁。铺子会从"正常"变成"拥挤"再到"哄抢"，门口人越来越多，米行第三日午时关门。营造坊（★）的活计要在第二日前订。时辰还多时歇下、或最后一天入夜前，都会先确认。
2. **尸劫降临**：之后是**连续时间**，右上角有时辰表盘，左下角调倍速（❚❚ ▶ ▶▶ ▶▶▶）。做事要花时间：做饭一个时辰、打理菜畦四十五分钟、读书两个时辰……忙的时候时间自动加速，睡觉更快。一天的节奏：8:00 可能来事件，18:00 天黑，20:00 自动烧炭取暖，21:00 外出的必须回家、有尸潮的夜里同时要**布防**，22:00 尸潮，次日 6:00 天亮结算**功过格**。
   - HUD 参考原版布局：左上菜畦清单（带倒计时）、今夜预警和**布防守力预测**，右上第几日 / 时刻 / 表盘 + 印章按钮 + 院子温度，右下状态条，左下背包 + 常用行为 + 倍速，底部正中心愿。
   - 场景里：菜苗头顶挂长势和剩余时间，忙的时候头顶有进度条，门受损时挂耐久；米袋、柴垛、木料按存货多少摆，守具摆在门外街上；干活时手上有动作，睡觉时人躺在床榻上。
3. **入夜**：有尸潮的夜里，僵尸分三轮（22:00 / 22:40 / 23:20）撞**院门、窗、院墙**三个面，每个面独立算守力和耐久，破了就从那儿进院子。
   - **21:00 定守夜方针**：**稳守**（亲守院门，间隙自动修最破的一面，不碰面板也能活）/ **亲战**（亲守最吃紧的一面，每到间隙提刀出门砍会漏的那一路，用气血换安全）/ **亲自调度**（全手动）。夜里随时按 `F` 或点右上「夜战」接管。
   - **轮间只够做一件事**：修缮（木料 1，耐久 +40）/ 贴符（符、狗血、糯米换这一面守力 +8/+6/+4）/ 布守具（按守具归属挂到对应面）/ **开门迎敌**（不换场景，就在院里）。
   - **院门是开关**：关着，僵尸只能砸门（每 1.25 秒 −2 耐久）；开着，这一轮本该撞门的最多 5 只直接走进院子，啃菜畦、扯米袋、踢柴垛、砸家具。你可以出门迎上去，左键 / J 挥刀，铜甲两刀，被咬一口 5 气血。**开门是用院子里的东西换门的耐久。**
   - **架刀**：`K` 或右键单击（右键拖动仍是转视角）。抬起后 0.35 秒内咬进来的那一口被架住——不掉血、把僵尸推开 1.4 米并让它趔趄；收刀 1.15 秒，架成功只算 0.6 秒。一次只挡一口，被四五只围住时只能救自己一回。
   - 被啃过的院子**看得见**：原地留碎屑和暗渍，砸掉的家具当场塌成一堆木料，米袋、柴垛、菜畦按新数量重画。
   - **砸烂的家具要重做**：灶台 / 工作台塌了会一直塌着（存档也带着），点它只剩「重修」——木料 2 + 铁钉 1、一个半时辰。修好之前做不了饭、也修不了门窗。**开门放僵尸进来，代价能延续到第二天。**
   - **添置家具**：工作台 →「添置家具…」，18 件里挑一件，回到院里**点地面放下**（`R` 转向、`Esc` 取消）。屋里院里的空地都能摆，只是不能堵住门口到正屋的中路、不能和已有家具挤在一起；料不够或已到上限的会直接写出来。摆好的点它就能**拆掉，退一半料**（向下取整）。
   - 演出仍是「先算后演」：第一轮有 3D 演出（可以跳过），后两轮以面板和战报呈现。功德可以在**神龛求签**（同一天求得越多越贵）。
4. **死亡**：翻**生死簿残页**——翻回昨日（折寿元）、翻回扉页（结算道心重来），或者合上此录。
5. **劫满**：熬过第二十夜，可以守宅（转无尽）、再入轮回或合上此录。道心用来参悟**心法**（永久能力）。

## 目录

```
data/                 配置表（JSON），对应原版的 124 张 Config_* 表，改数值只改这里
scripts/core/         纯逻辑，不依赖界面，可以无界面测试
  data.gd  rng.gd  inv.gd  state.gd       读表、可存档随机数、物品仓、局面状态
  pre.gd                                   备劫：走动、买卖、当铺、营造订制、囤货清单
  post.gd                                  劫中：每日流程、时段行动、入夜
  defense.gd  explore.gd  events.gd        尸潮夜袭、外出搜寻、随机事件
  ledger.gd                                功过格、求签、心愿、道心、生死簿快照
scripts/world/              3D 场景
  assets.gd                                第三方素材：PBR 材质、家具模型、铺面模型
  kit.gd  arch.gd  props.gd                色板与基本体、徽派建筑构件、家具 / 物资堆 / 作物 / 守具
  character.gd                             骨骼人物与僵尸（换色、冠帽、动作状态机）
  figure.gd                                旧的程序拼的人物（已不用，留作参考）
  player.gd  cam_rig.gd  sky.gd            主角移动与寻路、跟随镜头、天光雾雪
  outline.gd                               悬停描边
  home_world.gd  wave_show.gd              宅院、入夜尸潮演出
  city_world.gd  ruin_world.gd             临川城、外出废墟
scripts/autoload/game.gd   全局单例：当前一局、存读档、界面切换
scripts/autoload/audio.gd  声音（Sfx）：音效、环境声、配乐，三条总线
scripts/ui/                界面（全部用代码搭）：ui_kit.gd 纸本主题，hud_kit.gd 场景 HUD 主题，widgets/ 时辰表盘，
                           main.gd 弹窗层，dialogs.gd 各种弹窗，
                           screens/ 各界面（pre / post / explore 是 3D 场景 + HUD，其余是 2D 页面）
scripts/dev/demo.gd        截图演示场景
assets/third_party/        下载的原始素材包（Poly Haven 模型贴图、cs-studio、Quaternius）
assets/models/             转换后的模型：buildings/（cs-studio 铺面 GLB）、characters/（换好衣服的人物 GLB）
tests/                     无界面整局模拟、界面冒烟测试、脚本编译检查；city_shots 逐个拍城里的铺子
```

一局的全部状态是一个 Dictionary（`Game.run`），所以存档就是 JSON，翻生死簿就是深拷贝快照。

## 测试

三个测试都在无界面模式下运行：

```bash
./tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/sim_test.gd
```

```bash
./tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/ui_smoke.tscn
```

```bash
./tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/check_scripts.tscn
```

- `sim_test`：两种机器人策略各跑多局，检查属性、库存、耐久等不变量，并打印平衡数据；另测翻生死簿和旧存档迁移。主动策略应该大多能劫满，偷懒策略（不出门不布防）应该在中后期死掉。
- `ui_smoke`：在 3D 场景里走完整流程：城里走路订货买货、熬过三日、宅院里寻路去打水、做饭吃饭、进废墟翻找回家、天黑就寝、天亮翻功过格、第二夜尸潮演出与战报、存读档、翻生死簿、合上此录。存档写到测试专用文件，不会碰你的存档。
- `check_scripts`：把所有脚本加载一遍，确认都能编译。

开发用的体检工具（会弹窗口）：

- `tests/play_check.tscn`：在真实界面里体检宅院——导航网格覆盖图、点地面走路、打水后能否接着走、真实鼠标的点击 / 右键拖动 / 滚轮、遮挡截图、不锁帧的帧时间和绘制调用。可以读一份存档的副本（只读不回写）：`-- --save=<路径> --shots=<截图目录>`。
- `tests/anim_speed.gd`：量走 / 跑动作原本的步速，人物按实际速度挑步态、调播放速度就靠它量的数。
- `tests/city_shots.tscn`：逐个拍城里的铺子，检查模型朝向和比例。

截图（会弹出一个游戏窗口，截完自动关闭）：

```bash
./tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 -- --demo=post --shot=res://docs/screenshots/post.png
```

可用的 demo：`title credits roles talents pre crowd post closeup hall kitchen menu night sleep wave wave_blood dawn cook garden build omens inventory explore_pick explore plan night_panel gate_fight wreck furnish event dead ending`。演出类的加 `--delay=6` 截到中途。

## 导出注意

`data/*.json` 不是 Godot 资源。导出时要在导出预设的"资源 → 非资源文件过滤"里加上 `*.json`，否则发布包里读不到配置表。

## 素材与仓库

- cs-studio 的铺面**不得再分发素材本身**：打包进游戏可以，但 `assets/third_party/cs_studio/` 和由它转换的 `assets/models/buildings/` 不能放进公开仓库，`.gitignore` 已经排除。别人拿到代码后要自己去 itch.io 领一份（免费），按 docs/03-art-assets.md 里的步骤转换；缺了这些文件时，城里的铺子会自动退回代码拼的厅堂。
- Poly Haven、Quaternius 是 CC0，可以入库；但原始压缩包很大（约 200 MB），`.gitignore` 只排除了压缩包和解包目录，保留游戏实际用到的文件。
- 人物贴图原图是 2048，导入时限制到 1024（`.import` 里的 `process/size_limit`），屏幕上看不出差别，显存省四分之三。所以 `.import` 文件要跟着入库，不能忽略。
- 引擎（`tools/godot/`，255 MB）和 `.workbuddy/`（本地工作记忆）不入库。
- 仓库：[github.com/zhouqingyi1104/The-Survivor-s-Ledger](https://github.com/zhouqingyi1104/The-Survivor-s-Ledger)

## 原型的边界

- 美术是公开素材和代码模型混搭：写实家具、低多边形铺面、程序构件放在一起，风格还不够统一；人物底模是"超级英雄"体型，袍服是从身体网格派生的，近看偏紧身。
- 声音只有两首配乐（平静 / 激战），夜里没有专门的配乐；音效是通用素材加合成的中式声音，没有人声。
- 米行、铁匠铺、药铺和家宅还是代码拼的厅堂（免费素材包里没有合适的）。
- 宅院只有一层；原版是多层（二楼 / 家 / 地下室）带楼层切换。
- 备劫（临川城）的 HUD 和弹窗还是宣纸风格；宅院、废墟上的弹窗已经换成和 HUD 一致的夜色。
- 尸潮是"先算结果、再演出来"。v0.6 把一夜拆成三轮，轮间可以修墙、贴符、布守具、出门迎战，但每一轮本身仍是结算，不是实时砍杀。
- 体温在 v0.5 才真正咬人：柴炭断供后第 3 夜起每晚固定掉血，白天最多回暖到 60；想更硬就调 `scripts/core/post.gd` 顶部的 `RATE`。
- 备劫三日还是按时辰的回合制（走一趟扣几个时辰），只有劫中是连续时间。
- 字体用的是系统楷体（KaiTi）。别的系统上会回退到其他中文字体，正式版应该内置一套开源字体。
- 数值只用机器人策略粗调过，还没经过真人试玩。
- 纸鹤交易、邻家小妹、真相线目前都还是随机事件，没有成体系。
