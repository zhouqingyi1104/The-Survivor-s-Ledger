# 独立 Windows 程序（2026-11-05）

状态：首版已实现，候选包定向验收完成。承接优化路线图 C2；2026-11-05 用户已明确批准下载并启用官方同版本模板。最终提交包的来源与验收结果另随包记录，不将候选对象或本地结果当作 CI/正式发行/玩家验收。

## 玩家得到什么

试玩包使用同版本 Godot 的 Windows x64 release 模板，提供独立 exe 与同名 PCK，沿用现有文件夹分发方式。程序带项目自己的图标，保留中文字体和完整许可、离线说明及干净来源；记录相对上一版便携包的实际体积变化。导出格式的 release 不等于已正式发行或玩家验收。

## 范围与验收合同

1. 新增构建依赖前遵循用户全局 AGENTS 规则「依赖变更先问」：官方 Godot 4.7.2 标准导出模板 TPZ，1,281,349,702 B，固定官方 URL、SHA512 与发布页摘要，放本项目忽略目录。只启用 Windows x64 release 模板及其必要数据；不升级现有引擎、不安装软件包、不动真实 `.env`。
2. `build_windows_clean.ps1` 增加显式 release 模式，仍从明确提交 `git archive` 提取，隔离用户目录。调用前捕获并验证模板与版本，复制到隔离构建环境使用，不能因 APPDATA 隔离丢失模板而静默降回 portable。保留现有 portable 路径，正式产物不含工作区改动或忽略素材。
3. 图标延续既有朱砂印章、旧纸与楷书方向，用项目自己的矢量资源接入工程和 Windows 导出设置。使用 Godot 4.7.2 内置 PE 资源修改，不新增 rcedit；不更改代码签名、证书、PCK 嵌入策略或游戏布局。
4. 仅做有证据的体积治理：排除测试、工具、文档与构建产物，保留实际运行需要的字体/贴图/音频/数据；不能为变小而缺字、漏图或丢声音。实际 exe/PCK 分别记字节与哈希，和 078fa1f 便携包对比。
5. 先补当前构建脚本测试的许可夹具，定向验证模板缺失/错版/校验失败、旧包保留、release 与 portable 正确分路及合法模板复制。失败只重跑对应项；不为过测试放宽现有来源或许可检查。
6. 从验证后的干净提交出包，使用真实导出 exe 核对 template/release/offline 特性、中文与实际 400/700 字重、57 件存货贴图、完整许可、数据表和资源；实际窗口检查标题、HUD/时钟、存货并验证存档往返。开发引擎运行的截图不能替代导出模板验证。
7. 新系统、数值调整、资产重绘、全量性能测试不在本批。保留文案及美术任务的未提交内容；按功能提交后立即正常推送并核对远端 SHA，读取 CI。下载/安装确认前继续文档、图标、脚本和夹具等独立工作，不执行依赖使用步骤。

## 未验收边界

无签名程序、独立机器的 SmartScreen/杀软表现、安装器、系统兼容矩阵、正式公开分发、真人整局与其它路线图的玩家验收均单列 NOT RUN。A4/A5、B4/B5、C3 无楷体实体环境不因本批打包自动变成通过。

模板来源：[官方 4.7.2 发布](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable)；图标/导出依据：[Godot Windows 导出](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html)。实际下载、文件校验与验收结果将在执行后补充。

## 已执行的依赖准备

`powershell.exe -NoProfile -File tools/install_windows_templates.ps1`：PASS。官方 TPZ 实际 1,281,349,702 B，SHA256 `f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011`，SHA512 `ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079`，均匹配官方发布记录。仅提取 `version.txt`、`windows_release_x86_64.exe`（109,268,480 B）、`icudt_godot.dat` 到忽略目录 `tools/godot/export-templates/4.7.2.stable/`；未安装到用户全局模板目录。该发行包没有 accesskit DLL，不凭源码中可选复制逻辑虚构实际依赖。

重现方式（新增依赖下载仍须遵守相应授权）：

```powershell
powershell.exe -NoProfile -File tools/install_windows_templates.ps1 -Download
powershell.exe -NoProfile -File tools/build_windows_clean.ps1 -Commit <40位提交SHA> -Mode release
```

安装器校验完整下载的大小、两个官方摘要，再固定提取文件并生成逐文件 SHA256 来源记录。构建器拒绝缺失、错版、损坏或非 x64 模板，不自动下载，不在显式 release 失败时降为 portable。

## 定向验收记录

候选验证对象 `8c3ba386f38bbde38ee932a39b35728898caf228` 来自独立临时 Git index/commit-tree，未改变当前分支，未纳入文案任务的改动、未跟踪资源或忽略素材。正常提交前检视最终差异，提交后重新从最终 SHA 构建。后补的引擎许可链接另以对应 portable 用例定向验证。

