param(
    [ValidateSet('all', 'archive', 'release', 'rejected-source')]
    [string]$Case = 'all'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
$fixture = Join-Path $tempRoot ('ledger-clean-test-' + [guid]::NewGuid().ToString('N'))
if (-not $fixture.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid fixture location' }
New-Item -ItemType Directory -Force -Path (Join-Path $fixture 'tools/godot') | Out-Null
$checks = 0
$completed = 0
$oldImportError = $env:LEDGER_CLEAN_IMPORT_ERROR
$oldBuilderError = $env:LEDGER_CLEAN_BUILDER_ERROR
$oldAppData = $env:APPDATA
$oldLocalAppData = $env:LOCALAPPDATA
function Check($ok, $message) { $script:checks++; if (-not $ok) { throw "FAIL [$script:activeCase]: $message" } }
function Run($revision, $mode = 'portable', $templatesDir = $script:templates) {
    $stdout = Join-Path $fixture 'stdout.txt'
    $stderr = Join-Path $fixture 'stderr.txt'
    $args = @('-NoProfile', '-File', ('"' + (Join-Path $fixture 'tools/build_windows_clean.ps1') + '"'), '-Commit', $revision, '-OutDir', ('"' + $script:out + '"'), '-Mode', $mode, '-TemplatesDir', ('"' + $templatesDir + '"'))
    $p = Start-Process -FilePath powershell.exe -ArgumentList $args -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $cachedHandle = $p.Handle
    $p.WaitForExit()
    $script:lastOutput = ([IO.File]::ReadAllText($stdout) + [IO.File]::ReadAllText($stderr))
    return $p.ExitCode
}
function Check-Old {
    Check ([IO.File]::ReadAllText((Join-Path $script:out 'old.txt')) -eq 'KEEP') 'failure changed old output'
}
function Commit-Fixture([string]$message) {
    & git -C $fixture -c user.name=Test -c user.email=test@example.invalid commit -qm $message
    if ($LASTEXITCODE -ne 0) { throw "fixture commit failed: $message" }
}
function Write-Templates {
    New-Item -ItemType Directory -Force -Path $script:templates | Out-Null
    [IO.File]::WriteAllText((Join-Path $script:templates 'version.txt'), '4.7.2.stable')
    $pe = New-Object byte[] 256
    $pe[0] = 0x4d; $pe[1] = 0x5a
    [BitConverter]::GetBytes([int]128).CopyTo($pe, 60)
    $pe[128] = 0x50; $pe[129] = 0x45
    [BitConverter]::GetBytes([uint16]0x8664).CopyTo($pe, 132)
    [IO.File]::WriteAllBytes((Join-Path $script:templates 'windows_release_x86_64.exe'), $pe)
    $pe[200] = 2
    [IO.File]::WriteAllBytes((Join-Path $script:templates 'accesskit.x86_64.dll'), $pe)
    [IO.File]::WriteAllText((Join-Path $script:templates 'icudt_godot.dat'), 'MOCK_ICU')
    $files = @('version.txt', 'windows_release_x86_64.exe', 'accesskit.x86_64.dll', 'icudt_godot.dat') | ForEach-Object {
        $path = Join-Path $script:templates $_
        @{path=$_; sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant(); size_bytes=(Get-Item -LiteralPath $path).Length}
    }
    @{
        schema_version=1; version='4.7.2.stable'
        source=@{
            url='https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz'
            sha512='ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079'
            sha256='f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011'
        }
        files=@($files)
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $script:templates 'provenance.json') -Encoding UTF8
}
try {
    foreach ($name in @('build_windows_clean.ps1', 'windows_templates.ps1')) {
        Copy-Item -LiteralPath (Join-Path $repo "tools/$name") -Destination (Join-Path $fixture "tools/$name")
    }
    $mock = @'
using System;
class MockGodot {
 static int Main(string[] args) {
  if (Array.IndexOf(args, "--version") >= 0) { Console.WriteLine("4.7.2.stable.official.mock"); return 0; }
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
param([string]$Mode, [string]$TemplatesDir)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ($env:LEDGER_CLEAN_BUILDER_ERROR -eq '1') { exit 19 }
if (Test-Path -LiteralPath (Join-Path $root 'private-untracked.gd')) { exit 9 }
if ((Get-Content -LiteralPath (Join-Path $root 'tracked-data.txt') -Raw) -ne 'COMMITTED') { exit 10 }
if (-not $env:APPDATA.StartsWith([IO.Path]::GetDirectoryName($root), [StringComparison]::OrdinalIgnoreCase)) { exit 11 }
$out = Join-Path $root 'build/windows'
New-Item -ItemType Directory -Force -Path $out | Out-Null
foreach ($name in @('劫余录.exe', '劫余录.pck', '读我.txt', '字体许可.txt')) { [IO.File]::WriteAllText((Join-Path $out $name), $Mode) }
$template = $null
if ($Mode -eq 'release') {
    if (-not $TemplatesDir -or -not $TemplatesDir.StartsWith([IO.Path]::GetDirectoryName($root), [StringComparison]::OrdinalIgnoreCase)) { exit 12 }
    . (Join-Path $PSScriptRoot 'windows_templates.ps1')
    $verified = Get-VerifiedWindowsTemplates -TemplatesDir $TemplatesDir -Version '4.7.2.stable'
    if ([IO.File]::ReadAllText((Join-Path $TemplatesDir 'icudt_godot.dat')) -ne 'MOCK_ICU') { exit 13 }
    $template = Get-Content -LiteralPath (Join-Path $TemplatesDir 'provenance.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Copy-Item -LiteralPath (Join-Path $TemplatesDir 'accesskit.x86_64.dll') -Destination $out
    [IO.File]::WriteAllText((Join-Path $out 'template-path.txt'), $TemplatesDir)
}
$files = @(Get-ChildItem -LiteralPath $out -File | ForEach-Object {
    @{path=$_.Name; sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(); size_bytes=$_.Length}
})
@{schema_version=1; mode=$Mode; engine=@{version='4.7.2.stable'; files=@()}; template=$template; files=$files} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $out 'package-provenance.json') -Encoding UTF8
'@
    [IO.File]::WriteAllText((Join-Path $fixture 'tools/build_windows.ps1'), $builder, [Text.UTF8Encoding]::new($true))
    [IO.File]::WriteAllText((Join-Path $fixture 'tracked-data.txt'), 'COMMITTED')
    & git -C $fixture init -q
    & git -C $fixture add tools/build_windows.ps1 tools/windows_templates.ps1 tracked-data.txt
    Commit-Fixture 'fixture'
    $sha = & git -C $fixture rev-parse HEAD
    [IO.File]::WriteAllText((Join-Path $fixture 'tracked-data.txt'), 'DIRTY_WORKTREE')
    [IO.File]::WriteAllText((Join-Path $fixture 'private-untracked.gd'), 'PRIVATE')
    [IO.File]::WriteAllText((Join-Path $fixture 'tools/build_windows.ps1'), 'exit 99')
    $script:templates = Join-Path $fixture 'verified-templates'
    Write-Templates
    $env:APPDATA = Join-Path $fixture 'original-appdata'
    $env:LOCALAPPDATA = Join-Path $fixture 'original-localappdata'
    foreach ($activeCase in @('archive', 'release', 'rejected-source')) {
        if ($Case -ne 'all' -and $Case -ne $activeCase) { continue }
        $script:out = Join-Path $fixture "build/$activeCase"
        New-Item -ItemType Directory -Force -Path $script:out | Out-Null
        [IO.File]::WriteAllText((Join-Path $script:out 'old.txt'), 'KEEP')
        $env:LEDGER_CLEAN_IMPORT_ERROR = '0'
        $env:LEDGER_CLEAN_BUILDER_ERROR = '0'
        switch ($activeCase) {
            'archive' {
                $env:LEDGER_CLEAN_IMPORT_ERROR = '1'
                Check ((Run $sha) -ne 0) 'Godot script error with exit 0 accepted'
                Check-Old
                $env:LEDGER_CLEAN_IMPORT_ERROR = '0'
                Check ((Run 'missing-revision') -ne 0) 'invalid commit accepted'
                Check-Old
                Check ((Run $sha) -eq 0) "committed-only build failed: $script:lastOutput"
                Check ([IO.File]::ReadAllText((Join-Path $script:out '劫余录.exe')) -eq 'portable') 'portable mode not passed to archived builder'
                Check ([IO.File]::ReadAllText((Join-Path $script:out '字体许可.txt')) -eq 'portable') 'font license omitted'
                Check (-not (Test-Path -LiteralPath (Join-Path $script:out 'accesskit.x86_64.dll'))) 'portable copied release sidecar'
                $source = Get-Content -LiteralPath (Join-Path $script:out '构建来源.txt') -Raw -Encoding UTF8
                Check ($source.Contains($sha)) 'package lacks full source SHA'
                Check ($source.Contains('本机 Godot')) 'portable provenance omits external runtime'
                Check ($source.Contains('.gitignore 排除的素材')) 'provenance omits ignored assets'
                $packageManifest = Get-Content -LiteralPath (Join-Path $script:out 'package-provenance.json') -Raw -Encoding UTF8 | ConvertFrom-Json
                Check ($packageManifest.source_commit -eq $sha -and $packageManifest.mode -eq 'portable') 'JSON provenance lost source SHA/portable mode'
                $backup = @(Get-ChildItem -LiteralPath (Split-Path $script:out) -Directory -Filter "$activeCase.previous-*")
                Check ($backup.Count -eq 1 -and [IO.File]::ReadAllText((Join-Path $backup[0].FullName 'old.txt')) -eq 'KEEP') 'old output not retained'
            }
            'release' {
                Check ((Run $sha 'release' (Join-Path $fixture 'missing-templates')) -ne 0) 'missing template silently downgraded to portable'
                Check-Old
                $env:LEDGER_CLEAN_BUILDER_ERROR = '1'
                Check ((Run $sha 'release') -ne 0) 'release builder failure accepted'
                Check-Old
                $env:LEDGER_CLEAN_BUILDER_ERROR = '0'
                Check ((Run $sha 'release') -eq 0) "clean release fixture failed: $script:lastOutput"
                Check ([IO.File]::ReadAllText((Join-Path $script:out '劫余录.exe')) -eq 'release') 'release downgraded to portable'
                Check ((Get-FileHash -LiteralPath (Join-Path $script:out 'accesskit.x86_64.dll') -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath (Join-Path $script:templates 'accesskit.x86_64.dll') -Algorithm SHA256).Hash) 'clean release omitted or changed sidecar'
                $copiedTemplates = [IO.File]::ReadAllText((Join-Path $script:out 'template-path.txt'))
                Check (-not $copiedTemplates.StartsWith($fixture, [StringComparison]::OrdinalIgnoreCase)) 'clean build reused caller template directory'
                Check (-not (Test-Path -LiteralPath $copiedTemplates)) 'isolated template directory not cleaned'
                $packageManifest = Get-Content -LiteralPath (Join-Path $script:out 'package-provenance.json') -Raw -Encoding UTF8 | ConvertFrom-Json
                Check ($packageManifest.source_commit -eq $sha -and $packageManifest.mode -eq 'release') 'JSON provenance lost source SHA/release mode'
                Check ($packageManifest.template.source.sha256 -eq 'f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011') 'JSON provenance lost official archive digest'
                Check (@($packageManifest.files | Where-Object {$_.path -eq 'accesskit.x86_64.dll'}).Count -eq 1) 'provenance omits copied release sidecar'
                Check ((Get-Content -LiteralPath (Join-Path $script:out '构建来源.txt') -Raw -Encoding UTF8).Contains('release')) 'human provenance omits release mode'
                Check (Test-Path -LiteralPath (Join-Path $script:templates 'windows_release_x86_64.exe')) 'clean build deleted original template'
            }
            'rejected-source' {
                New-Item -ItemType Directory -Path (Join-Path $fixture 'nested') | Out-Null
                [IO.File]::WriteAllText((Join-Path $fixture 'nested/.gitattributes'), "*.bin filter=lfs" + [Environment]::NewLine)
                & git -C $fixture add nested/.gitattributes
                Commit-Fixture 'nested lfs'
                Check ((Run 'HEAD') -ne 0) 'nested Git LFS attributes accepted'
                Check-Old
                [IO.File]::WriteAllText((Join-Path $fixture 'nested/.gitattributes'), "# no filter" + [Environment]::NewLine)
                [IO.File]::WriteAllText((Join-Path $fixture 'nested/pointer.bin'), (@('version https://git-lfs.github.com/spec/v1', 'oid sha256:fake', 'size 1') -join [Environment]::NewLine) + [Environment]::NewLine)
                & git -C $fixture add nested/.gitattributes nested/pointer.bin
                Commit-Fixture 'lfs pointer'
                Check ((Run 'HEAD') -ne 0) 'LFS pointer accepted'
                Check-Old
            }
        }
        Check ($env:APPDATA -eq (Join-Path $fixture 'original-appdata')) 'caller APPDATA changed'
        Check ($env:LOCALAPPDATA -eq (Join-Path $fixture 'original-localappdata')) 'caller LOCALAPPDATA changed'
        Check (@(Get-ChildItem -LiteralPath (Split-Path $script:out) -Force -Directory -Filter ".$activeCase.staging-*").Count -eq 0) 'failed/successful staging leaked'
        $completed++
        Write-Output "[windows_build_clean:$activeCase] PASS"
    }
    Write-Output "[windows_build_clean] $checks checks, $completed cases, 0 failures"
} finally {
    $env:LEDGER_CLEAN_IMPORT_ERROR = $oldImportError
    $env:LEDGER_CLEAN_BUILDER_ERROR = $oldBuilderError
    $env:APPDATA = $oldAppData
    $env:LOCALAPPDATA = $oldLocalAppData
    if (Test-Path -LiteralPath $fixture -PathType Container) {
        $resolved = (Resolve-Path -LiteralPath $fixture).ProviderPath
        $item = Get-Item -LiteralPath $fixture -Force
        if ($resolved -eq [IO.Path]::GetFullPath($fixture) -and $resolved.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            Remove-Item -LiteralPath $fixture -Recurse -Force
        }
    }
}
