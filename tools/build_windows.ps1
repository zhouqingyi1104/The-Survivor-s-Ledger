# 出 Windows 包。
#
# 两种产物：
#   release  —— Godot 导出模板生成的 exe 和 pck（默认预设），需要先装导出模板。
#   portable —— 便携包（导出的 .pck + 仓库里那台编辑器二进制当运行时），不需要模板，
#               能双击就玩，但体积大（≈400 MB）且带着编辑器；用来给人试玩、验资源是否都进包。
#
# 用法：
#   powershell -File tools\build_windows.ps1              # 有模板就出 release，没有就出 portable
#   powershell -File tools\build_windows.ps1 -Mode portable
#   powershell -File tools\build_windows.ps1 -Mode release  # 没模板会直接报错退出
#
# 模板使用 tools/install_windows_templates.ps1 校验安装到项目忽略目录。
# 构建只使用带官方来源与逐文件校验记录的模板，不写用户全局模板目录。

param(
	[string]$OutDir = "build/windows",
	[string]$Preset = "Windows Desktop",
	[ValidateSet("auto", "release", "portable")]
	[string]$Mode = "auto",
	[string]$TemplatesDir = ''
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'windows_templates.ps1')
$godot = Join-Path $root "tools\godot\Godot_v4.7.2-stable_win64_console.exe"
$runtime = Join-Path $root "tools\godot\Godot_v4.7.2-stable_win64.exe"

if (-not (Test-Path $godot)) {
	throw "找不到引擎：$godot（tools/godot/ 不入库，见 README）"
}

# 引擎版本 → 模板目录名（4.7.2.stable）
$versionLine = & $godot --version
if ($LASTEXITCODE -ne 0) { throw "读取引擎版本失败（退出码 $LASTEXITCODE）。" }
$version = ($versionLine -split '\.official')[0]     # 4.7.2.stable
if (-not $version) { throw "读不出引擎版本：$versionLine" }
if (-not $TemplatesDir) { $TemplatesDir = Join-Path $root "tools\godot\export-templates\$version" }
$hasTemplates = Test-Path -LiteralPath $TemplatesDir -PathType Container

if ($Mode -eq "auto") {
	$Mode = if ($hasTemplates) { "release" } else { "portable" }
}
if ($Mode -eq "release") { $verifiedTemplate = Get-VerifiedWindowsTemplates -TemplatesDir $TemplatesDir -Version $version }

