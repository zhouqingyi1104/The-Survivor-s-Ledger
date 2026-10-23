$ErrorActionPreference = 'Stop'
# Local companion only: never block game startup or put ARK credentials in Godot.
$directorDir = Join-Path $env:LOCALAPPDATA 'SurvivorsLedger/director'
$configPath = Join-Path $directorDir 'connection.json'
$mutex = [Threading.Mutex]::new($false, 'Local\SurvivorsLedgerStoryDirector')
if (-not $mutex.WaitOne(0)) { $mutex.Dispose(); exit 0 }
try {
    if (Test-Path -LiteralPath $configPath) {
        try {
            $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            $health = Invoke-RestMethod -Uri ("http://127.0.0.1:{0}/health" -f [int]$config.port) -Headers @{Authorization=('Bearer ' + $config.token)} -TimeoutSec 1
            if ($health.app -eq 'ledger-director' -and $health.version -eq 1) { exit 0 }
        } catch { }
    }
    $node = (Get-Command node -ErrorAction Stop).Source
    $binary = Join-Path $env:APPDATA 'npm/node_modules/@volcengine/ark-cli/bin/arkcli-windows-amd64.exe'
    if (-not (Test-Path -LiteralPath $binary)) { exit 0 }
    [IO.Directory]::CreateDirectory($directorDir) | Out-Null
    $server = Join-Path $PSScriptRoot 'bridge.mjs'
    Start-Process -FilePath $node -ArgumentList @(('"'+$server+'"'),('"'+$directorDir+'"'),('"'+$binary+'"'),'agent-plan_cn-beijing_personal') -WindowStyle Hidden -RedirectStandardOutput (Join-Path $directorDir 'bridge.log') -RedirectStandardError (Join-Path $directorDir 'bridge-error.log') | Out-Null
} catch {
    # Missing local tools means ordinary offline play, not a game-start failure.
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
