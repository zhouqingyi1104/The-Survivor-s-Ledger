$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
$fixture = Join-Path $tempRoot ('ledger-build-test-' + [Guid]::NewGuid().ToString('N'))
if (-not $fixture.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid fixture location' }
New-Item -ItemType Directory -Path (Join-Path $fixture 'tools/godot') -Force | Out-Null
$checks = 0
function Check($condition, $message) {
	$script:checks++
	if (-not $condition) { throw "FAIL: $message" }
}
try {
	Copy-Item -LiteralPath (Join-Path $repo 'tools/build_windows.ps1') -Destination (Join-Path $fixture 'tools/build_windows.ps1')
	Copy-Item -LiteralPath (Join-Path $repo 'export_presets.cfg') -Destination (Join-Path $fixture 'export_presets.cfg')
	$fakeSource = @'
using System;
using System.IO;
class FakeGodot {
 static int Main(string[] args) {
  if (Array.IndexOf(args, "--version") >= 0) { Console.WriteLine("4.7.2.stable.official.mock"); return 0; }
  string scenario = Environment.GetEnvironmentVariable("LEDGER_BUILD_TEST_CASE");
  if (scenario == "fail") return 8;
  string target = args[args.Length - 1];
  bool release = Array.IndexOf(args, "--export-release") >= 0;
  if (scenario != "missing_pck") File.WriteAllText(release ? Path.ChangeExtension(target, ".pck") : target, "NEW_PCK");
  if (release && scenario != "missing_exe") File.WriteAllText(target, "NEW_RELEASE_EXE");
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
	$oldAppData = $env:APPDATA
	$oldCase = $env:LEDGER_BUILD_TEST_CASE
	$env:APPDATA = Join-Path $fixture 'appdata'
	$template = Join-Path $env:APPDATA 'Godot/export_templates/4.7.2.stable'
	New-Item -ItemType Directory -Force -Path $template | Out-Null
	[IO.File]::WriteAllText((Join-Path $template 'windows_release_x86_64.exe'), 'MOCK_TEMPLATE')
	$out = Join-Path $fixture 'build/windows'
	New-Item -ItemType Directory -Force -Path $out | Out-Null
	[IO.File]::WriteAllText((Join-Path $out '劫余录.exe'), 'OLD_EXE')
	[IO.File]::WriteAllText((Join-Path $out '劫余录.pck'), 'OLD_PCK')
	[IO.File]::WriteAllText((Join-Path $out 'user-note.txt'), 'DO_NOT_DELETE')
	function Build($scenario, $mode, $preset = 'Windows Desktop') {
		$env:LEDGER_BUILD_TEST_CASE = $scenario
		$script = Join-Path $fixture 'tools/build_windows.ps1'
		$stdout = Join-Path $fixture 'stdout.txt'
		$stderr = Join-Path $fixture 'stderr.txt'
		$p = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-File', ('"' + $script + '"'), '-Mode', $mode, '-Preset', ('"' + $preset + '"')) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
		return $p.ExitCode
	}
	Check ((Build 'fail' 'portable') -ne 0) 'nonzero exporter exit was accepted'
	Check ([IO.File]::ReadAllText((Join-Path $out '劫余录.exe')) -eq 'OLD_EXE') 'failure replaced old exe'
	Check ([IO.File]::ReadAllText((Join-Path $out '劫余录.pck')) -eq 'OLD_PCK') 'failure replaced old pck'
	Check ((Build 'missing_pck' 'portable') -ne 0) 'missing pck accepted'
	Check ([IO.File]::ReadAllText((Join-Path $out 'user-note.txt')) -eq 'DO_NOT_DELETE') 'old user file lost after failure'
	Check ((Build 'ok' 'portable') -eq 0) 'portable export failed'
	Check ([IO.File]::ReadAllText((Join-Path $out '劫余录.exe')) -eq 'PORTABLE_RUNTIME') 'portable runtime incorrect'
	Check ([IO.File]::ReadAllText((Join-Path $out '劫余录.pck')) -eq 'NEW_PCK') 'portable pck incorrect'
	Check (-not (Test-Path -LiteralPath (Join-Path $out 'user-note.txt'))) 'old extra file leaked into package'
	$backups = @(Get-ChildItem -LiteralPath (Split-Path $out) -Directory -Filter 'windows.previous-*')
	Check ($backups.Count -eq 1) 'old package not retained'
	Check ([IO.File]::ReadAllText((Join-Path $backups[0].FullName 'user-note.txt')) -eq 'DO_NOT_DELETE') 'old user file not preserved in backup'
	Check ((Build 'missing_exe' 'release') -ne 0) 'missing release exe accepted'
	Check ([IO.File]::ReadAllText((Join-Path $out '劫余录.exe')) -eq 'PORTABLE_RUNTIME') 'failed release overwrote portable'
	Check ((Build 'missing_pck' 'release') -ne 0) 'nonembedded release missing pck accepted'
	Check ((Build 'ok' 'release') -eq 0) 'release fixture export failed'
	Check ([IO.File]::ReadAllText((Join-Path $out '劫余录.exe')) -eq 'NEW_RELEASE_EXE') 'release exe incorrect'
	Check ([IO.File]::ReadAllText((Join-Path $out '劫余录.pck')) -eq 'NEW_PCK') 'release pck incorrect'
	Check ((Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $out '读我.txt')).Contains('导出模板')) 'release readme incorrect'
	Check (@(Get-ChildItem -LiteralPath (Split-Path $out) -Directory -Filter 'windows.previous-*').Count -eq 2) 'portable output not retained after switch'
	Check ((Build 'missing_pck' 'release' 'Windows Desktop (console)') -eq 0) 'embedded release without pck rejected'
	Check (-not (Test-Path -LiteralPath (Join-Path $out '劫余录.pck'))) 'old pck leaked into embedded release'
	Check ((Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $out '读我.txt')).Contains('资源已嵌入')) 'embedded readme incorrect'
	Check (@(Get-ChildItem -LiteralPath (Split-Path $out) -Directory -Filter 'windows.previous-*').Count -eq 3) 'previous release not retained after switch'
	Check (@(Get-ChildItem -LiteralPath (Split-Path $out) -Force -Directory -Filter '.windows.staging-*').Count -eq 0) 'staging directory left behind'
	Write-Output "[windows_build] $checks checks, 0 failures"
} finally {
	$env:APPDATA = $oldAppData
	$env:LEDGER_BUILD_TEST_CASE = $oldCase
	if (Test-Path -LiteralPath $fixture -PathType Container) {
		$resolved = (Resolve-Path -LiteralPath $fixture).ProviderPath
		$item = Get-Item -LiteralPath $fixture -Force
		if ($resolved -eq [IO.Path]::GetFullPath($fixture) -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
			Remove-Item -LiteralPath $fixture -Recurse -Force
		}
	}
}
