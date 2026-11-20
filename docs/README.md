# 《劫余录》文档索引

## 从这里开始

| 想了解什么 | 入口 |
|---|---|
| 如何开始一局、回院、过夜和保存进度 | [玩家指南](player-guide.md) |
| 哪些玩法已经实现，哪些仍待验收 | [10 · 内容路线图](10-roadmap.md) |
| 接下来做什么，为什么要先收真人反馈 | [37 · 优化路线图](37-optimization-roadmap.md) |
| 本次目录清理、项目进度与未验收项 | [62 · 2026-11-20 项目审核报告](62-project-audit.md) |
| Steam 商店页、抢先体验问答与 Windows 上传配置 | [Steam 首发录入单](steam/README.md) |

下列专题保留对应版本的设计、实验和验收记录。阅读测试数字时请同时核对提交、运行方式和日期。

## 备劫、宅院与外出

- [09 · 挑战自选](09-challenge-mode-design.md)记录誓约、凭仗、了愿的组合与计分。
- [15 · 同院帮手](15-companions.md)说明备劫时带谁回家、各自做什么、每天消耗多少口粮。
- [16 · 工作台加工](16-craft-tradeoffs.md)记录三条配方的材料和机会成本。
- [31 · 宅院建设与周边街区](31-courtyard-construction.md)覆盖街景、家具搬动、装修、扩建、楼层和西邻。
- [27 · 等一刻](27-pacing.md)说明在宅院如何跳过空档，以及哪些事情会打断等待。
- [36 · 今日差事](36-day-agenda.md)说明如何分配有限的白天时间。
- [53 · 外出途中遇事](53-interrupted-field-time.md)记录中断后的赶路时间与搜寻完成后才授物的规则。
- [51 · 离线世情](51-offline-events.md)说明事件库、每日触发点与未见事件优先规则。

## 邻里、主线与轮回

- [11 · 隔墙求药](11-neighbor-medicine.md)记录阿宁支线的取药、交药和后果。
- [17 · 纸鹤交易](17-relationship-trade.md)说明报价、信用、借债、回礼与失约补救。
- [18 · 风声与危机](18-crisis-clocks.md)说明如何核实预兆、提前准备或在事后补救。
- [19 · NPC 自主行动](19-npc-autonomy.md)记录邻人的有限库存、行动与对话边界。
- [13 · 运行时世情导演](13-dynamic-director.md)说明开发版如何提前规划事件，以及哪些结果由本地规则决定。
- [20 · 调查与结局](20-mainline-endings.md)梳理义庄、青云观取证及坚守、撤离、破阵条件。
- [14 · 前世档案](14-past-lives.md)说明何时写入本机 `Memory.md`、哪些往事可供人物觉醒。
- [21 · 身份解法](21-identity-paths.md)记录四种身份的工法、成本和前世经验条件。
- [22 · 可变开局](22-variable-openings.md)说明哪些今世资源与人情会随开局选择改变。
- [23 · 轮回调查](23-cycle-inquiry.md)说明如何用今世证据查证旧诺、失约与救助。

## 玩家界面与文案

- [24 · 操作与画面设置](24-input-and-display-settings.md)列出默认键位、改键冲突与显示设置。
- [33 · 目标与今日要务](33-goal-brief.md)记录 HUD 倒计时和劫余录提示。
- [34 · 游戏内玩法说明](34-manual.md)记录首次提示、说明内容和入口。
- [42 · 劫余录三页](42-journal-tabs.md)说明如何从今世、人、前世三个页签找到原有入口。
- [43 · 夜战反馈](43-night-feedback.md)记录重复提示合并、后两轮镜头与夜间 HUD。
- [26 · 死因复盘](26-death-recap.md)说明残页如何展示一局的失血记录与最后一击。
- [38 · 文案规范](38-copy-style.md)收录界面与故事文案写法，以及第一轮审查。
- [39 · 屏幕上的规则文本](39-rules-on-screen.md)记录正文、悬浮提示和外出左栏的调整。
- [40 · 第五轮文案对照](40-copy-round5.md)保存各批改写前后的原句。
- [41 · 第五轮风格审查](41-copy-review.md)保存逐条评语、对白拼接检查与复检。

## 难度测量与真人试玩

