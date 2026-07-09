param(
    [string] $FindingId = '',
    [switch] $PrintPrompt,
    [switch] $MenuPreview,
    [switch] $RunCodex,
    [switch] $AllowDirtyApply
)

. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Assert-HearthvaleRepo
$config = Read-WorkflowConfig
$stateDir = Ensure-WorkflowState -Config $config
$queuePath = Join-Path $stateDir 'improvement_queue.json'
$promptPath = Join-Path $stateDir 'next_improvement_prompt.md'
$resultPath = Join-Path $stateDir 'last_improvement_result.md'
$resultLogDir = Join-Path $stateDir 'result_logs'

function Get-SafeArchiveNamePart {
    param([Parameter(Mandatory)][string] $Value)
    $safe = [regex]::Replace($Value.Trim(), '[^A-Za-z0-9._-]+', '_').Trim('_')
    if ($safe.Length -eq 0) {
        return 'unknown'
    }
    if ($safe.Length -gt 80) {
        return $safe.Substring(0, 80)
    }
    return $safe
}

function New-QueueArtifactPath {
    param(
        [Parameter(Mandatory)][string] $ItemId,
        [Parameter(Mandatory)][string] $Kind
    )
    if (-not (Test-Path -LiteralPath $resultLogDir)) {
        New-Item -ItemType Directory -Path $resultLogDir | Out-Null
    }
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $safeId = Get-SafeArchiveNamePart -Value $ItemId
    $safeKind = Get-SafeArchiveNamePart -Value $Kind
    $candidate = Join-Path $resultLogDir ('{0}_{1}_{2}.md' -f $timestamp, $safeId, $safeKind)
    $suffix = 1
    while (Test-Path -LiteralPath $candidate) {
        $candidate = Join-Path $resultLogDir ('{0}_{1}_{2}_{3}.md' -f $timestamp, $safeId, $safeKind, $suffix)
        $suffix += 1
    }
    return $candidate
}

function Copy-QueueArtifact {
    param(
        [Parameter(Mandatory)][string] $SourcePath,
        [Parameter(Mandatory)][string] $ItemId,
        [Parameter(Mandatory)][string] $Kind
    )
    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "Cannot archive missing queue artifact: $SourcePath"
    }
    $archivePath = New-QueueArtifactPath -ItemId $ItemId -Kind $Kind
    Copy-Item -LiteralPath $SourcePath -Destination $archivePath
    return $archivePath
}

function Set-QueueItemProperty {
    param(
        [Parameter(Mandatory)] $QueueItem,
        [Parameter(Mandatory)][string] $Name,
        $Value
    )
    if ($null -eq $QueueItem.PSObject.Properties[$Name]) {
        $QueueItem | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    } else {
        $QueueItem.PSObject.Properties[$Name].Value = $Value
    }
}

function Set-QueueItemHandled {
    param(
        [Parameter(Mandatory)] $Queue,
        [Parameter(Mandatory)][string] $ItemId,
        [Parameter(Mandatory)][string] $ResultPath,
        [Parameter(Mandatory)][string] $PromptArchivePath,
        [Parameter(Mandatory)][string[]] $PostGitStatus,
        [Parameter(Mandatory)][string] $Outcome
    )

    foreach ($queueItem in @($Queue.items)) {
        if ([string]$queueItem.id -eq $ItemId) {
            $queueItem.status = 'handled'
            Set-QueueItemProperty -QueueItem $queueItem -Name 'handledAt' -Value (Get-Date).ToString('s')
            Set-QueueItemProperty -QueueItem $queueItem -Name 'promptPath' -Value $PromptArchivePath
            Set-QueueItemProperty -QueueItem $queueItem -Name 'resultPath' -Value $ResultPath
            Set-QueueItemProperty -QueueItem $queueItem -Name 'postGitStatus' -Value @($PostGitStatus)
            Set-QueueItemProperty -QueueItem $queueItem -Name 'postDiffCheck' -Value 'passed'
            Set-QueueItemProperty -QueueItem $queueItem -Name 'handledOutcome' -Value $Outcome
        }
    }
    ConvertTo-JsonFile -Value $Queue -Path $queuePath
}

function Get-RequiredLineValue {
    param(
        [Parameter(Mandatory)][string] $Text,
        [Parameter(Mandatory)][string] $Label
    )
    $pattern = '(?im)^{0}:\s*(.+)$' -f [regex]::Escape($Label)
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success -or $match.Groups[1].Value.Trim().Length -eq 0) {
        throw "Codex result summary must include an exact '${Label}:' line before the queue item can be marked handled."
    }
    return $match.Groups[1].Value.Trim()
}

