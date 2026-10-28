# Build a portable playtest package from one committed tree, never the worktree.
param(
    [string]$Commit = 'HEAD',
    [string]$OutDir = 'build/windows-clean'
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$engine = Join-Path $root 'tools/godot/Godot_v4.7.2-stable_win64.exe'
$console = Join-Path $root 'tools/godot/Godot_v4.7.2-stable_win64_console.exe'
foreach ($binary in @($engine, $console)) {
    if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) { throw "找不到本地 Godot 引擎：$binary" }
}
$sha = (& git -C $root rev-parse --verify --end-of-options "$Commit^{commit}" 2>&1)
if ($LASTEXITCODE -ne 0 -or $sha -notmatch '^[0-9a-f]{40}$') { throw "无法解析提交：$Commit" }
$tree = & git -C $root ls-tree -r --full-tree $sha
if ($LASTEXITCODE -ne 0) { throw '读取提交树失败。' }
if (@($tree | Where-Object { $_ -match '^160000 ' }).Count -gt 0) { throw '提交包含子模块，干净构建尚不支持。' }
if (@($tree | Where-Object { $_ -match '^120000 ' }).Count -gt 0) { throw '提交包含符号链接，干净构建尚不支持。' }
$paths = & git -C $root ls-tree -r --name-only $sha
if ($LASTEXITCODE -ne 0) { throw '读取提交路径失败。' }
foreach ($attrPath in @($paths | Where-Object { $_ -match '(^|/)\.gitattributes$' })) {
    $attrs = & git -C $root show "${sha}:$attrPath"
    if ($LASTEXITCODE -ne 0) { throw "读取属性文件失败：$attrPath" }
    if (@($attrs | Where-Object { $_ -match 'filter=lfs' -and $_ -notmatch '^\s*#' }).Count -gt 0) { throw '提交使用 Git LFS，干净构建尚不支持。' }
}
$pointers = & git -C $root grep -l -I -E '^version https://git-lfs\.github\.com/spec/v1$' $sha --
if ($LASTEXITCODE -eq 0 -and $pointers) { throw '提交包含 Git LFS 指针，干净构建尚不支持。' }
if ($LASTEXITCODE -gt 1) { throw 'Git LFS 指针检查失败。' }

if ([IO.Path]::IsPathRooted($OutDir)) { $out = [IO.Path]::GetFullPath($OutDir) }
else { $out = [IO.Path]::GetFullPath((Join-Path $root $OutDir)) }
$out = $out.TrimEnd('\')
$parent = [IO.Path]::GetDirectoryName($out)
$leaf = [IO.Path]::GetFileName($out)
if (-not $parent -or -not $leaf -or $out -eq $root -or $root.StartsWith($out + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "输出目录不能是项目根、它的上级或磁盘根：$out"
}
if ($out.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase) -and -not $out.StartsWith((Join-Path $root 'build') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "项目内的输出目录必须位于 build/ 下：$out"
}
if (Test-Path -LiteralPath $out) {
    $existing = Get-Item -LiteralPath $out -Force
    if (-not $existing.PSIsContainer -or ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "输出路径不是普通目录：$out" }
}
New-Item -ItemType Directory -Force -Path $parent | Out-Null
$token = [guid]::NewGuid().ToString('N')
$work = Join-Path ([IO.Path]::GetTempPath()) "ledger-clean-$token"
if ([IO.Path]::GetFullPath($work).StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw '临时目录位于项目内，请将 TEMP 指向项目外。' }
$stage = Join-Path $parent ".$leaf.staging-$token"
$backup = Join-Path $parent "$leaf.previous-$token"
if ((Test-Path -LiteralPath $work) -or (Test-Path -LiteralPath $stage) -or (Test-Path -LiteralPath $backup)) { throw '临时路径已存在。' }
New-Item -ItemType Directory -Path $work,$stage | Out-Null
$oldAppData = $env:APPDATA
$oldLocalAppData = $env:LOCALAPPDATA
$oldMoved = $false
$published = $false
try {
    $source = Join-Path $work 'source'
    $archive = Join-Path $work 'source.zip'
    $env:APPDATA = Join-Path $work 'appdata'
    $env:LOCALAPPDATA = Join-Path $work 'localappdata'
    New-Item -ItemType Directory -Path $source,$env:APPDATA,$env:LOCALAPPDATA | Out-Null
    & git -C $root archive --format=zip "--output=$archive" $sha
    if ($LASTEXITCODE -ne 0) { throw '提取提交失败。' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($archive, $source)
    $sourceTools = Join-Path $source 'tools/godot'
    New-Item -ItemType Directory -Force -Path $sourceTools | Out-Null
    Copy-Item -LiteralPath $engine,$console -Destination $sourceTools
    $sourceConsole = Join-Path $sourceTools ([IO.Path]::GetFileName($console))
    $builder = Join-Path $source 'tools/build_windows.ps1'
    if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) { throw '该提交没有 Windows 打包脚本。' }
    Write-Host "构建提交：$sha（不包含工作区未提交或未跟踪内容）"
    Write-Host '正在隔离环境中导入资源……'
    $importLog = Join-Path $work 'import.log'
    & $sourceConsole --headless --editor --path $source --import --quit *> $importLog
    $importExit = $LASTEXITCODE
    $importErrors = @(Select-String -LiteralPath $importLog -Pattern 'SCRIPT ERROR|^ERROR:' -CaseSensitive:$false)
    if ($importExit -ne 0 -or $importErrors.Count -gt 0) {
        $importErrors | ForEach-Object { Write-Host $_.Line }
        throw "资源导入失败（退出码 $importExit，错误数 $($importErrors.Count)）。"
    }
    & powershell.exe -NoProfile -File $builder -Mode portable
    if ($LASTEXITCODE -ne 0) { throw "便携包构建失败（退出码 $LASTEXITCODE）。" }
    $package = Join-Path $source 'build/windows'
    foreach ($name in @('劫余录.exe', '劫余录.pck', '读我.txt')) {
        $item = Join-Path $package $name
        if (-not (Test-Path -LiteralPath $item -PathType Leaf) -or (Get-Item -LiteralPath $item).Length -eq 0) { throw "包文件缺失或为空：$name" }
        Copy-Item -LiteralPath $item -Destination $stage
    }
    @"
试玩包来源提交：$sha
游戏项目内容仅来自该提交，不包含构建者工作区未提交、未跟踪或忽略的文件。
也不含 .gitignore 排除的素材（如 cs-studio 铺面模型）：城里这些铺面会退回代码拼的厅堂，和开发机上看到的不同。
便携运行时使用构建者本机 Godot 引擎，不属于该提交。
这是便携试玩包，不代表正式发行或玩家验收。
"@ | Set-Content -LiteralPath (Join-Path $stage '构建来源.txt') -Encoding UTF8
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
    Write-Host "试玩包：$out"
    if ($oldMoved) { Write-Host "原输出保留在：$backup" }
} finally {
    $env:APPDATA = $oldAppData
    $env:LOCALAPPDATA = $oldLocalAppData
    foreach ($owned in @($work, $(if (-not $published) { $stage }))) {
        if ($owned -and (Test-Path -LiteralPath $owned -PathType Container)) {
            $item = Get-Item -LiteralPath $owned -Force
            $resolved = (Resolve-Path -LiteralPath $owned).ProviderPath
            if ($resolved -eq [IO.Path]::GetFullPath($owned) -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                Remove-Item -LiteralPath $owned -Recurse -Force
            } else { Write-Warning "临时目录路径发生变化，未清理：$owned" }
        }
    }
}
