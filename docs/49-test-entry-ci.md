# 统一测试入口与 CI（2026-11-05）

状态：本地入口、负例和定向游戏检查 PASS；远端 CI 配置已接入，推送后的实际结果以该批提交的 Actions run 及本机 CI 记录为准。本文先写方案再补结果。承接优化路线图 C5；这是工程基础批次，不算新增玩法或玩家验收。

## 要交付的结果

开发者可用 `tools/run_tests.ps1 -Tier fast|core|ui|full` 选择范围，失败后用 `-Case <id>` 只重跑对应项。提交到远端后，GitHub Actions 自动执行脚本编译与一小组无界面规则检查。每项保留退出码、超时、完整日志和明确的完成标记；局部函数报错后退出 0 不能变成 PASS。

## 范围与验收合同

1. 用显式清单登记已有离线自动测试：fast 为编译与小型纯规则；core 含 fast 及其余已登记无界面规则；ui 只跑真实窗口；full 为已登记离线自动测试全量，只供发布候选手动执行。诊断脚本、人工截图、需本地服务/私有模型的检查写出排除原因，不以文件名猜测成功。
2. PowerShell 只做入口，运行器使用项目已有 Python 3 标准库与现有 Godot 4.7.2，不安装包、不升级引擎、不下载运行时、不改 `.env`。支持列出选择与单项重跑；未知用例、空选择、缺引擎、错误版本明确失败。
3. 启动前把需要的项目文件复制到本轮 `build/test-runs/<唯一ID>/project`，不在原工作区运行游戏测试。既隔离各进程的 APPDATA/LOCALAPPDATA/XDG/TEMP，也隔离会写 `res://` 的旧测试，不能靠测试启动后设置 `no_save` 保护玩家档案。子进程只继承必要系统变量白名单，排除凭据、用例缩减与外部截图路径变量，用户名用非空合成值。不复制 `.git`、真实 `.env`、玩家档案、构建缓存或忽略的私有模型；保留本轮快照、日志及证据供复查，不自动删除其他内容。
4. 每项真实父进程超时，失败立即停在第一项；未执行项记录 NOT RUN，不跑后续 tier 抹掉失败。非零退出、超时、脚本/解析/运行错误、缺完成标记均失败。已知退出阶段的资源清理信息保持原文、单列为带警告结果，不伪装成日志无错误。
5. 用必要的负例检查运行器本身：退出 0 但有 SCRIPT ERROR、缺完成标记、超时及子进程残留、非零退出、路径/快照隔离、选择错误，均不能假绿。这些是假引擎夹具，不算游戏功能通过。
6. CI 仅公开仓库的标准 Ubuntu runner、只读权限，无 secrets、ARK、部署、付费 runner、缓存/附件上传或软件包安装。拉取当前提交并验证固定版本官方 Linux Godot 压缩包 SHA512，用相同入口运行 fast；本地不下载新引擎。仓库不是公开状态则跳过并明确记录，不触发费用。
7. 先验证运行器与本批定向用例，再提交推送并核对 SHA，读取该提交真实 CI 结果。全量游戏测试只留发布候选，本批不运行 full，也不为测试入口重打无玩法变化的试玩包。保留文案和美术任务的未提交内容。

## 未验收边界

本地通过、夹具通过、远端 CI、真实窗口、玩家整局和发行验收分别记录。未运行的层级或平台写 NOT RUN；C3 无楷体环境、A4/A5 真人试玩、B4 平衡目标、B5 白天体验均保持原状态。本批不修改游戏规则、数值或存档安全机制。

## 实现与使用

入口是 `tools/run_tests.ps1`，委托仅使用标准库的 `tools/run_tests.py`。PowerShell 5.1/7 均可用，顺序选择现有 `python` / `python3` 的合格单一应用，跳过 WindowsApps 商店别名；要求 Python ≥3.10。`-GodotPath` 指定已有引擎，程序不会下载或升级引擎。