function Assert-ResultSummaryForQueueItem {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)] $Item,
        [Parameter(Mandatory)][string] $Lane
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Codex did not write a result summary: $Path"
    }
    $text = Get-Content -Raw -LiteralPath $Path
    if ($text.Trim().Length -eq 0) {
        throw "Codex wrote an empty result summary: $Path"
    }
    $handledId = Get-RequiredLineValue -Text $text -Label 'Finding handled'
    if ($handledId -ne [string]$Item.id) {
        throw "Codex result summary handled finding '$handledId', but the selected queue item is '$($Item.id)'."
    }
    $evidenceChecked = Get-RequiredLineValue -Text $text -Label 'Evidence checked'
    if ($evidenceChecked -match '^(none|n/a|not checked)$') {
        throw "Codex result summary cannot mark the queue item handled without concrete evidence checked."
    }
    $outcome = (Get-RequiredLineValue -Text $text -Label 'Outcome').ToLowerInvariant()
    if ($outcome -eq 'blocked') {
        throw "Codex reported the selected queue item is blocked; it cannot be marked handled."
    }
    if ($outcome -notin @('fixed', 'no-code-change')) {
        throw "Codex result summary Outcome must be 'fixed' or 'no-code-change' before the queue item can be marked handled."
    }
    $filesChanged = Get-RequiredLineValue -Text $text -Label 'Files changed'
    $validationRun = Get-RequiredLineValue -Text $text -Label 'Validation run'
    if ($outcome -eq 'fixed') {
        if ($filesChanged -match '^(none|no files|n/a)$') {
            throw "Codex reported Outcome fixed but did not list changed files."
        }
        if ($validationRun -match '^(none|not run|n/a)$') {
            throw "Codex reported Outcome fixed but did not list targeted validation."
        }
    }
    if ($outcome -eq 'no-code-change' -and $Lane -eq 'evidence-backed code fix') {
        [void](Get-RequiredLineValue -Text $text -Label 'No code change reason')
    }
    return [pscustomobject]@{
        outcome = $outcome
        evidenceChecked = $evidenceChecked
        filesChanged = $filesChanged
        validationRun = $validationRun
    }
}

function Invoke-DiffCheckOrThrow {
    param([Parameter(Mandatory)][string] $RepoRoot)
    Push-Location $RepoRoot
    try {
        git -c core.autocrlf=false diff --check
        $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
        if ($exitCode -ne 0) {
            throw "git diff --check failed after Codex execution with exit code $exitCode."
        }
    } finally {
        Pop-Location
    }
}

if (-not (Test-Path -LiteralPath $queuePath)) {
    Write-Host 'No improvement queue found yet.'
    Write-Host 'Choose Light audit or Deep audit first, then come back to Next fix/review prompt.'
    Write-StepSummary -Step 'next fix prompt' -Status 'skipped' -LogPath $queuePath -Detail 'No improvement queue found.'
    exit 0
}

$queue = Get-Content -Raw -LiteralPath $queuePath | ConvertFrom-Json
$items = @($queue.items)
if ($FindingId.Trim().Length -gt 0) {
    $item = $items | Where-Object { $_.id -eq $FindingId } | Select-Object -First 1
} else {
    $item = $items | Where-Object { $_.status -eq 'queued' } | Select-Object -First 1
}

if ($null -eq $item) {
    @'
# No Queued Improvement Item

The latest queue has no queued evidence-backed implementation finding or review-backed polish prompt.

Run a manual evidence pass for the residual gaps, or run a fresh deep/full audit after the current batch is complete.
'@ | Set-Content -LiteralPath $promptPath -Encoding UTF8
    Write-Host 'pass with gaps'
    Write-Host "No queued item. Prompt written: $promptPath"
    Write-StepSummary -Step 'next fix prompt' -Status 'pass with gaps' -LogPath $promptPath -Detail 'No queued evidence-backed or review-backed item.'
    exit 0
}

