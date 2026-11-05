# Thin Windows entry point. Game processes and test evidence are isolated by Python.
[CmdletBinding()]
param(
    [ValidateSet('fast', 'core', 'ui', 'full')][string]$Tier = 'fast',
    [string[]]$Case,
    [switch]$List,
    [Alias('GodotPath')][string]$Godot,
    [string]$OutputRoot,
    [string]$Manifest,
    [double]$ImportTimeout = 240
)
$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'run_tests.py'
$pythonPath = $null
foreach ($name in @('python', 'python3')) {
    foreach ($candidate in @(Get-Command $name -CommandType Application -ErrorAction SilentlyContinue)) {
        $candidatePath = [string]$candidate.Source
        if ($candidatePath -match '[\\/]Microsoft[\\/]WindowsApps[\\/]') { continue }
        & $candidatePath -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)'
        if ($LASTEXITCODE -eq 0) { $pythonPath = $candidatePath; break }
    }
    if ($pythonPath) { break }
}
if (-not $pythonPath) { throw 'Existing Python 3.10+ was not found; this runner never downloads or installs dependencies.' }
$runnerArgs = @($runner, '--tier', $Tier, '--import-timeout', $ImportTimeout.ToString([Globalization.CultureInfo]::InvariantCulture))
foreach ($id in $Case) { $runnerArgs += @('--case', $id) }
if ($List) { $runnerArgs += '--list' }
if ($Godot) { $runnerArgs += @('--godot', $Godot) }
if ($OutputRoot) { $runnerArgs += @('--output-root', $OutputRoot) }
if ($Manifest) { $runnerArgs += @('--manifest', $Manifest) }
& $pythonPath @runnerArgs
exit $LASTEXITCODE
