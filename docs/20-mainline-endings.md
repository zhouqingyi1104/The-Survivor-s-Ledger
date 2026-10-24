# 二十日主线：取证、断运、撤离与破阵

2026-10-24。先规划再开发。目标是让「道士—义庄—青云观」成为本世实际可推进、可放弃、会改变尸潮和结局的内容链，保留原有生存、NPC与危机玩法。提交完成即正常推送并核对远端SHA。

## 玩家可见的结果

第3日08:00保证出现道士线索入口，不依赖随机事件。主线面板始终说明目的地、专属目标、耗材、施工/往返时间和截止。旧世残卷可读，但不能代替本世调查证据；拒绝道士、没救邻居也有自查路径。选择不调查仍能守满二十日。

| 节点 | 行动与成本 | 实际后果 |
|---|---|---|
| 道士，至第12日18:00 | 接待：清水1、柴1，30分钟、精力4；拒绝：不耗物资 | 接待完工后学画符、得镇尸符1/符纸2及道士残卷，开启义庄任务；拒绝/错过改走第5日起自查路线 |
| 自查替代 | 米1，60分钟、精力4，买下义庄旧路线 | 无赠符/画符教学，也能进入本世调查，不强迫先救邻 |
| 义庄专属目标 | 到「炼尸阵的运尸簿」，20分钟、精力4，外泄35；来回各60分钟 | 完成只取得贴身证物，成功完成返程才确认为今世证据；被尸群追上会丢失未交回证物，可重试 |
| 义庄证据处置 | 断运：镇尸符1、灯油1，60分钟、精力6；抄录：30分钟、精力4；封存：零成本并放弃本线后续 | 断运完工移除尚未开夜的第11/17夜「铜甲」；抄录保材料、尸潮原样；两者开启青云观任务。封存保物资、锁为坚守 |
| 青云观专属目标 | 「观主七灯图与后山道图」，20分钟、精力4，外泄35；往返各60分钟 | 实际取回才获得今世灯阵及出路证据。进入最终路线选择 |
| 坚守 | 零额外物资/时间，路线锁定 | 保留筹备物资，放弃撤离/破阵；守过20夜后21晨结案，可继续无尽 |
| 备撤离 | 第12日起，米3/清水3/木料2/铁钉1，90分钟、精力8 | 物资消耗用于行装和渡具，完工锁定撤离，不能同时用于破阵 |
| 实际撤离 | 第18日08:00至第19日18:00内完成，120分钟、精力10 | 完成才进入「离城余生」结局，不再守第20夜，不得领取守满20日奖励或直接回原宅继续 |
| 备破阵 | 第12日起，镇尸符2/灯油1/黑狗血1，120分钟、精力10 | 完工锁定破阵；仍须亲赴青云观阵眼施工 |
| 青云观封阵 | 「七星灯阵眼 · 按图封阵」，90分钟、精力10，外泄45，严格在第19日18:00前完工 | 现场完工才熄灯：第20夜移除血月，基础数量乘0.8；仍需对付残潮并活到21晨，得到「七灯俱熄」结局 |

所有关键施工走真实busy，开始付物资，完工生效；中断不退材料，也不免费生效。到期仍未完成的撤离/封阵明确收尾为转守宅，投入不退，不凭空杀玩家。撤离筹备必须留够后续120分钟，迟到不开工也不扣料。探索只调查的访问不刷新普通物资，不受物资搜空冷却卡死；同一访问的主线专点不吞邻人药账专点。搜索时不能在busy/睡觉/战斗中重复开工。

初始取证及返程均使用真实时钟：调查完工后贴身携带，返程另60分钟busy，返程完成才入账；惊动尸群、放弃未完成工作、期限不足均有日志。封阵现场生效，不需要把已经熄灭的灯搬回家才能影响尸潮。

## 规则与边界

- 新增 `scripts/core/mainline.gd`，run.mainline独立保存schema/revision/start_day/stage/evidence/route/interventions/work/ending/history，私有carried校验证物来源。存档v17，旧卷从当前时钟日之后开始，不追认已调查或破阵；当前局/快照一并升级。公开context不含carried或施工私有数据。
- stage：waiting/contact/fallback/mortuary/mortuary_choice/temple/routes/escape_ready/ritual_ready/sealed/hold/closed/failed/endless；公开后deadline固定。route为空/hold/escape/ritual；evidence仅本世mortuary、temple；interventions记录断运/封阵完成时刻。
- API：state/poll/view/options/act(run,action,token)/complete(run,data)/summary/context；objective(run,pid)/add_objective(run,pid,spots)/search_objective(run,spot)/begin_return(run,ex)；wave_effect(run,day)/finish_dawn(run)/ending(run)/continue_block(run)/continued(run)。
- view提供title/summary/goal/target/target_name/objective/costs/deadlines/evidence/route/interventions/token/last_result/history；options只提供本阶段action的id/text/hint/block。token绑定本世、revision与阶段，实际t校验期限。搜索标记mainline=mortuary/temple/ritual，与neighbor隔离。
- Post统一结算公开主线/中断/截止，新增事实进入Director；主线玩家动作失效未展示规划。Explore接专点与贴身证物、开始返程，真正完成才交证。原随机taoist退出新抽选，已显示旧事件仍可完成，不能据旧奖励自动补造今世证据。
- Defense新增wave_for_run(run,day)统一预报、布防、HUD与实际开夜；基础wave_for_day保持原样。所有修改先深拷贝，绝不改Data.table；已开始整晚的night.wave锁定，后续取证不能回改。
- Game/Ledger区分真实结局：坚守/破阵在20夜后享原劫满10分，撤离0劫满奖励；提前撤离不满足存活20日了愿。仅坚守允许继续无尽，破阵与撤离保留重开/合卷，重复点击不得重复结算。守到死不开自动20日结局，撤离禁用，调查干预仍可做。
- NPC支援复用已实际送达物资，主线不直接挪用NPC库存/当天计划/人情预留/交易回礼或欠账。危机只通过真实供给影响筹备，不读私有真假决定路线。
- Director只输入公开本世主线事实；AI不能输出clue/flag/wave/ending等新权限。主线公开期间普通AI自由事件使用本地效果文字，避免文案虚构完成调查/封阵；NPC受控多样表达照常。现有前世觉醒是本地确证事实，保持独立。
- Memory增加有界主线结算：真实本世证据、已完成干预、锁定路线、未完成筹备和实际结局；旧世完成状态不自动带到新世或未觉醒NPC。8000 UTF-16总预算不变。