$lane = if ($null -ne $item.PSObject.Properties['lane']) { [string]$item.lane } else { 'evidence-backed code fix' }
$isReviewBacked = $lane -eq 'review-backed polish fix'
$selectionLabel = if ($isReviewBacked) { 'review-backed polish prompt' } else { 'evidence-backed fix' }
$queueGeneratedAt = [string](Get-ObjectProperty -Object $queue -Name 'generatedAt' -Default '')
$queueSourceRunId = [string](Get-ObjectProperty -Object $queue -Name 'sourceRunId' -Default '')
$queueSourceFindings = [string](Get-ObjectProperty -Object $queue -Name 'sourceFindings' -Default '')
$queuePublishStatus = [string](Get-ObjectProperty -Object $queue -Name 'publishStatus' -Default '')
$evidenceSource = [string](Get-ObjectProperty -Object $item -Name 'evidenceSource' -Default '')
$confidence = [string](Get-ObjectProperty -Object $item -Name 'confidence' -Default '')
$affectedSystem = [string](Get-ObjectProperty -Object $item -Name 'affectedSystem' -Default '')
$reproduction = [string](Get-ObjectProperty -Object $item -Name 'reproduction' -Default '')
$verificationGap = [string](Get-ObjectProperty -Object $item -Name 'verificationGap' -Default '')
$replayCommand = [string](Get-ObjectProperty -Object $item -Name 'replayCommand' -Default '')
$buildHash = [string](Get-ObjectProperty -Object $item -Name 'buildHash' -Default '')
$snapshotPath = [string](Get-ObjectProperty -Object $item -Name 'snapshotPath' -Default '')
$stateDigest = [string](Get-ObjectProperty -Object $item -Name 'stateDigest' -Default '')
if (-not $isReviewBacked) {
    $hasEvidenceSource = $evidenceSource.Trim().Length -gt 0
    $hasReplayPath = $reproduction.Trim().Length -gt 0 -or $replayCommand.Trim().Length -gt 0
    $hasHashEvidence = $buildHash.Trim().Length -gt 0
    if (-not ($hasEvidenceSource -and $hasReplayPath -and $hasHashEvidence)) {
@"
# Queue Requires Fresh Audit Evidence

The selected evidence-backed queue item was generated before the hardened evidence contract.

Finding id: $($item.id)
Queue generated at: $queueGeneratedAt
Source findings: $queueSourceFindings

Run a fresh Light or Deep audit before applying this fix so the prompt can include evidence source, replay command, build hash, snapshot path, and state digest.
"@ | Set-Content -LiteralPath $promptPath -Encoding UTF8
        Write-Host 'blocked'
        Write-Host "Queue item $($item.id) is missing required replay/hash evidence. Prompt invalidated: $promptPath"
        Write-StepSummary -Step 'next fix prompt' -Status 'blocked' -LogPath $promptPath -Detail 'Queue item lacks the hardened evidence contract; run a fresh audit.'
        exit 1
    }
}
$reviewRules = if ($isReviewBacked) {
@'
- This is review-backed, not already-proven code evidence.
- First inspect the cited screenshots/logs/telemetry.
- Implement a change only if that review confirms a concrete defect.
- If review finds no concrete defect, do not edit; report that no fix was applied.
'@
} else {
@'
- This is evidence-backed code work.
- Implement the smallest fix for the queued finding.
'@
}

$fixSummary = @"
Selected $selectionLabel

Finding id: $($item.id)
Lane: $lane
Area: $($item.area)
Score: $($item.score)
Title: $($item.title)
Queue generated at: $queueGeneratedAt
Source run id: $queueSourceRunId
Publish/latest status: $queuePublishStatus

What will be reviewed/fixed:
$($item.recommendedAction)

Evidence:
$($item.evidence)

Evidence source:
$evidenceSource

Reproduction:
$reproduction
"@

$prompt = @"
# Hearthvale Improvement Pass

Use the latest audit evidence and handle only this queued item.

Finding id: $($item.id)
Lane: $lane
Area: $($item.area)
Score: $($item.score)
Title: $($item.title)
Queue generated at: $queueGeneratedAt
Source findings: $queueSourceFindings
Source run id: $queueSourceRunId
Publish/latest status: $queuePublishStatus
Confidence: $confidence
Affected system: $affectedSystem

Evidence:
$($item.evidence)

Evidence source:
$evidenceSource

Reproduction or command path:
$reproduction

Replay command:
$replayCommand

Build hash:
$buildHash

Snapshot path:
$snapshotPath

State digest:
$stateDigest

Verification gap:
$verificationGap

Recommended smallest action:
$($item.recommendedAction)

Before editing:
- Send a short user-facing message explaining exactly what is being fixed.
- Include the finding id, lane, area, score, evidence, and the intended smallest action.
- Then perform only that fix or review.

