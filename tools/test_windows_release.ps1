param(
    [Parameter(Mandatory = $true)][string]$PackageDir,
    [ValidateSet('headless', 'visual')][string]$Only = 'headless'
)
# Windows PowerShell 5 compatible. No download, export, or production package write.
# Exact exe/PCK copies use an adjacent QA-only override; CLI path/script overrides stay disabled.
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'This probe requires Windows.' }
. (Join-Path $PSScriptRoot 'windows_templates.ps1')
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Assert-LedgerPlainPath $PackageDir
$source = (Resolve-Path -LiteralPath $PackageDir).ProviderPath
if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw 'PackageDir must be a directory.' }
if (Test-Path -LiteralPath (Join-Path $source 'override.cfg')) { throw 'Source contains override.cfg; refuse a QA or overridden package.' }
$manifestPath = Join-Path $source 'package-provenance.json'
Assert-LedgerPlainPath $manifestPath
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.schema_version -ne 1 -or $manifest.mode -cne 'release' -or $manifest.engine.version -cne '4.7.2.stable' -or $manifest.source_commit -notmatch '^[a-f0-9]{40}$') { throw 'Expected clean Godot 4.7.2 release provenance.' }
$records = @($manifest.files)
if ($records.Count -eq 0) { throw 'Empty package provenance file inventory.' }
$seen = @{}
foreach ($record in $records) {
    $relative = [string]$record.path
    $parts = $relative.Split('/')
    if (-not $relative -or $relative.Contains('\') -or $relative.Contains(':') -or [IO.Path]::IsPathRooted($relative) -or @($parts | Where-Object { $_ -in @('', '.', '..', 'Memory.md', 'override.cfg', 'package-provenance.json') -or $_ -like '.env*' }).Count) { throw 'Unsafe or non-package path in provenance.' }
    if ($seen.ContainsKey($relative) -or [string]$record.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or [long]$record.size_bytes -le 0) { throw 'Invalid or duplicate package file record.' }
    $seen[$relative] = $true
}
$exeRecords = @($records | Where-Object { [IO.Path]::GetExtension($_.path) -eq '.exe' })
$pckRecords = @($records | Where-Object { [IO.Path]::GetExtension($_.path) -eq '.pck' })
if ($exeRecords.Count -ne 1 -or $pckRecords.Count -ne 1 -or [IO.Path]::GetFileNameWithoutExtension($exeRecords[0].path) -cne [IO.Path]::GetFileNameWithoutExtension($pckRecords[0].path)) { throw 'Expected one exe and its matching PCK.' }
$records += [pscustomobject]@{ path = 'package-provenance.json'; size_bytes = (Get-Item -LiteralPath $manifestPath).Length; sha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash }
function Assert-Record([string]$Base, $Record) {
    $path = [IO.Path]::GetFullPath((Join-Path $Base $Record.path))
    if (-not $path.StartsWith($Base.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Package path escapes its directory.' }
    Assert-LedgerPlainPath $path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -ne [long]$Record.size_bytes -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine [string]$Record.sha256) { throw ('Package size or SHA256 mismatch: ' + $Record.path) }
}
foreach ($record in $records) { Assert-Record $source $record }
$qaBase = Join-Path $repo 'build/c2-qa'
Assert-LedgerPlainPath $qaBase
$run = [IO.Path]::GetFullPath((Join-Path $qaBase ([guid]::NewGuid().ToString('N'))))
if (-not $run.StartsWith([IO.Path]::GetFullPath($qaBase).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'QA output escapes build/c2-qa.' }
$copy = Join-Path $run 'package'
$userRoot = Join-Path $run 'user'
New-Item -ItemType Directory -Path $copy | Out-Null
foreach ($record in $records) {
    $target = Join-Path $copy $record.path
    New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($target)) | Out-Null
    Copy-Item -LiteralPath (Join-Path $source $record.path) -Destination $target
    Assert-Record $copy $record
}
$probePath = (Join-Path $repo 'tests/windows_release_probe.gd').Replace('\', '/')
Assert-LedgerPlainPath $probePath
if (-not (Test-Path -LiteralPath $probePath -PathType Leaf)) { throw 'External release probe script is missing.' }
$entryPath = (Join-Path $copy 'release-probe-entry.tscn').Replace('\', '/')
@"
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="$probePath" id="1_probe"]
[node name="ExternalWindowsReleaseProbe" type="Node"]
script = ExtResource("1_probe")
"@ | Set-Content -LiteralPath $entryPath -Encoding UTF8
@"
[application]
run/main_scene="$entryPath"
"@ | Set-Content -LiteralPath (Join-Path $copy 'override.cfg') -Encoding UTF8
$stdoutPath = Join-Path $run 'stdout.log'
$stderrPath = Join-Path $run 'stderr.log'
$saved = @{}
foreach ($name in @('APPDATA', 'LOCALAPPDATA', 'HOME', 'USERPROFILE')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$exitCode = $null
$failure = ''
try {
    $env:APPDATA = Join-Path $userRoot 'appdata'
    $env:LOCALAPPDATA = Join-Path $userRoot 'localappdata'
    $env:HOME = Join-Path $userRoot 'home'
    $env:USERPROFILE = $env:HOME
    New-Item -ItemType Directory -Force -Path $env:APPDATA, $env:LOCALAPPDATA, $env:HOME | Out-Null
    $arguments = @()
    if ($Only -eq 'headless') { $arguments += '--headless' }
    else { $arguments += @('--rendering-method', 'gl_compatibility', '--resolution', '1280x720', '--windowed') }
    $arguments += @('--', "--only=$Only", "--user-root=$userRoot")
    if ($Only -eq 'visual') { $arguments += '--output=' + (Join-Path $run 'shots') }
    # Start-Process joins ArgumentList on PS5; quote complete tokens for paths with spaces.
    $quotedArguments = @($arguments | ForEach-Object { '"' + ($_ -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' }) -join ' '
    $process = Start-Process -FilePath (Join-Path $copy $exeRecords[0].path) -WorkingDirectory $copy -WindowStyle Hidden -ArgumentList $quotedArguments -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
    $handle = $process.Handle
    if (-not $process.WaitForExit(45000)) {
        & taskkill.exe /PID $process.Id /T /F | Out-Null
        throw 'Parent timeout: complete probe result was not received.'
    }
    $exitCode = $process.ExitCode
} catch { $failure = $_.Exception.Message }
finally { foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') } }
$stdout = if ((Test-Path -LiteralPath $stdoutPath) -and (Get-Item -LiteralPath $stdoutPath).Length) { Get-Content -LiteralPath $stdoutPath -Raw -Encoding UTF8 } else { '' }
$stderr = if ((Test-Path -LiteralPath $stderrPath) -and (Get-Item -LiteralPath $stderrPath).Length) { Get-Content -LiteralPath $stderrPath -Raw -Encoding UTF8 } else { '' }
$completion = [regex]::Matches($stdout, "(?m)^\[windows_release_probe\] COMPLETE PASS only=$Only checks=[1-9][0-9]*\r?$")
if (-not $failure -and ($exitCode -ne 0 -or $completion.Count -ne 1)) { $failure = 'Nonzero exit or missing/duplicate complete success marker.' }
$warnings = @()
foreach ($line in (($stdout + "`n" + $stderr) -split '\r?\n')) {
    $trimmed = $line.Trim()
    # Only these exact engine shutdown ERRORs may accompany a completed exit 0.
    $cleanup = $trimmed -match '^ERROR: (\d+ resources still in use at exit \(run with --verbose for details\)|Texture with GL ID of \d+: leaked \d+ bytes)\.$'
    if ($cleanup -and -not $failure) { $warnings += $trimmed }
    elseif ($trimmed -match '(?i)SCRIPT ERROR|ParseError|Parse Error|\bERROR:|\bFAIL:') { if (-not $failure) { $failure = $trimmed } }
    elseif ($trimmed -match '^WARNING:') { $warnings += $trimmed }
}
try {
    foreach ($record in $records) { Assert-Record $source $record; Assert-Record $copy $record }
    if (Test-Path -LiteralPath (Join-Path $source 'override.cfg')) { throw 'Original package acquired an override during the probe.' }
} catch { if (-not $failure) { $failure = $_.Exception.Message } }
$warnings = @($warnings | Select-Object -Unique)
$status = if ($failure) { 'FAIL' } elseif ($warnings.Count) { 'PASS_WITH_WARNINGS' } else { 'PASS' }
[ordered]@{
    schema_version = 1; status = $status; mode = $Only; source_commit = $manifest.source_commit
    package = $source; qa_copy = $copy; user_root = $userRoot; exit_code = $exitCode
    completion = @($completion | ForEach-Object { $_.Value.Trim() }); failure = $failure; warnings = $warnings
    scope = 'Unchanged release exe/PCK/resources; QA-copy adjacent override plus external scene/script only. Not untouched-package player acceptance.'
    original_and_copy_files = $records; stdout = $stdoutPath; stderr = $stderrPath
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $run 'results.json') -Encoding UTF8
Write-Output ("$status $Only; evidence: " + (Join-Path $run 'results.json'))
if ($failure) { throw $failure }
