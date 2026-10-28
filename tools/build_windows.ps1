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
if ($LASTEXITCODE -ne 0) { throw "读取引擎版本失败（退出码 $LASTEXITCODE）。" }
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

$out = [IO.Path]::GetFullPath((Join-Path $root $OutDir)).TrimEnd([IO.Path]::DirectorySeparatorChar)
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
New-Item -ItemType Directory -Force -Path $parent | Out-Null
$token = [Guid]::NewGuid().ToString('N')
$stage = Join-Path $parent (".$leaf.staging-$token")
$backup = Join-Path $parent ("$leaf.previous-$token")
if (Test-Path -LiteralPath $backup) { throw "备份路径已存在：$backup" }
New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null
$exe = Join-Path $stage "劫余录.exe"
$pck = Join-Path $stage "劫余录.pck"
$oldMoved = $false
$published = $false

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

Write-Host "引擎：$version"
Write-Host "模式：$Mode"
Write-Host "输出：$out"

try {
	if ($Mode -eq "release") {
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
	$readme = @"
劫余录 The Survivor's Ledger —— Windows 试玩包

双击「劫余录.exe」即可开始。$packText
$modeText

存档与设置位置：%APPDATA%\Godot\app_userdata\劫余录\
存档 save.json（另有上一版的 save.json.bak）、跨轮回底稿 meta.json，
设置 input.cfg / video.cfg、前世档案 Memory.md。

遇到问题时，可在标题页、生死簿残页或结局页点击「导出试玩报告」，
并按界面显示的位置找到报告；画面问题请另附截图。
"@
	Set-Content -LiteralPath (Join-Path $stage "读我.txt") -Value $readme -Encoding UTF8

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