| 选择 | 内容 |
|---|---|
| `-Tier fast` | 5 项：check_scripts、brief、pacing、ending_report、playtest_report |
| `-Tier core` | fast + 56 项 core，共 61 项无界面检查 |
| `-Tier ui` | 36 项真实窗口检查 |
| `-Tier full` | 全部 118 项已登记 Godot 离线检查，含 21 项慢/专项自动检查；仅发布候选 |
| `-Case brief` | 只执行该 ID，不会顺带跑 fast；可多项，未知/重复/空 ID 明确失败 |
| `-List` | 只展示选中清单，不启动引擎或导入资源 |

131 个 Godot 入口均已有分类；118 项可执行，另有 22 项诊断、人工截图、本地服务及 PS/Python/Node 专项排除说明。运行器自身 unittest 在 CI 单独执行，不冒充游戏用例。`full` 不代表这些被排除专项通过，也不代表跨平台或真人整局通过。

每轮保存每文件 SHA256 与快照摘要、来源 HEAD/dirty 状态、实际命令、退出码、超时、各项状态及首失败的单项重跑命令；原日志按字节保留。它是当前工作区可测试文件的快照，包含合格的未提交代码，不是干净提交构建，也不承诺对并行写入的工作区作原子拍照。所有平台不适用的选择保留 SKIP 并非零退出；部分平台限制单列 SKIP。

CI 文件 `.github/workflows/tests.yml` 不引入第三方 action，按事件 SHA 拉取并核对提交，使用只读权限。固定 Godot 4.7.2 官方 Linux zip 的 SHA512 已在线与原有同版本校验清单比对；使用预装 Python/PowerShell，不安装软件包。每项 JSON 和原始日志写入 job log，不上传缓存或附件。公开仓库标准 runner 的费用边界见 [GitHub 官方说明](https://docs.github.com/en/billing/concepts/product-billing/github-actions)；仓库状态已读回为 public，工作流仍保留 private=false 的运行条件。手动 dispatch 可只选择一个 fast 用例重跑。

## 本地实际验证

| 实际执行 | 结果 |
|---|---|
| `python -m unittest discover -s tests -p test_run_tests.py -v -f` 起步，失败/新增项按方法名定向续跑 | 20 个独立运行器测试均 PASS；均为假引擎/临时 Git/真实 Python 子进程，不是 Godot 功能验收 |
| Windows PowerShell 5.1：`-File tools/run_tests.ps1 -Tier fast -List` | 精确列 5 项，退出 0 |
| PowerShell 7：`./tools/run_tests.ps1 -Tier fast` | 5/5，退出 0；2 PASS、3 PASS_WITH_WARNINGS；93 脚本编译、brief 63、pacing 33、ending_report 31、playtest_report 52 检查零失败 |
| `./tools/run_tests.ps1 -Tier ui -Case title_input` | 1/1 PASS，真实 OpenGL 窗口 1280×720 的 GUI 鼠标命中并打开自选身份页，退出 0 |
| 清单与 CI 静态/独立审查 | 118 项路径/正则及 131 入口分类、隔离边界、同版本 SHA512、YAML 与 job-report Python 语法 PASS；不等于远端执行 |

本机 fast 证据：`build/test-runs/cee75a0d902d46769f65e18b1c1dd676/results.json`；窗口证据：`2233763ccac04cf5831d51b81f8ff3f0/results.json`（同一父目录）。资源导入和各用例均在各自快照执行，源码与玩家目录未用于游戏测试写入。

开发时 `-List` 首次把 tools 专项排除项错误按 tests 路径校验，已分别校验；首次 PowerShell 探测把多个 Python 路径拼成一条，也已修复并定向复核。运行器单测的 Windows 短路径夹具比较错误已用规范路径修正，仅重跑失败项。独立审查发现的 Linux 空用户名、继承凭据及 `JOURNEY_ONLY`/外部截图变量风险，已用合成身份与环境白名单解决，并补负例；没有改旧游戏断言来绕过。

已知退出清理信息原样保留。core 其余用例、ui 其余用例、full 全量、Node/人工图像矩阵专项、真人整局及发行均 NOT RUN；本批不重新打包相同游戏内容。远端执行结果只在推送后按实际提交回读，不提前记 PASS。
