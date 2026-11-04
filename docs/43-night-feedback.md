# B3 夜战观感（2026-11-04）

用户明确选择先推进 B3。目标是让夜战信息更集中、第二和第三轮有可见反馈；真人试玩结论仍缺，不将这一批视为 A4/A5 完成。

## 玩家能看到的变化

- 同句提示复用一条，累计 `×N`；每次续满 2.2 秒，之后淡出 0.6 秒。淡出中重发也恢复原条，不叠出第二条。不同原文各自显示，彻底消失后重新计数。
- 第二、三轮结算后聚焦受袭面 2.2 秒，可点“跳过”。新撞破的一面优先，其次比较实际进院数、损伤和来袭数。横幅和场景均使用本轮实际结果，开门迎敌不会写成守住。
- 夜里及实时迎敌时收起菜畦、邻里/主线/轮回任务卡和今日差事行；白天且战斗结束后恢复。保留预兆、守面、物资、属性与时间控制。
- 演出时暂停人物和即时迎敌，结束后才开轮间面板或整夜战报；致命一轮演完进入残页，中途离开释放场景锁。

规则计算仍只调用一次 `Post.nod_round`，新增演出读取其返回值，不改 core 战斗数值或规则随机状态。

## 验证

Godot 4.7.2；所有进程的 `APPDATA`、`LOCALAPPDATA` 隔离至项目 `build/`。窗口检查使用 Compatibility、1280×720、视口鼠标事件，采用受控战斗边界夹具，不代表自然整夜试玩。

| 检查 | 结果 |
|---|---|
| `tests/toast_merge.tscn`（headless） | 24 项、0 失败：原文键、续命、真实淡出中重发、过期重生、不同原文、旧回调身份 |
| `tests/night_feedback.tscn`（真实窗口） | HUD 显隐、第二/三轮聚焦、跳过与自然结束、实时战斗恢复、致命第三轮转残页、首轮跳过、演出中换场均 PASS |
| 同帧真实入院事件 → `Game.toast` → 提示层 | 5 次入院只产生一条 `×5`，PASS |
| 演出与纯核心对照 | 时间、属性、门窗墙、夜战报告、斩杀、守具、即时战斗与规则随机状态一致，PASS |
| `tests/check_scripts.tscn` | 90 个脚本、0 编译失败 |
| 独立对抗式审查、`git diff --check` | PASS；审查发现的破损画面未同步、开门误写守住、差事行未收起均已修正 |

夜战测试最初先修正测试本身的鼠标路由和弹窗键名（实际键为 `night`）。窗口联通后从第二项继续运行，40 项、0 失败。独立审查修正后，仅回跑受影响病例：HUD 7、第二轮 15、开门迎敌 11、第三轮 9、致命一轮 7，均 0 失败。没有为重跑而重复执行全量测试。

运行方式（先在当前进程设置隔离目录）：

```powershell
& tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/toast_merge.tscn
& tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method gl_compatibility --resolution 1280x720 res://tests/night_feedback.tscn
& tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/check_scripts.tscn
```

夜战可用 `-- --only=test_second_round` 等参数只回跑一个病例；`--from=test_second_round` 从该项继续。真实窗口截图保留于本机 `build/b3-qa/shots/`，已目视检查夜间 HUD、破窗与院墙镜头、入院合并提示。首版破窗截图曾显示上轮窗棂；修正后断言实际窗棂节点减少并重新出图。

## 未验收范围

- 真人完整一局、长期平衡、CI、全量模拟、导出发行包：**NOT RUN**。本批不调整 B4 数值、不刷新旧试玩包。
- 退出仍有 RID/ObjectDB/resource 清理警告；编译与功能断言通过不等于清理无警告，本批未处理该工程债。
- 后两轮为短镜头和局部光效，未增加完整尸群演出；所有镜头、性能和玩家观感仍待试玩。
