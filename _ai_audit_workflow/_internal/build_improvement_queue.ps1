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
$sourceStatus = [string](Get-ObjectProperty -Object $state -Name 'status' -Default '')
if ($sourceStatus -eq 'fail') {
    $failure = [string](Get-ObjectProperty -Object $state -Name 'failure' -Default 'Audit failed.')
    $runId = [string](Get-ObjectProperty -Object $state -Name 'runId' -Default '')
    $invalidQueue = [pscustomobject]@{
        generatedAt = (Get-Date).ToString('s')
        valid = $false
        count = 0
        evidenceBackedCount = 0
        reviewBackedCount = 0
        workflowEvidenceImprovementCount = 0
        policy = 'No queued evidence item is runnable from a failed audit. Run a fresh audit that ends in pass or pass with gaps before applying or previewing an item.'
        items = @()
    }
    ConvertTo-JsonFile -Value $invalidQueue -Path $queuePath
    @"
# Improvement Prompt Invalidated

The latest audit run failed, so this workflow will not produce an actionable fix, review, or workflow-evidence prompt from it.

Run id: $runId
Audit status: $sourceStatus
Failure: $failure

Fix the blocking audit/check failure, then run a fresh Light or Deep audit before applying any queued evidence item.
"@ | Set-Content -LiteralPath $promptPath -Encoding UTF8
    Write-Host 'blocked'
    Write-Host "Audit status is fail; no queue was generated. Prompt invalidated: $promptPath"
    exit 1
}
$artifactFreshAfterText = [string](Get-ObjectProperty -Object $state.artifacts -Name 'artifactFreshAfter' -Default '')
$artifactFreshAfter = [datetime]::MinValue
if ($artifactFreshAfterText.Trim().Length -gt 0) {
    $artifactFreshAfter = [datetime]::Parse($artifactFreshAfterText)
}
$eligible = @($state.findings | Where-Object {
    $_.eligibleForFix -eq $true -and $_.evidenceBacked -eq $true -and $_.status -eq 'open'
} | Sort-Object score, area, id)

$items = New-Object System.Collections.Generic.List[object]

function Get-SafeQueueIdPart {
    param([Parameter(Mandatory)][string] $Value)
    $safe = [regex]::Replace($Value.Trim().ToLowerInvariant(), '[^a-z0-9]+', '-').Trim('-')
    if ($safe.Length -eq 0) {
        return 'unknown'
    }
    if ($safe.Length -gt 64) {
        return $safe.Substring(0, 64).Trim('-')
    }
    return $safe
}

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

foreach ($gap in @($state.gaps)) {
    $area = [string](Get-ObjectProperty -Object $gap -Name 'area' -Default 'Evidence gap')
    $detail = [string](Get-ObjectProperty -Object $gap -Name 'detail' -Default '')
    $recommendedEvidence = [string](Get-ObjectProperty -Object $gap -Name 'recommendedEvidence' -Default '')
    $safeArea = Get-SafeQueueIdPart -Value $area
    $items.Add([pscustomobject]@{
        id = "workflow-evidence-$safeArea"
        lane = 'workflow-evidence-improvement'
        area = $area
        score = 0
        title = "Improve audit evidence path: $area"
        evidence = "$area evidence gap: $detail Recommended evidence: $recommendedEvidence"
        evidenceSource = $findingsPath
        confidence = 'medium'
        affectedSystem = 'audit workflow / evidence coverage'
        reproduction = ".\_ai_audit_workflow\RUN_AUDIT.ps1 -Tier $($state.tier)"
        verificationGap = $detail
        recommendedAction = 'Improve or document the audit workflow evidence path for this gap; do not change gameplay, content, data, scenes, assets, or save behavior from this queue item.'
        evidenceBacked = $false
        reviewBacked = $false
        workflowEvidenceImprovement = $true
        status = 'queued'
    })
}

$codeFixCount = @($items | Where-Object { $_.lane -eq 'evidence-backed code fix' }).Count
$reviewFixCount = @($items | Where-Object { $_.lane -eq 'review-backed polish fix' }).Count
$workflowFixCount = @($items | Where-Object { $_.lane -eq 'workflow-evidence-improvement' }).Count

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
    workflowEvidenceImprovementCount = $workflowFixCount
    policy = 'Evidence-backed code findings are first priority. Review-backed polish prompts are for bounded screenshot/performance review and must confirm concrete defects before editing. Workflow-evidence-improvement items are audit-harness or evidence-coverage work only; they must not change gameplay, content, data, scenes, assets, or save behavior.'
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

or preview the next item from the current queue before applying a fix or workflow evidence improvement.
"@ | Set-Content -LiteralPath $promptPath -Encoding UTF8

if ($items.Count -eq 0) {
    Write-Host 'pass with gaps'
    Write-Host "No evidence-backed, review-backed, or workflow evidence improvement items are queued. Review gaps in $findingsPath."
} else {
    Write-Host 'pass'
    Write-Host "Queued $($items.Count) improvement item(s): $codeFixCount evidence-backed, $reviewFixCount review-backed, $workflowFixCount workflow/evidence. $queuePath"
}