## 分批交付

1. 方案及提交即推送约定，提交后立即push核对。
2. 核心主线、v17、独有目标、期限与反例。
3. 探索/返程/真实尸潮/时钟接入，精确验证不同分支。
4. 多结局结算、公开AI背景与旧世档案。
5. 主线面板、地图/E键调查及三结局界面，真实窗口鼠标与布局。

各批带必要依赖和测试；若跨模块互相依赖则同批提交。只运行本次相关与必要回归，先修第一真实失败再重跑该项，不跑发布全量。每批提交后正常推送，核对远端SHA，不force、不部署、不改.env/凭据/依赖。

## 必须验证

继承五残卷仍需取证；拒绝/错过道士有替代；专点与邻居并存；缺料、未来/过期/跨世token、双击、忙碌、睡觉、外出与中断不免费生效；返程未满60分钟无证据；暴露追捕丢证且可重试；冷却只开放调查不刷新loot；预报/实际一致且不改共享配置/整晚锁；三结局奖励/了愿/继续生活边界；日局无跨世捷径、旧局/快照迁移、存读档/回溯无重复；AI不造事实；最终合卷实际更新Memory而非假写测试。玩家整局、长期平衡、CI、导出发布若未运行均写NOT RUN。

## 本地交付与验证结果

玩家入口：宅院「调查 / 出路」，或「劫余录 → 尸劫来历 · 调查与出路」。面板显示专属目标、成本、期限、当前工作和本世记录；地图显示青云观封锁原因。现场调查显示剩余分钟，工作期间不能再翻找或跳过返程。熟练搜寻的四处普通物资可与邻人药账、主线运尸簿共存，六处物理位置各自可达。

| 实际执行 | 结果 | 验证范围 |
|---|---|---|
| Godot 4.7.2 headless `res://tests/mainline_rules.tscn` | PASS 253检查 | 本世证据、替代路线、工作成本、期限、跨世与重复操作、迁移与回溯 |
| Godot headless `res://tests/mainline_integration.tscn` | PASS 207检查 | Post真实时钟、追捕丢证与即时死亡、调查冷却、真实开夜减潮和预报一致、残潮后结案 |
| Godot headless `res://tests/mainline_memory.tscn` | PASS 83检查 | 三结局奖励/了愿/无尽边界、整轮去重、真实测试Memory写入读回、公开AI事实与恶意文案隔离 |
| Godot真实窗口 `res://tests/mainline_ui.tscn` | PASS 349检查 | 真实鼠标/E键、调查及返程存读与回溯、地图锁观、六目标可达、三结局按钮和实际合卷 |
| `node --test --test-name-pattern="mainline" tools/director/bridge.test.mjs` | PASS 4项 | 严格主线上下文、越权输出拒绝、模拟provider契约 |
| Godot实际导出5份虚构快照，Node严格校验 | PASS 5/5 | waiting、hold、escape、ritual、mortuary公开快照 |

必要相关回归均PASS：`npc_rules`439、`neighbor_story`419、`director_rules`34、`npc_integration`69、`crisis_integration`64、`social_trade_integration`430、`npc_memory`36检查；`memory_file_flow`9/9组68检查。交易旧fixture初次因新增主线公告多记一次revision而失败，隔离该fixture主线时钟后保留严格单次事实断言并重跑通过；主线与世界时钟组合由联合场景验证。本批未执行全量发布测试。

对抗检查修复：主线调查改为可见工作后，致命即时追捕必须在返回UI前检查死亡；预报/实际开夜先计算干预再写wave_day；物资冷却不足以完成调查时阻止空跑；六点共存不复用物理位置；工作中不标作已调查，被追捕也不把未搜点显示为已封阵。完整档案过长时压缩重复叙述，保留最新一世交易、危机、NPC与主线结算，8000 UTF-16预算和原始meta均保持。

已查看8张1280×720窗口图，开发机临时目录为 `ledger-mainline-{contact,map,six-targets,investigating,routes,hold,escape,ritual}.png`。窗口检查使用隔离里程碑状态及真实操作，并非玩家连续完成20夜。部分headless场景仍有4 ObjectDB/2 resources退出警告，最终窗口有CanvasItem/ObjectDB及4条GL纹理释放警告；本批未修复这些退出资源问题。

本批真实ARK调用0次，未更改玩家根Memory、凭据或依赖。玩家完整一轮、长期经济平衡、更多分辨率、CI、独立安装包与发行部署均NOT RUN。