Rules:
- Confirm repo path and git status first.
- Preserve unrelated dirty files.
- Do not implement from weak or missing evidence.
$reviewRules
- Keep the fix scoped to this finding.
- Run targeted validation for the changed system.
- Run git diff --check before final.
- Final response must include exact lines starting with:
  - "Finding handled: $($item.id)"
  - "Evidence checked:"
  - "Outcome:" with exactly "fixed" or "no-code-change"
  - "Files changed:"
  - "Validation run:"
- If Outcome is "no-code-change" for an evidence-backed code fix, include "No code change reason:".
- Update _ai_audit_workflow/_internal/HEARTHVALE_AI_SIMULATION_AUDIT_REPORT.md only if post-fix evidence materially changes.
"@

$prompt | Set-Content -LiteralPath $promptPath -Encoding UTF8
$promptArchivePath = Copy-QueueArtifact -SourcePath $promptPath -ItemId $item.id -Kind 'prompt'
if ($MenuPreview) {
    Write-Host ''
    Write-Host 'Next fix/review preview'
    Write-Host ''
    Write-Host "Finding id: $($item.id)"
    Write-Host "Lane: $lane"
    Write-Host "Area: $($item.area)"
    Write-Host "Score: $($item.score)"
    Write-Host "Title: $($item.title)"
    Write-Host ''
    Write-Host "What will be reviewed/fixed: $($item.recommendedAction)"
    Write-Host ''
    Write-Host "Evidence: $($item.evidence)"
    Write-Host ''
    Write-Host "Prompt file: $promptPath"
    Write-Host "Archived prompt: $promptArchivePath"
} else {
    Write-Host 'pass'
    Write-Host ''
    Write-Host $fixSummary
    Write-Host ''
    Write-Host "Next improvement prompt: $promptPath"
    Write-Host "Archived improvement prompt: $promptArchivePath"
    Write-StepSummary -Step 'next fix prompt' -Status 'passed' -LogPath $promptArchivePath -Detail "Prepared finding $($item.id): $($item.title)"
}
if ($PrintPrompt) {
    Get-Content -Raw -LiteralPath $promptPath
}

if ($RunCodex) {
    $preStatus = @(Get-ShortGitStatus -RepoRoot $repoRoot)
    if ($preStatus.Count -gt 0 -and -not $AllowDirtyApply) {
        Write-Host 'Refusing to launch Codex because the repo is dirty.'
        Write-Host 'Review or preserve the current worktree, then rerun with -AllowDirtyApply only if applying into this dirty tree is intentional.'
        Write-StepSummary -Step 'codex fix execution' -Status 'blocked' -LogPath $queuePath -Detail "$($preStatus.Count) existing git status row(s)."
        exit 1
    }

    $promptText = Get-Content -Raw -LiteralPath $promptPath
    Write-Host ''
    Write-Host "Launching Codex to perform this $selectionLabel now..."
    Write-Host "Result summary will be written to: $resultPath"
    $global:LASTEXITCODE = 0
    $promptText | & codex exec --cd $repoRoot --output-last-message $resultPath -
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    if ($exitCode -ne 0) {
        Write-Host "Codex fix execution failed with exit code $exitCode."
        Write-StepSummary -Step 'codex fix execution' -Status 'failed' -LogPath $resultPath -Detail "codex exec exit code $exitCode"
        exit $exitCode
    }
    $resultSummary = Assert-ResultSummaryForQueueItem -Path $resultPath -Item $item -Lane $lane
    $resultArchivePath = Copy-QueueArtifact -SourcePath $resultPath -ItemId $item.id -Kind 'result'
    Write-Host "Archived result summary: $resultArchivePath"
    Invoke-DiffCheckOrThrow -RepoRoot $repoRoot
    $postStatus = @(Get-ShortGitStatus -RepoRoot $repoRoot)
    Set-QueueItemHandled -Queue $queue -ItemId $item.id -ResultPath $resultArchivePath -PromptArchivePath $promptArchivePath -PostGitStatus $postStatus -Outcome $resultSummary.outcome
    $executionDetail = "codex exec completed; outcome=$($resultSummary.outcome); Evidence checked: $($resultSummary.evidenceChecked); Files changed: $($resultSummary.filesChanged); Validation run: $($resultSummary.validationRun); git diff --check passed; $($postStatus.Count) git status row(s)."
    Write-StepSummary -Step 'codex fix execution' -Status 'passed' -LogPath $resultArchivePath -Detail $executionDetail
}
