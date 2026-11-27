# 劫余录 · The Survivor's Ledger

在临川城用三天备荒，再回宅院熬过二十日尸劫。一次出城能多带一袋米，也可能错过交药或补门的时辰。熬不下去时，生死簿会记下死因与尚有的余地，下一世还能遇见记得旧事的邻人。

第一次玩可从[一局怎么玩](docs/player-guide.md)开始。当前进度见[内容路线图](docs/10-roadmap.md)和[优化路线图](docs/37-optimization-roadmap.md)。此前的[项目审查记录](docs/62-project-audit.md)与各批验证可从[文档索引](docs/README.md)查阅。

## 运行游戏

| 你手上有什么 | 从哪里开始 |
|---|---|
| Windows 试玩包 | 本机的 `build/model-craft-20261127/windows/` 可走过石拱桥，近看街坊衣装和别院陈设，也可去官仓查粮车、在米行寻访旧事「燕尾担」。保留目录内的文件，双击「劫余录.exe」即可离线玩。报告里的「本次运行的构建提交」可用来核对版本。 |
| 仓库源码 | 用 Godot 4.7.2 打开 [project.godot](project.godot)，首次导入完成后按 F5 运行项目。默认渲染器为 Forward+。 |
| 已按项目目录放好 Windows 引擎 | 双击 [启动游戏.bat](启动游戏.bat)。它使用 `tools/godot/Godot_v4.7.2-stable_win64.exe` 并尝试启动本地世情桥接器。 |

标题页「新开一卷」直接进城。「自选开局」可选身份、难度、誓约和同行者。已有旧卷时会先确认。源码版可选接入本机 Node.js 与已认证的 ARK CLI，让后台导演预排三日世情。独立 Windows 试玩包使用离线事件。[动态世情](docs/13-dynamic-director.md) · [Windows 试玩包](docs/50-windows-release.md)

Windows 默认玩家目录为 `%APPDATA%\Godot\app_userdata\劫余录\`。其中 `save.json` 记录当前一局，`meta.json` 保存跨轮回进度。可写源码工程在项目根更新 `Memory.md`。release 模板或只读项目写入玩家目录。搬到另一台机器时可使用游戏内的 `.jyz` 导出与导入。[存档安全](docs/25-save-safety.md) · [存档搬运](docs/32-save-pack.md)

## 开发目录

| 位置 | 内容 |
|---|---|
| [scenes](scenes) · [scripts/autoload](scripts/autoload) | 主场景、全局局面与存读档、设置、声音、异步导演 |
| [data](data) · [scripts/core](scripts/core) | JSON 配置和规则，包括备劫、时钟、外出、守夜、人情、结局与轮回 |
| [scripts/world](scripts/world) · [scripts/ui](scripts/ui) | 城镇、宅院、废墟、人物及镜头。界面入口在 screens，分拆的弹窗实现在 dialogs |
| [assets](assets) | 模型、材质、音频、中文字体和物资插画。发布所需的导入设置与许可随资源入库 |
| [tests](tests) · [tools](tools) · [.github/workflows](.github/workflows) | Godot 用例与夹具、离线运行器、导出、素材管线、可选导演桥接器与 CI |
| [docs](docs) | 玩法、路线图、专题记录；screenshots 收截图，evidence 收历史检查和素材证据 |
| 本机目录 | `build/` 保存当前构建与测试输出，`tools/godot/` 保存引擎和模板，`art-previews/` 保存本机美术稿。根目录 `Memory.md` 是玩家数据。 |

## 素材与仓库

部分铺面使用本机 cs-studio 素材，干净源码缺少该素材时会显示程序生成的厅堂。人物、家具、贴图、音乐和字体的来源分别记录在[素材清单](docs/03-art-assets.md)、[角色许可说明](assets/third_party/413games/NOTICE.txt)和[字体来源](assets/fonts/SOURCES.md)。

## 验证与构建

在仓库根目录运行。离线测试入口使用 Python 3.10+ 和 Godot 4.7.2，每次运行建立一个工程快照，同一次运行的各用例使用独立用户目录。先列用例，再运行本次改动涉及的项目。

```powershell
./tools/run_tests.ps1 -Tier core -List
./tools/run_tests.ps1 -Case brief
./tools/run_tests.ps1 -Tier ui -Case title_input
```

`tools/test_manifest.json` 列出各档实际覆盖与排除原因。日志和 `results.json` 位于 `build/test-runs/<运行ID>/`。全量测试留给发布候选。桥接器另有本地 Node 测试 `node --test tools/director/bridge.test.mjs`。[测试清单](tools/test_manifest.json) · [运行器与 CI](docs/49-test-entry-ci.md)

已有匹配的导出模板时，可从指定提交生成独立程序。下面的命令输出至本机候选目录。构建所用源码、引擎、模板与成品指纹随包记录。

```powershell
$sourceCommit = git rev-parse HEAD
powershell.exe -NoProfile -File tools/build_windows_clean.ps1 -Commit $sourceCommit -Mode release -OutDir build/windows-release-candidate
```

模板校验与导出步骤见[Windows 构建](docs/28-windows-build.md)。本机各试玩包的源码提交、已测范围与后续验收见[优化路线图 A3/A4](docs/37-optimization-roadmap.md#阶段-a--试玩与反馈)。