- [08 · v0.8 难度实验](08-difficulty-balance-v0.8.md)保存早期固定策略的小样本及寒冷单项实验。
- [44 · 首轮 B4 重测](44-balance-retest.md)记录差事、外出策略、对照组和定向测量命令。
- [52 · 离线事件扩充后的重采](52-balance-after-offline-events.md)标明哪些旧样本受到外出耗时错误影响。
- [54 · 困难档校准](54-hard-difficulty-calibration.md)列出采用的倍率、独立种子组结果及仍未达到的目标。
- [35 · 长局稳定性](35-longrun.md)测量无尽模式的推进、运行耗时和存档增长。
- [30 · 试玩报告文件](30-playtest.md)说明报告、当前局快照和可选附件分别包含什么。
- [45 · 游戏内填写反馈](45-playtest-feedback.md)记录四处入口、三问表单、取消与导出。
- [57 · 试玩包核实与回收说明](57-playtest-gate-check.md)记录特定包与提交的对照、退出告警探针及试玩提问。

## 存档、测试与 Windows 构建

- [25 · 存档安全](25-save-safety.md)说明临时写入、备份轮换、坏档保留和恢复提示。
- [32 · 单局备份与搬运](32-save-pack.md)说明如何用 `.jyz` 文件导入或导出一局。
- [49 · 测试入口与 CI](49-test-entry-ci.md)说明如何列出用例、运行相关项、复跑失败项并查日志。
- [55 · 测试存储隔离](55-test-storage-isolation.md)记录裸跑测试与玩家目录发生混用的问题。
- [56 · 测试失败与历史残留清理](56-test-red-and-cleanup.md)记录两处失败的修复、旧夹具识别及备份位置。
- [50 · 独立 Windows 程序](50-windows-release.md)提供固定版本模板、干净提交构建和实际包验证命令。
- [28 · 初版 Windows 便携包](28-windows-build.md)保存首批便携构建的取舍与结果。

## 美术、声音与字体

- [03 · 素材清单](03-art-assets.md)记录模型、纹理、音效的来源、使用范围及授权说明。
- [46 · 守夜配乐](46-night-music.md)说明夜曲的合成来源及与三轮夜战的切换。
- [47 · 存货插画](47-inventory-art.md)记录 57 件物品的图集映射和窗口检查。
- [48 · 内置中文字体](48-bundled-fonts.md)记录字形覆盖、字重、字体来源与许可。

## 弹窗模块拆分记录

- [58 · 灶房、菜畦、营造、读书](58-dialogs-split-house.md)记录第一批控件树对照及阁楼入口复测失败。
- [59 · 存货、神龛与事件卡](59-dialogs-split-stock-shrine-event.md)记录含随机内容面板的对照方法。
- [60 · 劫余录](60-dialogs-split-journal.md)记录三页切换、面板高度和日志滚动状态的迁移。
- [61 · 三条调查线](61-dialogs-split-inquiry.md)记录主线、危机、轮回调查窗口及旧入口转发。

## 设计来源与原型历史

- [01 · 《生存日志》结构分析](01-survival-log-analysis.md)区分观察到的接口、资源和对实现的推断。
- [07 · 《生存日志》功能清单](07-survival-log-features.md)保存 2026-10-24 的功能对照，可用于回看早期取舍。
- [02 · 中国风世界与玩法设计](02-chinese-style-design.md)记录临川县、尸劫和生死簿的设定。
- [04 · v0.4 玩法诊断](04-gameplay-diagnosis.md)记录改动前的资源与生存曲线。
- [05 · v0.5 玩法方案](05-gameplay-plan-v0.5.md)记录体温、尸潮、事件与功德的早期调整。
- [06 · v0.6 三面夜防](06-night-defense-v0.6.md)记录三面、三轮、守夜方针和院门作战的初版。
- [12 · 邻居求药的 AI 策划评审](12-neighbor-ai-review.md)保存作者策划阶段采用和舍弃的建议。

## 配套文件

| 文件 | 用途 |
|---|---|
| [project-spec.json](project-spec.json) | 工程扫描规格，包括目录要求、动态资源引用与截图导入例外。 |
| [project-check.json](evidence/project-check.json) | 早期工程检查快照。其中的 3 个 autoload 和“没有定义任何输入动作”描述的是采集当时的工程。当前设置查 [project.godot](../project.godot)。 |
| [rea-webui-evidence-slim.json](evidence/rea-webui-evidence-slim.json) | 《生存日志》WebUI 分析摘录，供核对原作的取证范围。 |
| [47-inventory-art-prompts.json](evidence/47-inventory-art-prompts.json) | 存货图集的提示词、选定文件和 SHA256。 |
| [screenshots/](screenshots/) | 随仓库保存的画面记录。对照时请核对所属专题、当时版本和分辨率。 |

早期文档中的 `build/<批次>/...` 是开发机采集时的相对位置。重新克隆仓库不会得到这些生成物；本次移出的本地历史产物及恢复位置见本页顶部的项目审核报告。