if ([IO.Path]::IsPathRooted($OutDir)) { $out = [IO.Path]::GetFullPath($OutDir) }
else { $out = [IO.Path]::GetFullPath((Join-Path $root $OutDir)) }
$out = $out.TrimEnd([IO.Path]::DirectorySeparatorChar)
$parent = [IO.Path]::GetDirectoryName($out)
$leaf = [IO.Path]::GetFileName($out)
$rootPath = [IO.Path]::GetFullPath($root).TrimEnd([IO.Path]::DirectorySeparatorChar)
if (-not $parent -or -not $leaf -or $out -eq $rootPath -or $rootPath.StartsWith($out + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
	throw "输出目录不能是项目根、它的上级或磁盘根：$out"
}
if (Test-Path -LiteralPath $out) {
	$existing = Get-Item -LiteralPath $out -Force
	if (-not $existing.PSIsContainer -or ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
		throw "输出路径不是普通目录：$out"
	}
}
Assert-LedgerPlainPath $parent
New-Item -ItemType Directory -Force -Path $parent | Out-Null
$token = [Guid]::NewGuid().ToString('N')
$stage = Join-Path $parent (".$leaf.staging-$token")
$backup = Join-Path $parent ("$leaf.previous-$token")
$templateWork = Join-Path $parent (".$leaf.templates-$token")
if (Test-Path -LiteralPath $backup) { throw "备份路径已存在：$backup" }
New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null
$exe = Join-Path $stage "劫余录.exe"
$pck = Join-Path $stage "劫余录.pck"
$oldMoved = $false
$published = $false
$oldAppData = $env:APPDATA
$oldLocalAppData = $env:LOCALAPPDATA
$templateWorkCreated = $false

# The console preset embeds the pack. Only accept a release without a separate
# pck when the selected preset explicitly says so; stale pcks can never satisfy it.
function Test-EmbeddedPreset([string]$name) {
	$configPath = Join-Path $root 'export_presets.cfg'
	if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { return $false }
	$section = ''
	$index = ''
	$embed = @{}
	foreach ($line in Get-Content -LiteralPath $configPath -Encoding UTF8) {
		if ($line -match '^\[preset\.(\d+)(\.options)?\]$') {
			$section = $Matches[1] + $Matches[2]
		} elseif (-not $section.EndsWith('.options') -and $line -match '^name="(.*)"$' -and $Matches[1] -ceq $name) {
			$index = $section
		} elseif ($section.EndsWith('.options') -and $line -match '^binary_format/embed_pck=(true|false)$') {
			$embed[$section] = $Matches[1] -eq 'true'
		}
	}
	return ($index -ne '' -and $embed.ContainsKey($index + '.options') -and $embed[$index + '.options'])
}

function Assert-NoCustomReleaseTemplate([string]$name) {
	$configPath = Join-Path $root 'export_presets.cfg'
	$section = ''
	$index = ''
	$custom = @{}
	foreach ($line in Get-Content -LiteralPath $configPath -Encoding UTF8) {
		if ($line -match '^\[preset\.(\d+)(\.options)?\]$') { $section = $Matches[1] + $Matches[2] }
		elseif (-not $section.EndsWith('.options') -and $line -match '^name="(.*)"$' -and $Matches[1] -ceq $name) { $index = $section }
		elseif ($section.EndsWith('.options') -and $line -match '^custom_template/release="(.*)"$') { $custom[$section] = $Matches[1] }
	}
	if ($index -ne '' -and $custom.ContainsKey($index + '.options') -and $custom[$index + '.options'] -ne '') {
		throw 'Release preset cannot override the verified Windows template.'
	}
}

Write-Host "引擎：$version"
Write-Host "模式：$Mode"
Write-Host "输出：$out"

try {
	if ($Mode -eq "release") {
		Assert-NoCustomReleaseTemplate $Preset
		if (Test-Path -LiteralPath $templateWork) { throw "临时模板目录已存在：$templateWork" }
		New-Item -ItemType Directory -Path $templateWork | Out-Null
		$templateWorkCreated = $true
		$env:APPDATA = Join-Path $templateWork 'appdata'
		$env:LOCALAPPDATA = Join-Path $templateWork 'localappdata'
		New-Item -ItemType Directory -Path $env:APPDATA,$env:LOCALAPPDATA | Out-Null
		$isolatedTemplates = Join-Path $env:APPDATA "Godot\export_templates\$version"
		$isolatedTemplate = Copy-VerifiedWindowsTemplates $verifiedTemplate $isolatedTemplates $version
		& $godot --headless --path $root --export-release $Preset $exe
	} else {
		& $godot --headless --path $root --export-pack $Preset $pck
	}
	$exportExit = $LASTEXITCODE
	if ($exportExit -ne 0) { throw "Godot 导出失败（退出码 $exportExit）；原输出未替换。" }
	$hasPck = (Test-Path -LiteralPath $pck -PathType Leaf) -and (Get-Item -LiteralPath $pck).Length -gt 0
	$embedded = $Mode -eq "release" -and (Test-EmbeddedPreset $Preset)
	if (-not $hasPck -and -not $embedded) {
		throw "导出没有生成非空资源包：$pck；原输出未替换。"
	}
	if ($Mode -eq "portable") {
		if (-not (Test-Path -LiteralPath $runtime -PathType Leaf)) { throw "找不到便携运行时：$runtime" }
		Copy-Item -LiteralPath $runtime -Destination $exe
	}
	if (-not (Test-Path -LiteralPath $exe -PathType Leaf) -or (Get-Item -LiteralPath $exe).Length -eq 0) {
		throw "导出没有生成非空程序：$exe；原输出未替换。"
	}
	$modeText = if ($Mode -eq "portable") {
		"这是便携试玩包，使用开发引擎作为运行时，体积较大。"
	} else {
		"这是通过 Godot 导出模板生成的 Windows 试玩包。"
	}
	$packText = if ($embedded) { "资源已嵌入 exe。" } else { "请保持 exe 和同名 pck 在同一文件夹。" }
	# 档案落点跟 Game.res_is_readonly 走：便携包的运行时不是导出模板，res:// 是本文件夹，能写就写在这里
	$memoryText = if ($Mode -eq "portable") {
		"前世档案 Memory.md 写在本文件夹里；本文件夹不可写时改写到上面那个目录。"
	} else {
		"前世档案 Memory.md 也在上面那个目录。"
	}
	$readme = @"
劫余录 The Survivor's Ledger —— Windows 试玩包

双击「劫余录.exe」即可开始。$packText
$modeText

【本包离线】
本包不连接动态世情服务：世情事件只用游戏内置的内容，局内状态和前世档案不会发出，
也不会产生任何服务费用。局内「设置」里会显示「动态世情：本包离线」。

【试玩怎么玩】
1. 标题点「新开一卷」直接开始，不看攻略；卡住了就直接说「我卡住了」，不用硬撑。
2. 死了以后先看生死簿残页上的复盘，再回答：你知道自己是怎么死的吗？
3. 玩到第 10 日左右停一下，回答：现在有想做但做不了的事吗？是什么拦着你？

【怎么把结果发回来】
在生死簿残页、结局页或标题点「导出试玩报告」，游玩中也可从「设置」进入。
在游戏里选填三问后点「导出到本机」，空答也能导出；取消不会创建报告。
成功后界面会显示文件夹位置，先查看内容，再把整个文件夹打包发回；画面问题请另附截图。
注意：残页上点「合上此录」会删掉这一局的存档，请先导出再合上。

存档与设置位置：%APPDATA%\Godot\app_userdata\劫余录\
存档 save.json（另有上一版的 save.json.bak）、跨轮回底稿 meta.json，设置 input.cfg / video.cfg。
$memoryText

【内置字体】
中文字体随包携带，无需安装系统楷体。字体来源和完整 OFL 许可见同目录「字体许可.txt」。

【游戏引擎】
本游戏使用 Godot Engine。引擎及所含开源组件的许可：https://godotengine.org/license
"@
	Set-Content -LiteralPath (Join-Path $stage "读我.txt") -Value $readme -Encoding UTF8
	$fontLicenses = Join-Path $root 'assets/fonts/LICENSES.txt'
	if (-not (Test-Path -LiteralPath $fontLicenses -PathType Leaf) -or (Get-Item -LiteralPath $fontLicenses).Length -eq 0) {
		throw '缺少字体许可；原输出未替换。'
	}
	Copy-Item -LiteralPath $fontLicenses -Destination (Join-Path $stage '字体许可.txt')
	$engineFiles = @(
		Get-LedgerFileRecord $godot ([IO.Path]::GetFileName($godot))
		Get-LedgerFileRecord $runtime ([IO.Path]::GetFileName($runtime))
	)
	$provenance = [ordered]@{
		schema_version = 1
		mode = $Mode
		engine = [ordered]@{ version = $version; files = $engineFiles }
		template = $(if ($Mode -eq 'release') { $isolatedTemplate.Manifest } else { $null })
		files = @(Get-LedgerPackageFiles $stage)
	}
	$provenance | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $stage 'package-provenance.json') -Encoding UTF8

	# Keep the previous directory intact; a new package never mixes old files or modes.
	if (Test-Path -LiteralPath $out) {
		Move-Item -LiteralPath $out -Destination $backup -ErrorAction Stop
		$oldMoved = $true
	}
	try {
		Move-Item -LiteralPath $stage -Destination $out -ErrorAction Stop
		$published = $true
	} catch {
		if ($oldMoved -and -not (Test-Path -LiteralPath $out)) {
			Move-Item -LiteralPath $backup -Destination $out -ErrorAction Stop
			$oldMoved = $false
		}
		throw
	}
	$exe = Join-Path $out "劫余录.exe"
	$pck = Join-Path $out "劫余录.pck"
	Write-Host "做好：$exe（$([math]::Round((Get-Item -LiteralPath $exe).Length / 1MB, 1)) MB）"
	if ($hasPck) { Write-Host "       $pck（$([math]::Round((Get-Item -LiteralPath $pck).Length / 1MB, 1)) MB）" }
	if ($oldMoved) { Write-Host "原输出完整保留在：$backup" }
	Write-Host "下一步：双击 exe 试玩；存档在 %APPDATA%\Godot\app_userdata\劫余录\"
} finally {
	$env:APPDATA = $oldAppData
	$env:LOCALAPPDATA = $oldLocalAppData
	if ($templateWorkCreated -and (Test-Path -LiteralPath $templateWork -PathType Container)) {
		Assert-LedgerPlainPath $templateWork
		$resolvedTemplates = (Resolve-Path -LiteralPath $templateWork).ProviderPath
		if ($resolvedTemplates -eq [IO.Path]::GetFullPath($templateWork) -and [IO.Path]::GetDirectoryName($resolvedTemplates) -eq $parent) {
			Remove-Item -LiteralPath $templateWork -Recurse -Force
		} else { Write-Warning "临时模板目录路径发生变化，未清理：$templateWork" }
	}
	# This GUID-named directory was created by this invocation, never supplied by a user.
	if (-not $published -and (Test-Path -LiteralPath $stage -PathType Container)) {
		$resolvedStage = (Resolve-Path -LiteralPath $stage).ProviderPath
		$stageItem = Get-Item -LiteralPath $stage -Force
		if ($resolvedStage -eq [IO.Path]::GetFullPath($stage) -and -not ($stageItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
			Remove-Item -LiteralPath $stage -Recurse -Force
		} else {
			Write-Warning "临时目录路径发生变化，未清理：$stage"
		}
	}
}
