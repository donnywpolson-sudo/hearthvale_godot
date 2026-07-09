param()

. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Assert-HearthvaleRepo
$config = Read-WorkflowConfig
$stateDir = Ensure-WorkflowState -Config $config
$findingsPath = Join-Path $stateDir 'findings.json'
$queuePath = Join-Path $stateDir 'improvement_queue.json'
$promptPath = Join-Path $stateDir 'next_improvement_prompt.md'

if (-not (Test-Path -LiteralPath $findingsPath)) {
    throw "Missing findings file. Run .\_ai_audit_workflow\RUN_AUDIT.ps1 first."
}

$state = Get-Content -Raw -LiteralPath $findingsPath | ConvertFrom-Json
$artifactFreshAfterText = [string](Get-ObjectProperty -Object $state.artifacts -Name 'artifactFreshAfter' -Default '')
$artifactFreshAfter = [datetime]::MinValue
if ($artifactFreshAfterText.Trim().Length -gt 0) {
    $artifactFreshAfter = [datetime]::Parse($artifactFreshAfterText)
}
$eligible = @($state.findings | Where-Object {
    $_.eligibleForFix -eq $true -and $_.evidenceBacked -eq $true -and $_.status -eq 'open'
} | Sort-Object score, area, id)

$items = New-Object System.Collections.Generic.List[object]

foreach ($finding in $eligible) {
    $items.Add([pscustomobject]@{
        id = $finding.id
        lane = 'evidence-backed code fix'
        area = $finding.area
        score = $finding.score
        title = $finding.title
        evidence = $finding.evidence
        evidenceSource = [string](Get-ObjectProperty -Object $finding -Name 'evidenceSource' -Default '')
        confidence = [string](Get-ObjectProperty -Object $finding -Name 'confidence' -Default '')
        affectedSystem = [string](Get-ObjectProperty -Object $finding -Name 'affectedSystem' -Default '')
        reproduction = [string](Get-ObjectProperty -Object $finding -Name 'reproduction' -Default '')
        verificationGap = [string](Get-ObjectProperty -Object $finding -Name 'verificationGap' -Default '')
        replayCommand = [string](Get-ObjectProperty -Object $finding -Name 'replayCommand' -Default '')
        buildHash = [string](Get-ObjectProperty -Object $finding -Name 'buildHash' -Default '')
        snapshotPath = [string](Get-ObjectProperty -Object $finding -Name 'snapshotPath' -Default '')
        stateDigest = [string](Get-ObjectProperty -Object $finding -Name 'stateDigest' -Default '')
        recommendedAction = $finding.recommendedAction
        evidenceBacked = $true
        reviewBacked = $false
        status = 'queued'
    })
}

$visualScore = $state.scores | Where-Object { $_.key -eq 'visual_audio_confidence' } | Select-Object -First 1
$visualReviewPath = [string](Get-ObjectProperty -Object $state.artifacts -Name 'visualReview' -Default '')
if ($null -ne $visualScore -and [int]$visualScore.score -lt [int]$config.scoreThresholdForQueue -and $visualReviewPath.Trim().Length -gt 0) {
    $items.Add([pscustomobject]@{
        id = 'review-visual-screenshots'
        lane = 'review-backed polish fix'
        area = 'Visual/UI polish'
        score = [int]$visualScore.score
        title = 'Review latest screenshots for concrete visual/UI fixes'
        evidence = "Visual/audio confidence score $($visualScore.score)/100 and screenshot folder: $visualReviewPath"
        recommendedAction = 'Manually inspect the latest visual review screenshots, identify concrete visible UI/visual defects, and fix only the smallest confirmed issues.'
        evidenceBacked = $false
        reviewBacked = $true
        status = 'queued'
    })
}

$performancePath = Join-Path $repoRoot $config.performanceObservations
$performance = Read-FreshJsonFileOrNull -Path $performancePath -EarliestWriteTime $artifactFreshAfter
$overBudget = @()
if ($null -ne $performance) {
    $overBudget = @(Get-ObjectProperty -Object $performance -Name 'observations' -Default @() | Where-Object {
        [string](Get-ObjectProperty -Object $_ -Name 'status' -Default '') -eq 'over_budget'
    })
}
if ($overBudget.Count -gt 0) {
    $evidenceParts = New-Object System.Collections.Generic.List[string]
    foreach ($observation in $overBudget) {
        $key = [string](Get-ObjectProperty -Object $observation -Name 'key' -Default 'performance')
        $value = Get-ObjectProperty -Object $observation -Name 'value'
        $budget = Get-ObjectProperty -Object $observation -Name 'budget'
        $evidenceParts.Add("$key=$value over budget $budget")
    }
    $items.Add([pscustomobject]@{
        id = 'review-performance-hotspots'
        lane = 'review-backed polish fix'
        area = 'Performance'
        score = 70
        title = 'Inspect repeated performance hotspots before optimizing'
        evidence = "$(($evidenceParts.ToArray()) -join '; ') in $($config.performanceObservations)"
        recommendedAction = 'Inspect performance observations and top slow samples, confirm a small code-level cause, then fix only that confirmed hotspot.'
        evidenceBacked = $false
        reviewBacked = $true
        status = 'queued'
    })
}

$codeFixCount = @($items | Where-Object { $_.lane -eq 'evidence-backed code fix' }).Count
$reviewFixCount = @($items | Where-Object { $_.lane -eq 'review-backed polish fix' }).Count

$queue = [pscustomobject]@{
    generatedAt = (Get-Date).ToString('s')
    sourceFindings = $findingsPath
    sourceRunId = [string](Get-ObjectProperty -Object $state -Name 'runId' -Default '')
    sourceStatus = [string](Get-ObjectProperty -Object $state -Name 'status' -Default '')
    publishStatus = [string](Get-ObjectProperty -Object $state.artifacts -Name 'publishStatus' -Default '')
    runStrength = [string](Get-ObjectProperty -Object $state.artifacts -Name 'runStrength' -Default '')
    coverageScope = [string](Get-ObjectProperty -Object $state.artifacts -Name 'coverageScope' -Default '')
    count = $items.Count
    evidenceBackedCount = $codeFixCount
    reviewBackedCount = $reviewFixCount
    policy = 'Evidence-backed code findings are first priority. Review-backed polish prompts are allowed for bounded screenshot review and performance hotspot inspection; they must confirm concrete defects before editing.'
    items = @($items.ToArray())
}

ConvertTo-JsonFile -Value $queue -Path $queuePath

@"
# Stale Improvement Prompt Invalidated

The improvement queue was rebuilt at $($queue.generatedAt), so any prompt generated before this queue is stale.

Run:

```powershell
.\_ai_audit_workflow\RUN_AUDIT.ps1 -NextFix
```

or preview the next item from the current queue before applying a fix.
"@ | Set-Content -LiteralPath $promptPath -Encoding UTF8

if ($items.Count -eq 0) {
    Write-Host 'pass with gaps'
    Write-Host "No evidence-backed or review-backed improvement items are queued. Review gaps in $findingsPath."
} else {
    Write-Host 'pass'
    Write-Host "Queued $($items.Count) improvement item(s): $codeFixCount evidence-backed, $reviewFixCount review-backed. $queuePath"
}