| 验证 | 实际结果 |
|---|---|
| `powershell.exe -NoProfile -File tests/windows_build.ps1` | PASS，86 checks / 5 cases / 0 failures |
| `powershell.exe -NoProfile -File tests/windows_build_clean.ps1` | PASS，40 checks / 3 cases / 0 failures |
| 后补 Godot 许可链接：`tests/windows_build.ps1 -Case portable` | PASS，19 checks / 1 case / 0 failures；仅重跑对应项 |
| 安装器拒绝错误 TPZ，比较原模板来源哈希 | PASS，拒绝且已验证的模板未改 |
| `build_windows_clean.ps1 -Commit <候选SHA> -Mode release -OutDir build/windows-release-candidate` | PASS，实际导出 exit 0；独立 exe + PCK，保留 2 份完整字体 OFL |
| 实际 Windows PE 资源及目录来源 | PASS，16/32/48/64/128/256 六档实际图标；文件/产品版本 `0.10.0.0`；目录 5 份文件逐一复核大小/哈希，另有来源 JSON |
| 同字节 exe/PCK QA 副本：headless | PASS_WITH_WARNINGS，323 checks，exit 0，完整完成标记；20 表、57 贴图/55 Atlas、无系统回退的中文、真实 400/700 字重、template/release/offline、默认 save/meta/Memory 写入和存档往返 |
| 同字节 exe/PCK QA 副本：visual | PASS_WITH_WARNINGS，111 checks，exit 0；真实鼠标开局、宅院唯一时钟、57 存货卡构建与存档往返，3 张 1280×720 窗口截图逐张目视 |
| 原包移出项目目录，分别 `-- --demo=title/post/inventory --shot=<本机绝对路径>` | PASS_WITH_WARNINGS，3 次 exit 0、3 张实际窗口截图目视；没有 QA 覆盖文件，不用开发引擎替代 |
| 原包默认渲染器启动（不传 `--rendering-method`） | PASS，Vulkan 1.4 / Forward+ / NVIDIA RTX 4060 Ti，标题截图及 exit 0；另三图使用 OpenGL Compatibility，区分记录 |

### 实际模板的测试限制

4.7.2 官方 release 不支持 `--path`/`--main-pack`，且会忽略 `--script`。第一次命令行探针没有执行，不能记通过；已改用正式文件哈希相同的独立 QA 副本，仅在副本旁放 `override.cfg` 和 QA 场景，选择测试入口。未修改 exe/PCK 字节、编译选项或正式游戏代码，正式包不带覆盖文件/场景/探针。可复现入口：

```powershell
powershell.exe -NoProfile -File tools/test_windows_release.ps1 -PackageDir build/windows-release -Only headless
powershell.exe -NoProfile -File tools/test_windows_release.ps1 -PackageDir build/windows-release -Only visual
```

每种模式都使用全新隔离用户目录。成功必须有完整完成标记、真实退出码与全部断言；未知错误不放行。现有 ObjectDB、CanvasItem RID、GL Texture、退出仍占用 resources 清理警告保留为 `PASS_WITH_WARNINGS`，不称零错误或已修复。正式原包另用既有演示入口检查渲染，演示模式不写玩家存档；不能把演示截图当成默认存档验证。

首个构建启动曾因从 PowerShell 7 `Start-Process powershell.exe` 继承模块路径而找不到 `Get-FileHash`，发生在导出前，旧包未动；改用正常 `powershell.exe -NoProfile -File ...` 调用后仅重跑该项成功，没有为验证放宽检查或新增哈希依赖。

### 体积实测

| 文件 | 078fa1f 便携包 | 本批独立候选包 |
|---|---:|---:|
| exe | 180,858,888 B | 109,170,176 B |
| PCK | 241,562,964 B | 241,580,016 B |
| exe + PCK | 402.853 MiB | 334.501 MiB |

两项合计减少 68.351 MiB（16.97%）；候选整个文件夹含说明/许可/来源共 350,767,680 B。字体、音频、纹理和 ICU 仍随包携带，不以缺资源换体积。最终包每项实际字节/哈希及源码 SHA 以 `package-provenance.json` 为准。旧文档「50–80 MB」「100 MB 上下」是历史预估，本批不沿用。随包读我还提供 [Godot 引擎及开源组件许可](https://godotengine.org/license) 链接。

证据保留在本机 `build/c2-qa/`，不将个人路径、运行存档或生成的 shader cache 提交仓库。无头与窗口探针使用同一个正式模板二进制；完整一轮真人游玩、独立机器无楷体/SmartScreen/杀软、签名/安装器及正式公开分发仍为 NOT RUN。

## 最终提交包及测试入口修正

源码 `c546819ce37f9c6988d0efd7a89de2f393ab0712` 已正常推送并核对远端，从该提交干净生成 `build/windows-release/`：exe 109,170,176 B、PCK 241,580,032 B；PE 六档图标/版本、目录逐文件来源与引擎许可链接复核 PASS。该提交 [CI](https://github.com/zhouqingyi1104/The-Survivor-s-Ledger/actions/runs/41993933327) 成功：运行器 20 项，fast 5/5（5 项均含既有退出清理警告），不代表 Windows 实体机矩阵或全量 full 已运行。

最终 WinPS5 测试入口第一次执行超时，没有完成标记，因此记 FAIL。已定位到旁置 `override.cfg` 使用 `Set-Content -Encoding UTF8` 在 WinPS5 产生 BOM（`EF BB BF`）；最小夹具证实 Godot 4.7.2 对该配置返回 OK 却忽略首节，造成 QA 场景未启动。改用 `.NET UTF8Encoding(false)` 显式写无 BOM 的 QA 配置/场景。修正只涉及 QA 启动器和此记录，不改正式 exe/PCK 或其已核对的来源。

修复后仅重跑 headless 失败项：**323 checks / exit 0 / PASS_WITH_WARNINGS**（`build/c2-qa/d201f4d898594dfda659ef8d68f45029/results.json`）。随后首次运行最终 visual：**111 checks / exit 0 / PASS_WITH_WARNINGS**（`build/c2-qa/ab37821dbf5549f69cb3570d8f8bd505/results.json`），实际标题、宅院 HUD/时钟和存货截图逐张目视；两模式前后全部原包与副本文件哈希一致。未修改的最终包也以默认 Vulkan/Forward+ 启动、截图、exit 0。只保留已列明退出清理警告，最终试玩包仍来自 `c546819`，后续修正提交只修复测试入口。
