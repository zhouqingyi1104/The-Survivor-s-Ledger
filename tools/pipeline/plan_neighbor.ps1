param([switch]$Generate)
$ErrorActionPreference = 'Stop'
# Authoring only. Never called by Godot; no player state or secrets enter prompts.
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$designPath = Join-Path $projectRoot 'docs/11-neighbor-medicine.md'
$prompt = @"
你是古风生存游戏《劫余录》的剧情策划。根据以下已经确定的规则，规划延迟后果并找出叙事漏洞。
只输出 JSON：premise(string)、branches(array，每项 choice/next_day_effect/final_effect)、pitfalls(string array)。
不要输出推理过程，不超过 1200 中文字。不得改变成本、发奖条件、截止时间或增加系统。
不要把措辞差异当作不同后果。全部分支在游戏启动前备齐，游戏内不发请求。
规则：
$([IO.File]::ReadAllText($designPath))
"@
if (-not $Generate) {
    Write-Output '预览：不会调用模型。执行 -Generate 才会使用当前 ARK profile 套餐额度。'
    Write-Output '固定参数：+chat --reasoning-effort low --max-output-tokens 2600 --format json'
    exit 0
}
$names = @('ARKCLI_NO_UPDATE_NOTIFIER','ARKCLI_CALLER_TYPE','ARKCLI_CALLER_NAME','ARKCLI_SKILL_NAME')
$previous = @{}
foreach ($name in $names) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    $env:ARKCLI_NO_UPDATE_NOTIFIER = '1'
    $env:ARKCLI_CALLER_TYPE = 'ai_agent'
    $env:ARKCLI_CALLER_NAME = 'codex'
    $env:ARKCLI_SKILL_NAME = 'arkcli-chat'
    # Do not pick a model or change the user's profile; use its current text default.
    $raw = & arkcli +chat --reasoning-effort low --max-output-tokens 2600 --format json $prompt
    if ($LASTEXITCODE -ne 0) { throw 'ARK 请求失败；不重试，不覆盖既有内容。请先核对认证状态。' }
    $response = ($raw -join "`n") | ConvertFrom-Json
    $plan = $response.content | ConvertFrom-Json
    if ($plan.premise -isnot [string] -or $plan.branches.Count -lt 2 -or $plan.branches.Count -gt 30 -or $plan.pitfalls.Count -lt 1) { throw '候选结构无效；不应用到游戏。' }
    foreach ($branch in $plan.branches) {
        foreach ($field in @('choice','next_day_effect','final_effect')) {
            if ($branch.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($branch.$field)) { throw '候选分支缺少实际后果。' }
        }
    }
    # New file each time; failed or repeated submissions never overwrite a reviewed pack.
    $outputDir = Join-Path ([IO.Path]::GetTempPath()) 'unknownGame-story-plans'
    [IO.Directory]::CreateDirectory($outputDir) | Out-Null
    $outputPath = Join-Path $outputDir ('neighbor-' + [guid]::NewGuid().ToString('N') + '.json')
    $artifact = @{ plan=$plan; provenance=@{response_id=$response.id; model=$response.model; reasoning_effort='low'; usage=$response.usage; reviewed=$false} }
    [IO.File]::WriteAllText($outputPath, ($artifact | ConvertTo-Json -Depth 15), [Text.UTF8Encoding]::new($false))
    Write-Output "候选已保存：$outputPath"
    Write-Output '候选不会自动替换游戏事件；需按 docs/11 审核规则、后果与文案。'
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process') }
}
