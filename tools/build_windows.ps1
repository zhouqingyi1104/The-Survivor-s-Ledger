# 出 Windows 包。
#
# 两种产物：
#   release  —— 真正的独立程序（Godot 导出模板编出来的 exe，约 50–80 MB），需要先装导出模板。
#   portable —— 便携包（导出的 .pck + 仓库里那台编辑器二进制当运行时），不需要模板，
#               能双击就玩，但体积大（≈400 MB）且带着编辑器；用来给人试玩、验资源是否都进包。
#
# 用法：
#   powershell -File tools\build_windows.ps1              # 有模板就出 release，没有就出 portable
#   powershell -File tools\build_windows.ps1 -Mode portable
#   powershell -File tools\build_windows.ps1 -Mode release  # 没模板会直接报错退出
#
# 导出模板怎么装：
#   下载 https://github.com/godotengine/godot/releases/download/<版本>-stable/Godot_v<版本>-stable_export_templates.tpz
#   解压后把 templates\ 里的文件放进 %APPDATA%\Godot\export_templates\<版本>.stable\
#   （目录名要和引擎版本完全一致，脚本会自己算出来并打印）

param(
	[string]$OutDir = "build/windows",
	[string]$Preset = "Windows Desktop",
	[ValidateSet("auto", "release", "portable")]
	[string]$Mode = "auto"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $root "tools\godot\Godot_v4.7.2-stable_win64_console.exe"
$runtime = Join-Path $root "tools\godot\Godot_v4.7.2-stable_win64.exe"

if (-not (Test-Path $godot)) {
	throw "找不到引擎：$godot（tools/godot/ 不入库，见 README）"
}

# 引擎版本 → 模板目录名（4.7.2.stable）
$versionLine = & $godot --version
$version = ($versionLine -split '\.official')[0]     # 4.7.2.stable
if (-not $version) { throw "读不出引擎版本：$versionLine" }
$templates = Join-Path $env:APPDATA "Godot\export_templates\$version"
$hasTemplates = Test-Path (Join-Path $templates "windows_release_x86_64.exe")

if ($Mode -eq "auto") {
	$Mode = if ($hasTemplates) { "release" } else { "portable" }
}
if ($Mode -eq "release" -and -not $hasTemplates) {
	throw "要出 release 但没装导出模板。模板目录应为：$templates"
}

$out = Join-Path $root $OutDir
New-Item -ItemType Directory -Force -Path $out | Out-Null
$exe = Join-Path $out "劫余录.exe"
$pck = Join-Path $out "劫余录.pck"

Write-Host "引擎：$version"
Write-Host "模式：$Mode"
Write-Host "输出：$out"

if ($Mode -eq "release") {
	& $godot --headless --path $root --export-release $Preset $exe
	if (-not (Test-Path $exe)) { throw "导出没有产物：$exe" }
} else {
	# 便携包：.pck 必须和 exe 同名，双击 exe 才会自动挂上
	& $godot --headless --path $root --export-pack $Preset $pck
	if (-not (Test-Path $pck)) { throw "导出没有产物：$pck" }
	Copy-Item $runtime $exe -Force
	$readme = @"
劫余录 The Survivor's Ledger —— 便携试玩包

双击「劫余录.exe」即可开始。不需要安装，整个文件夹可以拷走。

这是「便携包」：运行时用的是开发用的引擎二进制（所以体积大、且带着编辑器），
用来试玩和验证打包是否完整；正式的独立程序要等导出模板装好后用
tools\build_windows.ps1 -Mode release 重新出。

存档与设置位置：
  %APPDATA%\Godot\app_userdata\劫余录\
  存档 save.json（另有上一版的 save.json.bak）、跨轮回底稿 meta.json、
  设置 input.cfg / video.cfg、前世档案 Memory.md（打包后落在这里）

遇到问题想反馈：把上面那个目录里的 save.json 和截图一起发过来。
"@
	Set-Content -Path (Join-Path $out "读我.txt") -Value $readme -Encoding UTF8
}

$exeSize = [math]::Round((Get-Item $exe).Length / 1MB, 1)
Write-Host "做好：$exe（$exeSize MB）"
if (Test-Path $pck) {
	$pckSize = [math]::Round((Get-Item $pck).Length / 1MB, 1)
	Write-Host "       $pck（$pckSize MB）"
}
Write-Host "下一步：双击 exe 试一局；存档在 %APPDATA%\Godot\app_userdata\劫余录\"
