param(
    [ValidateSet('all', 'export-failure', 'portable', 'release', 'template-validation', 'font-license')]
    [string]$Case = 'all'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
$fixture = Join-Path $tempRoot ('ledger-build-test-' + [Guid]::NewGuid().ToString('N'))
if (-not $fixture.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid fixture location' }
New-Item -ItemType Directory -Path (Join-Path $fixture 'tools/godot'),(Join-Path $fixture 'assets/fonts') -Force | Out-Null
$checks = 0
$completed = 0
$oldAppData = $env:APPDATA
$oldCase = $env:LEDGER_BUILD_TEST_CASE
$oldLog = $env:LEDGER_BUILD_TEST_LOG
function Check($condition, $message) {
    $script:checks++
    if (-not $condition) { throw "FAIL [$script:activeCase]: $message" }
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
    Write-Manifest
}
function Write-Manifest {
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
function Build($scenario, $mode, $preset = 'Windows Desktop', $templatesDir = $script:templates) {
    $env:LEDGER_BUILD_TEST_CASE = $scenario
    $env:LEDGER_BUILD_TEST_LOG = Join-Path $fixture 'export-calls.txt'
    [IO.File]::WriteAllText($env:LEDGER_BUILD_TEST_LOG, '')
    $scriptPath = Join-Path $fixture 'tools/build_windows.ps1'
    $stdout = Join-Path $fixture 'stdout.txt'
    $stderr = Join-Path $fixture 'stderr.txt'
    $args = @('-NoProfile', '-File', ('"' + $scriptPath + '"'), '-Mode', $mode, '-Preset', ('"' + $preset + '"'), '-OutDir', ('"' + $script:out + '"'), '-TemplatesDir', ('"' + $templatesDir + '"'))
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $cachedHandle = $p.Handle
    $p.WaitForExit()
    $script:lastOutput = ([IO.File]::ReadAllText($stdout) + [IO.File]::ReadAllText($stderr))
    return $p.ExitCode
}
function Check-Old {
    Check ([IO.File]::ReadAllText((Join-Path $script:out '劫余录.exe')) -eq 'OLD_EXE') 'failure replaced old exe'
    Check ([IO.File]::ReadAllText((Join-Path $script:out '劫余录.pck')) -eq 'OLD_PCK') 'failure replaced old pck'
    Check ([IO.File]::ReadAllText((Join-Path $script:out 'user-note.txt')) -eq 'DO_NOT_DELETE') 'failure removed old user file'
}
function Check-NoExport {
    Check (-not ([IO.File]::ReadAllText($env:LEDGER_BUILD_TEST_LOG).Contains('--export-'))) 'invalid dependency reached exporter'
}
try {
    foreach ($name in @('build_windows.ps1', 'windows_templates.ps1')) {
        Copy-Item -LiteralPath (Join-Path $repo "tools/$name") -Destination (Join-Path $fixture "tools/$name")
    }
    Copy-Item -LiteralPath (Join-Path $repo 'export_presets.cfg') -Destination (Join-Path $fixture 'export_presets.cfg')
    [IO.File]::WriteAllText((Join-Path $fixture 'assets/fonts/LICENSES.txt'), 'OFL LICENSE FIXTURE')
    $fakeSource = @'
using System;
using System.IO;
class FakeGodot {
 static int Main(string[] args) {
  if (Array.IndexOf(args, "--version") >= 0) { Console.WriteLine("4.7.2.stable.official.mock"); return 0; }
  File.AppendAllText(Environment.GetEnvironmentVariable("LEDGER_BUILD_TEST_LOG"), String.Join(" ", args) + Environment.NewLine);
  string scenario = Environment.GetEnvironmentVariable("LEDGER_BUILD_TEST_CASE");
  if (scenario == "fail") return 8;
  string target = args[args.Length - 1];
  bool release = Array.IndexOf(args, "--export-release") >= 0;
  if (release) {
   string templateDir = Path.Combine(Environment.GetEnvironmentVariable("APPDATA"), "Godot/export_templates/4.7.2.stable");
   if (!File.Exists(Path.Combine(templateDir, "provenance.json")) || !File.Exists(Path.Combine(templateDir, "windows_release_x86_64.exe"))) return 11;
   if (File.ReadAllText(Path.Combine(templateDir, "icudt_godot.dat")) != "MOCK_ICU") return 12;
   File.AppendAllText(Environment.GetEnvironmentVariable("LEDGER_BUILD_TEST_LOG"), "VERIFIED_TEMPLATE=" + templateDir + Environment.NewLine);
  }
  if (scenario != "missing_pck") File.WriteAllText(release ? Path.ChangeExtension(target, ".pck") : target, "NEW_PCK");
  if (release && scenario != "missing_exe") File.WriteAllText(target, "NEW_RELEASE_EXE");
  if (release) File.WriteAllText(Path.Combine(Path.GetDirectoryName(target), "accesskit.x86_64.dll"), "NEW_ACCESSKIT");
  return 0;
 }
}
'@
    $fakeCs = Join-Path $fixture 'fake.cs'
    [IO.File]::WriteAllText($fakeCs, $fakeSource)
    $godot = Join-Path $fixture 'tools/godot/Godot_v4.7.2-stable_win64_console.exe'
    $csc = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    & $csc /nologo /target:exe "/out:$godot" $fakeCs
    if ($LASTEXITCODE -ne 0) { throw 'Could not compile isolated fake exporter' }
    [IO.File]::WriteAllText((Join-Path $fixture 'tools/godot/Godot_v4.7.2-stable_win64.exe'), 'PORTABLE_RUNTIME')
    $env:APPDATA = Join-Path $fixture 'appdata'
    $script:templates = Join-Path $fixture 'verified-templates'
    foreach ($activeCase in @('export-failure', 'portable', 'release', 'template-validation', 'font-license')) {
        if ($Case -ne 'all' -and $Case -ne $activeCase) { continue }
        Write-Templates
        $script:out = Join-Path $fixture "build/$activeCase"
        New-Item -ItemType Directory -Force -Path $script:out | Out-Null
        [IO.File]::WriteAllText((Join-Path $script:out '劫余录.exe'), 'OLD_EXE')
        [IO.File]::WriteAllText((Join-Path $script:out '劫余录.pck'), 'OLD_PCK')
        [IO.File]::WriteAllText((Join-Path $script:out 'user-note.txt'), 'DO_NOT_DELETE')
        switch ($activeCase) {
            'export-failure' {
                Check ((Build 'fail' 'portable') -ne 0) 'nonzero exporter exit accepted'
                Check-Old
                Check ((Build 'missing_pck' 'portable') -ne 0) 'missing portable pck accepted'
                Check-Old
                Check ((Build 'missing_exe' 'release') -ne 0) 'missing release exe accepted'
                Check-Old
                Check ((Build 'missing_pck' 'release') -ne 0) 'nonembedded release missing pck accepted'
                Check-Old
            }
            'portable' {
                Check ((Build 'ok' 'portable' 'Windows Desktop' (Join-Path $fixture 'missing-templates')) -eq 0) "portable export failed: $script:lastOutput"
                Check ([IO.File]::ReadAllText((Join-Path $script:out '劫余录.exe')) -eq 'PORTABLE_RUNTIME') 'portable runtime incorrect'
                Check ([IO.File]::ReadAllText((Join-Path $script:out '劫余录.pck')) -eq 'NEW_PCK') 'portable pck incorrect'
                $readme = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $script:out '读我.txt')
                foreach ($text in @('本包不连接动态世情服务', '局内状态和前世档案不会发出', '不会产生任何服务费用', '动态世情：本包离线', '新开一卷', '导出试玩报告', '请先导出再合上')) {
                    Check ($readme.Contains($text)) "readme omits $text"
                }
                Check ([IO.File]::ReadAllText((Join-Path $script:out '字体许可.txt')) -eq 'OFL LICENSE FIXTURE') 'font license not copied verbatim'
                Check (-not (Test-Path -LiteralPath (Join-Path $script:out 'user-note.txt'))) 'old extra file leaked into package'
                Check (-not (Test-Path -LiteralPath (Join-Path $script:out 'accesskit.x86_64.dll'))) 'portable package gained release sidecar'
                $backups = @(Get-ChildItem -LiteralPath (Split-Path $script:out) -Directory -Filter "$activeCase.previous-*")
                Check ($backups.Count -eq 1) 'old package not retained'
                Check ([IO.File]::ReadAllText((Join-Path $backups[0].FullName 'user-note.txt')) -eq 'DO_NOT_DELETE') 'backup lost user file'
                Check ((Build 'ok' 'auto' 'Windows Desktop' (Join-Path $fixture 'missing-templates')) -eq 0) 'auto without templates did not use portable'
                Check ([IO.File]::ReadAllText((Join-Path $script:out '劫余录.exe')) -eq 'PORTABLE_RUNTIME') 'auto missing template runtime incorrect'
                Check ((Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $script:out '读我.txt')).Contains('https://godotengine.org/license')) 'Godot attribution link missing from readme'
            }
            'release' {
                Check ((Build 'ok' 'release') -eq 0) "release fixture export failed: $script:lastOutput"
                Check ([IO.File]::ReadAllText((Join-Path $script:out '劫余录.exe')) -eq 'NEW_RELEASE_EXE') 'release exe incorrect'
                Check ([IO.File]::ReadAllText((Join-Path $script:out '劫余录.pck')) -eq 'NEW_PCK') 'release pck incorrect'
                Check ([IO.File]::ReadAllText((Join-Path $script:out 'accesskit.x86_64.dll')) -eq 'NEW_ACCESSKIT') 'release sidecar lost'
                Check ([IO.File]::ReadAllText($env:LEDGER_BUILD_TEST_LOG).Contains('VERIFIED_TEMPLATE=')) 'release did not receive isolated verified template'
                $packageManifest = Get-Content -LiteralPath (Join-Path $script:out 'package-provenance.json') -Raw -Encoding UTF8 | ConvertFrom-Json
                Check ($packageManifest.mode -eq 'release' -and $packageManifest.template.version -eq '4.7.2.stable') 'package provenance lost release mode/template version'
                Check (@($packageManifest.files | Where-Object { $_.path -eq 'accesskit.x86_64.dll' -and $_.sha256 -eq (Get-FileHash -LiteralPath (Join-Path $script:out 'accesskit.x86_64.dll') -Algorithm SHA256).Hash.ToLowerInvariant() }).Count -eq 1) 'package provenance lost sidecar hash'
                Check ((Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $script:out '读我.txt')).Contains('导出模板')) 'release readme incorrect'
                Check ((Build 'missing_pck' 'release' 'Windows Desktop (console)') -eq 0) 'embedded release without pck rejected'
                Check (-not (Test-Path -LiteralPath (Join-Path $script:out '劫余录.pck'))) 'old pck leaked into embedded release'
                Check ((Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $script:out '读我.txt')).Contains('资源已嵌入')) 'embedded readme incorrect'
                Check ((Build 'ok' 'auto') -eq 0) 'auto with verified template failed'
                Check ([IO.File]::ReadAllText((Join-Path $script:out '劫余录.exe')) -eq 'NEW_RELEASE_EXE') 'auto with template used portable'
                Check (@(Get-ChildItem -LiteralPath (Split-Path $script:out) -Directory -Filter "$activeCase.previous-*").Count -eq 3) 'previous outputs lost across mode switches'
            }
            'template-validation' {
                Check ((Build 'ok' 'release' 'Windows Desktop' (Join-Path $fixture 'missing-templates')) -ne 0) 'missing release template accepted'
                Check-NoExport
                Check-Old
                [IO.File]::WriteAllText((Join-Path $script:templates 'version.txt'), '4.6.0.stable')
                Write-Manifest
                Check ((Build 'ok' 'release') -ne 0) 'wrong template version accepted'
                Check-NoExport
                Write-Templates
                $templateExe = Join-Path $script:templates 'windows_release_x86_64.exe'
                $bytes = [IO.File]::ReadAllBytes($templateExe); $bytes[200] = 1
                [IO.File]::WriteAllBytes($templateExe, $bytes)
                Check ((Build 'ok' 'release') -ne 0) 'changed template hash accepted'
                Check-NoExport
                Check ((Build 'ok' 'auto') -ne 0) 'auto silently downgraded a corrupt template to portable'
                Check-NoExport
                Write-Templates
                $bytes = [IO.File]::ReadAllBytes($templateExe)
                [BitConverter]::GetBytes([uint16]0x014c).CopyTo($bytes, 132)
                [IO.File]::WriteAllBytes($templateExe, $bytes)
                Write-Manifest
                Check ((Build 'ok' 'release') -ne 0) 'x86 PE template accepted as x64'
                Check-NoExport
                Write-Templates
                $manifestPath = Join-Path $script:templates 'provenance.json'
                $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $manifest.source.url = 'https://example.invalid/unverified.tpz'
                $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
                Check ((Build 'ok' 'release') -ne 0) 'unapproved source accepted'
                Check-NoExport
                Write-Templates
                [IO.File]::WriteAllText((Join-Path $script:templates 'unexpected.dll'), 'UNVERIFIED')
                Check ((Build 'ok' 'release') -ne 0) 'unlisted dependency accepted'
                Check-NoExport
                Check-Old
                Remove-Item -LiteralPath (Join-Path $script:templates 'unexpected.dll')
                $presetPath = Join-Path $fixture 'export_presets.cfg'
                $presetText = [IO.File]::ReadAllText($presetPath)
                [IO.File]::WriteAllText($presetPath, $presetText.Replace('custom_template/release=""', 'custom_template/release="res://unverified.exe"'), [Text.UTF8Encoding]::new($true))
                Check ((Build 'ok' 'release') -ne 0) 'custom preset template bypassed verification'
                Check-NoExport
                Check-Old
                [IO.File]::WriteAllText($presetPath, $presetText, [Text.UTF8Encoding]::new($true))
            }
            'font-license' {
                $licensePath = Join-Path $fixture 'assets/fonts/LICENSES.txt'
                Remove-Item -LiteralPath $licensePath
                Check ((Build 'ok' 'portable') -ne 0) 'missing font license accepted'
                Check-Old
                [IO.File]::WriteAllText($licensePath, '')
                Check ((Build 'ok' 'release') -ne 0) 'empty font license accepted'
                Check ([IO.File]::ReadAllText($env:LEDGER_BUILD_TEST_LOG).Contains('--export-release')) 'empty license case failed before export'
                Check-Old
                [IO.File]::WriteAllText($licensePath, 'OFL LICENSE FIXTURE')
            }
        }
        Check (@(Get-ChildItem -LiteralPath (Split-Path $script:out) -Force -Directory -Filter ".$activeCase.staging-*").Count -eq 0) 'staging directory left behind'
        $completed++
        Write-Output "[windows_build:$activeCase] PASS"
    }
    Write-Output "[windows_build] $checks checks, $completed cases, 0 failures"
} finally {
    $env:APPDATA = $oldAppData
    $env:LEDGER_BUILD_TEST_CASE = $oldCase
    $env:LEDGER_BUILD_TEST_LOG = $oldLog
    if (Test-Path -LiteralPath $fixture -PathType Container) {
        $resolved = (Resolve-Path -LiteralPath $fixture).ProviderPath
        $item = Get-Item -LiteralPath $fixture -Force
        if ($resolved -eq [IO.Path]::GetFullPath($fixture) -and $resolved.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            Remove-Item -LiteralPath $fixture -Recurse -Force
        }
    }
}
