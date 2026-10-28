$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('ledger-clean-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path (Join-Path $fixture 'tools/godot') | Out-Null
$checks = 0
function Check($ok, $message) { $script:checks++; if (-not $ok) { throw "FAIL: $message" } }
try {
    Copy-Item -LiteralPath (Join-Path $repo 'tools/build_windows_clean.ps1') -Destination (Join-Path $fixture 'tools/build_windows_clean.ps1')
    $mock = @'
using System;
class MockGodot {
 static int Main(string[] args) {
  if (Environment.GetEnvironmentVariable("LEDGER_CLEAN_IMPORT_ERROR") == "1") Console.WriteLine("SCRIPT ERROR: injected failure");
  return 0;
 }
}
'@
    [IO.File]::WriteAllText((Join-Path $fixture 'mock.cs'), $mock)
    $console = Join-Path $fixture 'tools/godot/Godot_v4.7.2-stable_win64_console.exe'
    $csc = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    & $csc /nologo /target:exe "/out:$console" (Join-Path $fixture 'mock.cs')
    if ($LASTEXITCODE -ne 0) { throw 'mock engine compile failed' }
    [IO.File]::WriteAllText((Join-Path $fixture 'tools/godot/Godot_v4.7.2-stable_win64.exe'), 'RUNTIME')
    $builder = @'
param([string]$Mode)
$root = Split-Path -Parent $PSScriptRoot
if (Test-Path -LiteralPath (Join-Path $root 'private-untracked.gd')) { exit 9 }
$out = Join-Path $root 'build/windows'
New-Item -ItemType Directory -Force -Path $out | Out-Null
foreach ($name in @('劫余录.exe', '劫余录.pck', '读我.txt')) { [IO.File]::WriteAllText((Join-Path $out $name), 'OK') }
'@
    [IO.File]::WriteAllText((Join-Path $fixture 'tools/build_windows.ps1'), $builder, [Text.UTF8Encoding]::new($true))
    & git -C $fixture init -q
    & git -C $fixture add tools/build_windows.ps1
    & git -C $fixture -c user.name=Test -c user.email=test@example.invalid commit -qm fixture
    if ($LASTEXITCODE -ne 0) { throw 'fixture commit failed' }
    $sha = & git -C $fixture rev-parse HEAD
    [IO.File]::WriteAllText((Join-Path $fixture 'private-untracked.gd'), 'PRIVATE')
    $out = Join-Path $fixture 'build/clean'
    New-Item -ItemType Directory -Force -Path $out | Out-Null
    [IO.File]::WriteAllText((Join-Path $out 'old.txt'), 'KEEP')
    $script = Join-Path $fixture 'tools/build_windows_clean.ps1'
    function Run($revision) {
        $stdout = Join-Path $fixture 'stdout.txt'
        $stderr = Join-Path $fixture 'stderr.txt'
        $p = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-File', ('"' + $script + '"'), '-Commit', $revision, '-OutDir', ('"' + $out + '"')) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        return $p.ExitCode
    }
    $env:LEDGER_CLEAN_IMPORT_ERROR = '1'
    Check ((Run $sha) -ne 0) 'Godot script error with exit 0 was accepted'
    Check ([IO.File]::ReadAllText((Join-Path $out 'old.txt')) -eq 'KEEP') 'import failure changed old output'
    $env:LEDGER_CLEAN_IMPORT_ERROR = '0'
    Check ((Run 'missing-revision') -ne 0) 'invalid commit accepted'
    Check ([IO.File]::ReadAllText((Join-Path $out 'old.txt')) -eq 'KEEP') 'invalid commit changed old output'
    Check ((Run $sha) -eq 0) 'committed-only build failed or included private file'
    Check (Test-Path -LiteralPath (Join-Path $out '劫余录.pck')) 'package missing'
    $source = Get-Content -LiteralPath (Join-Path $out '构建来源.txt') -Raw -Encoding UTF8
    Check ($source.Contains($sha)) 'package lacks full commit SHA'
    Check ($source.Contains('本机 Godot')) 'package does not identify external runtime'
    $backup = @(Get-ChildItem -LiteralPath (Split-Path $out) -Directory -Filter 'clean.previous-*')
    Check ($backup.Count -eq 1 -and [IO.File]::ReadAllText((Join-Path $backup[0].FullName 'old.txt')) -eq 'KEEP') 'old output not preserved'
    New-Item -ItemType Directory -Path (Join-Path $fixture 'nested') | Out-Null
    [IO.File]::WriteAllText((Join-Path $fixture 'nested/.gitattributes'), "*.bin filter=lfs`n")
    & git -C $fixture add nested/.gitattributes
    & git -C $fixture -c user.name=Test -c user.email=test@example.invalid commit -qm 'nested lfs'
    if ($LASTEXITCODE -ne 0) { throw 'nested LFS fixture commit failed' }
    Check ((Run 'HEAD') -ne 0) 'nested Git LFS attributes accepted'
    Check ((Get-Content -LiteralPath (Join-Path $out '构建来源.txt') -Raw -Encoding UTF8).Contains($sha)) 'LFS rejection changed package'
    [IO.File]::WriteAllText((Join-Path $fixture 'nested/.gitattributes'), "# no filter`n")
    [IO.File]::WriteAllText((Join-Path $fixture 'nested/pointer.bin'), "version https://git-lfs.github.com/spec/v1`noid sha256:fake`nsize 1`n")
    & git -C $fixture add nested/.gitattributes nested/pointer.bin
    & git -C $fixture -c user.name=Test -c user.email=test@example.invalid commit -qm 'lfs pointer'
    if ($LASTEXITCODE -ne 0) { throw 'LFS pointer fixture commit failed' }
    Check ((Run 'HEAD') -ne 0) 'LFS pointer accepted'
    Check ((Get-Content -LiteralPath (Join-Path $out '构建来源.txt') -Raw -Encoding UTF8).Contains($sha)) 'LFS pointer rejection changed package'
    Write-Output "[windows_build_clean] $checks checks, 0 failures"
} finally {
    $env:LEDGER_CLEAN_IMPORT_ERROR = $null
    if (Test-Path -LiteralPath $fixture -PathType Container) {
        $resolved = (Resolve-Path -LiteralPath $fixture).ProviderPath
        $item = Get-Item -LiteralPath $fixture -Force
        if ($resolved -eq [IO.Path]::GetFullPath($fixture) -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { Remove-Item -LiteralPath $fixture -Recurse -Force }
    }
}
