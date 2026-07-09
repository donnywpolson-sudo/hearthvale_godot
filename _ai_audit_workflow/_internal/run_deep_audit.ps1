param(
    [ValidateSet('Light', 'Deep')]
    [string] $Tier = 'Light',
    [switch] $SkipVisualCapture,
    [switch] $SkipSimulation,
    [switch] $SkipSmokes
)

. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Assert-HearthvaleRepo
$config = Read-WorkflowConfig
$stateDir = Ensure-WorkflowState -Config $config
$startedAt = Get-Date
$runId = Get-Date -Format 'yyyy_MM_dd_HHmmss'
$visualCaptureStartedAt = $startedAt
$simulationStartedAt = $startedAt
$checks = New-Object System.Collections.Generic.List[object]
$findings = New-Object System.Collections.Generic.List[object]
$gaps = New-Object System.Collections.Generic.List[object]
$smokeResults = New-Object System.Collections.Generic.List[object]
$finalStatus = 'pass'
$failureMessage = ''
$initialStatus = @()
$initialStatusRecorded = $false

function Add-Check {
    param(
        [string] $Name,
        [string] $Status,
        [string] $Detail
    )
    $script:checks.Add([pscustomobject]@{
        name = $Name
        status = $Status
        detail = $Detail
    })
}

function Add-Finding {
    param(
        [string] $Id,
        [string] $Area,
        [int] $Score,
        [string] $Title,
        [string] $Classification,
        [string] $Evidence,
        [string] $Action,
        [bool] $EvidenceBacked,
        [bool] $EligibleForFix,
        [string] $Confidence = 'medium',
        [string] $AffectedSystem = '',
        [string] $EvidenceSource = '',
        [string] $Reproduction = '',
        [string] $VerificationGap = '',
        [string] $ReplayCommand = '',
        [string] $BuildHash = '',
        [string] $SnapshotPath = '',
        [string] $StateDigest = ''
    )
    $script:findings.Add([pscustomobject]@{
        id = $Id
        area = $Area
        score = $Score
        title = $Title
        classification = $Classification
        confidence = $Confidence
        affectedSystem = $AffectedSystem
        evidenceSource = $EvidenceSource
        evidence = $Evidence
        reproduction = $Reproduction
        verificationGap = $VerificationGap
        recommendedAction = $Action
        replayCommand = $ReplayCommand
        buildHash = $BuildHash
        snapshotPath = $SnapshotPath
        stateDigest = $StateDigest
        evidenceBacked = $EvidenceBacked
        eligibleForFix = $EligibleForFix
        status = 'open'
    })
}

function Add-Gap {
    param(
        [string] $Area,
        [string] $Detail,
        [string] $RecommendedEvidence
    )
    $script:gaps.Add([pscustomobject]@{
        area = $Area
        detail = $Detail
        recommendedEvidence = $RecommendedEvidence
    })
}

function Get-ScoreRows {
    param($Summary)
    $rows = New-Object System.Collections.Generic.List[object]
    $scorecard = Get-ObjectProperty -Object $Summary -Name 'scorecard'
    $categories = Get-ObjectProperty -Object $scorecard -Name 'categories'
    if ($null -eq $categories) {
        return @()
    }
    foreach ($prop in $categories.PSObject.Properties) {
        $value = $prop.Value
        $rows.Add([pscustomobject]@{
            key = $prop.Name
            label = [string](Get-ObjectProperty -Object $value -Name 'label' -Default $prop.Name)
            score = [int](Get-ObjectProperty -Object $value -Name 'score' -Default 0)
            confidence = [string](Get-ObjectProperty -Object $value -Name 'confidence' -Default '')
            basis = [string](Get-ObjectProperty -Object $value -Name 'basis' -Default '')
        })
    }
    return @($rows | Sort-Object score, label)
}

function Get-FirstIssueSample {
    param($Summary)
    $details = Get-ObjectProperty -Object $Summary -Name 'issue_group_details'
    if ($null -eq $details) {
        return $null
    }
    foreach ($prop in $details.PSObject.Properties) {
        $firstIssue = Get-ObjectProperty -Object $prop.Value -Name 'first_issue'
        if ($null -ne $firstIssue) {
            return $firstIssue
        }
    }
    return $null
}

function Get-CheckStatus {
    param(
        [Parameter(Mandatory)][string] $Name,
        [string] $Default = 'not recorded'
    )
    $row = $script:checks | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if ($null -eq $row) {
        return $Default
    }
    return [string]$row.status
}

function Write-AuditOutputs {
    param(
        [Parameter(Mandatory)][string] $RunId,
        [string] $Status,
        [string] $Failure,
        [object[]] $InitialGitStatus,
        [object[]] $FinalGitStatus,
        $Summary,
        $Performance,
        $VisualFolder,
        [object[]] $Scores
    )

    $reportPath = Join-Path $repoRoot $config.auditReport
    $findingsPath = Join-Path $stateDir 'findings.json'
    $statusPath = Join-Path $stateDir 'status.json'
    $summaryPath = Join-Path $repoRoot $config.simulationSummary
    $performancePath = Join-Path $repoRoot $config.performanceObservations

    $scorecard = Get-ObjectProperty -Object $Summary -Name 'scorecard'
    $summaryConfig = Get-ObjectProperty -Object $Summary -Name 'config'
    $trust = Get-ObjectProperty -Object $Summary -Name 'trust'
    $replayMetadata = Get-ObjectProperty -Object $Summary -Name 'replay_metadata'
    $overallScore = [int](Get-ObjectProperty -Object $scorecard -Name 'overall_score' -Default 0)
    $weakest = Get-ObjectProperty -Object $scorecard -Name 'weakest_category'
    $weakestLabel = [string](Get-ObjectProperty -Object $weakest -Name 'label' -Default '')
    $weakestScore = [int](Get-ObjectProperty -Object $weakest -Name 'score' -Default 0)
    $publishStatus = [string](Get-ObjectProperty -Object $trust -Name 'latest_publish_status' -Default 'unknown')
    $runStrength = [string](Get-ObjectProperty -Object $trust -Name 'run_strength' -Default 'unknown')
    $coverageScope = [string](Get-ObjectProperty -Object $trust -Name 'coverage_scope' -Default 'unknown')
    $implementationReady = Get-ObjectProperty -Object $trust -Name 'implementation_ready' -Default $null
    $findingStatus = [string](Get-ObjectProperty -Object $trust -Name 'finding_status' -Default 'unknown')
    $buildHash = [string](Get-ObjectProperty -Object $replayMetadata -Name 'build_hash' -Default '')

    $issueOccurrences = [int](Get-ObjectProperty -Object $Summary -Name 'issue_occurrences' -Default 0)
    $issueSamples = [int](Get-ObjectProperty -Object $Summary -Name 'issue_samples' -Default 0)
    if ($issueOccurrences -gt 0) {
        $sample = Get-FirstIssueSample -Summary $Summary
        $sampleReplay = [string](Get-ObjectProperty -Object $sample -Name 'replay_command' -Default '')
        $sampleReplayMeta = Get-ObjectProperty -Object $sample -Name 'replay'
        if ($sampleReplay.Trim().Length -eq 0) {
            $sampleReplay = [string](Get-ObjectProperty -Object $sampleReplayMeta -Name 'replay_command' -Default '')
        }
        $sampleBuildHash = [string](Get-ObjectProperty -Object $sampleReplayMeta -Name 'build_hash' -Default $buildHash)
        $sampleSnapshotPath = [string](Get-ObjectProperty -Object $sample -Name 'snapshot_path' -Default '')
        $sampleStateDigest = [string](Get-ObjectProperty -Object $sample -Name 'state_digest' -Default '')
        $sampleSummary = [string](Get-ObjectProperty -Object $sample -Name 'summary' -Default 'issue sample unavailable')
        Add-Finding -Id 'runtime-issues' -Area 'Runtime / gameplay bugs' -Score 0 -Title 'Simulation reported issue occurrences' -Classification 'proven' -Evidence "$issueOccurrences occurrences, $issueSamples samples in $($config.simulationSummary). First sample: $sampleSummary" -Action 'Inspect the issue sample, confirm replay/hash compatibility, and fix the smallest verified runtime/gameplay defect.' -EvidenceBacked $true -EligibleForFix $true -Confidence 'high' -AffectedSystem 'direct simulation / gameplay rule' -EvidenceSource "$($config.simulationSummary): issue_group_details first_issue" -Reproduction $sampleReplay -VerificationGap 'Generated simulation evidence still needs code/data or replay confirmation before changing protected behavior.' -ReplayCommand $sampleReplay -BuildHash $sampleBuildHash -SnapshotPath $sampleSnapshotPath -StateDigest $sampleStateDigest
    }

    foreach ($observation in @(Get-ObjectProperty -Object $Performance -Name 'observations' -Default @())) {
        if ([string](Get-ObjectProperty -Object $observation -Name 'status' -Default '') -eq 'over_budget') {
            $key = [string](Get-ObjectProperty -Object $observation -Name 'key' -Default 'performance')
            $value = Get-ObjectProperty -Object $observation -Name 'value'
            Add-Finding -Id "perf-$key" -Area 'Performance' -Score 70 -Title "Advisory over-budget performance sample: $key" -Classification 'partially proven' -Evidence "$key=$value in $($config.performanceObservations)" -Action 'Inspect before optimizing; do not broad-rewrite from advisory telemetry alone.' -EvidenceBacked $false -EligibleForFix $false -Confidence 'low' -AffectedSystem 'performance telemetry' -EvidenceSource $config.performanceObservations -Reproduction ".\_ai_audit_workflow\RUN_AUDIT.ps1 -Tier $Tier" -VerificationGap 'One advisory sample does not prove a stable hotspot; repeat with the same seed/profile before optimizing.'
        }
    }

    foreach ($score in $Scores) {
        if ($score.score -lt [int]$config.scoreThresholdForQueue) {
            $evidenceBacked = $false
            $eligible = $false
            $action = 'Add or review evidence before implementing changes.'
            if ($score.key -eq 'runtime_gameplay_bugs' -and $issueOccurrences -gt 0) {
                $evidenceBacked = $true
                $eligible = $true
                $action = 'Fix the concrete runtime/gameplay issues reported by the simulation.'
            }
            Add-Finding -Id "score-$($score.key)" -Area $score.label -Score $score.score -Title "Low score: $($score.label)" -Classification 'partially proven' -Evidence "Score $($score.score)/100; confidence $($score.confidence); basis: $($score.basis)" -Action $action -EvidenceBacked $evidenceBacked -EligibleForFix $eligible -Confidence ([string]$score.confidence) -AffectedSystem 'scorecard / report workflow' -EvidenceSource "$($config.simulationSummary): scorecard.categories.$($score.key)" -Reproduction ".\_ai_audit_workflow\RUN_AUDIT.ps1 -Tier $Tier" -VerificationGap 'Scorecard values are advisory and must be reconciled with screenshots, smokes, manual notes, or code/data before implementation.'
        }
    }

    if ($null -eq $VisualFolder) {
        Add-Gap -Area 'Visual review' -Detail 'No visual review folder was found for this audit.' -RecommendedEvidence 'Run visual screenshot capture.'
    }
    Add-Gap -Area 'Manual playtesting' -Detail 'Manual play-feel, comprehension, and grind feel are not proven by automation.' -RecommendedEvidence 'Run a bounded manual playtest pass.'
    Add-Gap -Area 'Audio' -Detail 'Audio timing, mixing, bus routing, cue coverage, and pause behavior are not proven by this workflow.' -RecommendedEvidence 'Run a bounded audio review pass.'
    Add-Gap -Area 'Export/platform parity' -Detail 'Export and non-local platform behavior are not proven by this workflow.' -RecommendedEvidence 'Run an export/platform smoke when release confidence matters.'

    if ($Status -eq 'pass' -and ($gaps.Count -gt 0 -or ($Scores | Where-Object { $_.score -lt [int]$config.scoreThresholdForQueue }).Count -gt 0)) {
        $Status = 'pass with gaps'
    }

    $visualReviewPath = $null
    if ($null -ne $VisualFolder) {
        $visualReviewPath = $VisualFolder.FullName
    }
    $checkRows = @($checks.ToArray())
    $findingRows = @($findings.ToArray())
    $gapRows = @($gaps.ToArray())
    $smokeRows = @($smokeResults.ToArray())

    $state = [pscustomobject]@{
        generatedAt = (Get-Date).ToString('s')
        runId = $RunId
        tier = $Tier
        status = $Status
        failure = $Failure
        repoRoot = $repoRoot
        canonicalFiles = [pscustomobject]@{
            launcher = $config.launcher
            auditSpec = $config.auditSpec
            auditReport = $config.auditReport
        }
        checks = $checkRows
        scores = @($Scores)
        findings = $findingRows
        gaps = $gapRows
        smokeResults = $smokeRows
        artifacts = [pscustomobject]@{
            summary = $config.simulationSummary
            performanceObservations = $config.performanceObservations
            playtestLog = $config.playtestLog
            visualReview = $visualReviewPath
            publishStatus = $publishStatus
            runStrength = $runStrength
            coverageScope = $coverageScope
            implementationReady = $implementationReady
            findingStatus = $findingStatus
            artifactFreshAfter = $startedAt.ToString('s')
        }
    }
    ConvertTo-JsonFile -Value $state -Path $findingsPath
    ConvertTo-JsonFile -Value ([pscustomobject]@{
        generatedAt = (Get-Date).ToString('s')
        runId = $RunId
        status = $Status
        tier = $Tier
        failure = $Failure
        report = $reportPath
        findings = $findingsPath
    }) -Path $statusPath

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Hearthvale AI Simulation Audit Report')
    $lines.Add('')
    $lines.Add("Report date: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) local time.")
    $lines.Add('')
    $lines.Add(('Workflow status: `{0}`.' -f $Status))
    if ($Failure.Trim().Length -gt 0) {
        $lines.Add('')
        $lines.Add("Failure: $Failure")
    }
    $lines.Add('')
    $lines.Add('This report was generated by `_ai_audit_workflow/RUN_AUDIT.ps1`. The durable audit spec remains `_ai_audit_workflow/_internal/HEARTHVALE_AI_SIMULATION_AUDIT.md`; this file is the run-specific evidence packet.')
    $lines.Add('')
    $lines.Add('## Evidence Used')
    $lines.Add('')
    $visualFolderText = if ($null -ne $VisualFolder) { $VisualFolder.FullName } else { 'none' }
    $lines.Add(('- Audit run id: `{0}`' -f $RunId))
    $lines.Add(('- Repository path: `{0}`' -f $repoRoot))
    $lines.Add(('- Launcher: `{0}`' -f $config.launcher))
    $lines.Add(('- Audit spec: `{0}`' -f $config.auditSpec))
    $lines.Add(('- Simulation summary: `{0}`' -f $config.simulationSummary))
    $lines.Add(('- Performance observations: `{0}`' -f $config.performanceObservations))
    $lines.Add(('- Visual review folder: `{0}`' -f $visualFolderText))
    $lines.Add(('- Publish/latest status: `{0}`' -f $publishStatus))
    $lines.Add(('- Run strength: `{0}`; coverage scope: `{1}`; implementation ready: `{2}`; finding status: `{3}`' -f $runStrength, $coverageScope, $implementationReady, $findingStatus))
    $lines.Add(('- Machine-readable findings: `{0}\findings.json`' -f $config.currentDir))
    $lines.Add('')
    $lines.Add('## Current Repo State')
    $lines.Add('')
    $lines.Add('Initial `git status --short`:')
    $lines.Add('')
    $lines.Add('```text')
    if ($InitialGitStatus.Count -eq 0) { $lines.Add('(clean)') } else { foreach ($line in $InitialGitStatus) { $lines.Add($line) } }
    $lines.Add('```')
    $lines.Add('')
    $lines.Add('Final `git status --short`:')
    $lines.Add('')
    $lines.Add('```text')
    if ($FinalGitStatus.Count -eq 0) { $lines.Add('(clean)') } else { foreach ($line in $FinalGitStatus) { $lines.Add($line) } }
    $lines.Add('```')
    $lines.Add('')
    $lines.Add('## Minimum Coverage Bundle Status')
    $lines.Add('')
    $lines.Add('| Bundle item | Status | Detail |')
    $lines.Add('| --- | --- | --- |')
    $lines.Add("| Visible screenshot capture | $(Get-CheckStatus -Name 'visual_capture') | $visualFolderText |")
    $lines.Add("| Strategy simulation | $(Get-CheckStatus -Name 'simulation') | $($config.simulationSummary); publish/latest status $publishStatus |")
    $lines.Add("| Focused smoke matrix | $(Get-CheckStatus -Name 'focused_smoke_matrix') | $($smokeRows.Count)/$($config.smokes.Count) smoke result row(s) recorded |")
    $lines.Add("| Diff hygiene | $(Get-CheckStatus -Name 'diff_hygiene') | git diff --check |")
    $lines.Add('')
    $lines.Add('## Coverage Classification Summary')
    $lines.Add('')
    $lines.Add('| Area | Classification | Evidence | Remaining gap |')
    $lines.Add('| --- | --- | --- | --- |')
    $lines.Add('| Launcher | proven | Workflow preflight and configured launcher path were exercised before report write. | Does not prove gameplay quality. |')
    $lines.Add("| Direct simulation | $(if ((Get-CheckStatus -Name 'simulation') -eq 'passed') { 'proven' } else { 'not proven' }) | $($config.simulationSummary) | Generated findings still require replay/hash review before code changes. |")
    $lines.Add('| Scenario probes | partially proven | Scenario-probe status is carried by the simulation summary when present. | Report-only diagnostics; focused smokes remain pass/fail authority. |')
    $lines.Add("| Focused smokes | $(if ((Get-CheckStatus -Name 'focused_smoke_matrix') -eq 'passed') { 'proven' } else { 'not proven' }) | $($smokeRows.Count)/$($config.smokes.Count) smoke result row(s). | Does not prove long-run balance or subjective quality. |")
    $lines.Add("| Visual screenshots | $(if ($null -ne $VisualFolder) { 'proven' } else { 'not proven' }) | $visualFolderText | Requires human/AI review for concrete visual defects. |")
    $lines.Add('| Manual playtesting | not proven | No manual playtest notes are recorded by this workflow. | Fun, pacing, comprehension, and grind feel remain manual. |')
    $lines.Add('| Audio | not proven | No audio review evidence is recorded by this workflow. | Timing, mix, routing, and cue coverage need dedicated evidence. |')
    $lines.Add('| Export/platform parity | not proven | No export/platform smoke evidence is recorded by this workflow. | Exported build behavior remains unproven. |')
    $lines.Add('')
    $lines.Add('## Run Summary')
    $lines.Add('')
    $lines.Add(('- Tier: `{0}`' -f $Tier))
    $lines.Add(('- Runs: `{0}`; steps: `{1}`; seed: `{2}`; scenario/profile: `{3}/{4}`; trace: `{5}`; probes: `{6}`' -f (Get-ObjectProperty -Object $summaryConfig -Name 'runs' -Default 'unknown'), (Get-ObjectProperty -Object $summaryConfig -Name 'steps' -Default 'unknown'), (Get-ObjectProperty -Object $summaryConfig -Name 'seed' -Default 'unknown'), (Get-ObjectProperty -Object $summaryConfig -Name 'scenario' -Default 'unknown'), (Get-ObjectProperty -Object $summaryConfig -Name 'balance_profile' -Default 'unknown'), (Get-ObjectProperty -Object $summaryConfig -Name 'trace' -Default 'unknown'), (Get-ObjectProperty -Object $summaryConfig -Name 'scenario_probes' -Default 'unknown')))
    $lines.Add(('- Issue counts: `{0}` occurrence(s), `{1}` sample(s).' -f $issueOccurrences, $issueSamples))
    $lines.Add(('- Publish/latest status: `{0}`.' -f $publishStatus))
    $lines.Add(('- Output paths: summary `{0}`, performance `{1}`, visual review `{2}`.' -f $config.simulationSummary, $config.performanceObservations, $visualFolderText))
    $lines.Add('')
    $lines.Add('## Game Section Rankings')
    $lines.Add('')
    $lines.Add('| Section | Score | Confidence | Basis |')
    $lines.Add('| --- | ---: | --- | --- |')
    foreach ($score in $Scores) {
        $basis = ([string]$score.basis).Replace('|', '/')
        $lines.Add("| $($score.label) | $($score.score) | $($score.confidence) | $basis |")
    }
    $lines.Add('')
    $lines.Add(('Overall score: `{0}`.' -f $overallScore))
    if ($weakestLabel.Trim().Length -gt 0) {
        $lines.Add(('Weakest category: `{0}` at `{1}`.' -f $weakestLabel, $weakestScore))
    }
    $lines.Add('')
    $lines.Add('## Checks')
    $lines.Add('')
    $lines.Add('| Check | Status | Detail |')
    $lines.Add('| --- | --- | --- |')
    foreach ($check in $checks) {
        $lines.Add("| $($check.name) | $($check.status) | $(([string]$check.detail).Replace('|', '/')) |")
    }
    $lines.Add('')
    $lines.Add('## Findings')
    $lines.Add('')
    if ($findings.Count -eq 0) {
        $lines.Add('No implementation-driving findings were produced.')
    } else {
        foreach ($finding in $findings) {
            $lines.Add("### $($finding.id). $($finding.title)")
            $lines.Add('')
            $lines.Add("- Area: $($finding.area)")
            $lines.Add("- Score: $($finding.score)")
            $lines.Add("- Classification: $($finding.classification)")
            $lines.Add("- Confidence: $($finding.confidence)")
            $lines.Add("- Affected system: $($finding.affectedSystem)")
            $lines.Add("- Evidence backed: $($finding.evidenceBacked)")
            $lines.Add("- Eligible for fix queue: $($finding.eligibleForFix)")
            $lines.Add("- Evidence source: $($finding.evidenceSource)")
            $lines.Add("- Evidence: $($finding.evidence)")
            if ([string]$finding.replayCommand -ne '') { $lines.Add("- Replay command: $($finding.replayCommand)") }
            if ([string]$finding.buildHash -ne '') { $lines.Add("- Build hash: $($finding.buildHash)") }
            if ([string]$finding.snapshotPath -ne '') { $lines.Add("- Snapshot path: $($finding.snapshotPath)") }
            if ([string]$finding.stateDigest -ne '') { $lines.Add("- State digest: $($finding.stateDigest)") }
            $lines.Add("- Reproduction or command path: $($finding.reproduction)")
            $lines.Add("- Verification gap: $($finding.verificationGap)")
            $lines.Add("- Recommended smallest next action: $($finding.recommendedAction)")
            $lines.Add('')
        }
    }
    $lines.Add('## Recommended Improvements')
    $lines.Add('')
    $eligibleFindings = @($findings | Where-Object { $_.eligibleForFix -eq $true })
    if ($eligibleFindings.Count -eq 0) {
        $lines.Add('- No evidence-backed code fix is queued from this report. Use residual gaps for manual evidence planning.')
    } else {
        foreach ($finding in $eligibleFindings) {
            $lines.Add("- $($finding.id): $($finding.recommendedAction)")
        }
    }
    $lines.Add('')
    $lines.Add('## Residual Gaps')
    $lines.Add('')
    foreach ($gap in $gaps) {
        $lines.Add("- $($gap.area): $($gap.detail) Recommended evidence: $($gap.recommendedEvidence)")
    }
    $lines.Add('')
    $lines.Add('## Validation')
    $lines.Add('')
    $lines.Add('Exact command family run by this workflow:')
    $lines.Add('')
    $lines.Add('```powershell')
    $lines.Add(".\_ai_audit_workflow\RUN_AUDIT.ps1 -Tier $Tier")
    $lines.Add('```')
    $lines.Add('')
    $lines.Add("Final line: $Status")
    $lines.Add('')
    $lines -join "`n" | Set-Content -LiteralPath $reportPath -Encoding UTF8

    Write-Host $Status
    return $Status
}

Push-Location $repoRoot
try {
    $initialStatus = @(Get-ShortGitStatus -RepoRoot $repoRoot)
    $initialStatusRecorded = $true
    Add-Check -Name 'repo_status_initial' -Status 'recorded' -Detail "$($initialStatus.Count) status rows"

    if (-not (Test-Path -LiteralPath $config.godotExe)) {
        throw "Godot executable was not found: $($config.godotExe)"
    }

    $tierConfig = $config.tiers.$Tier
    if ($null -eq $tierConfig) {
        throw "No tier config found for $Tier."
    }
    if ([int]$tierConfig.timeoutSeconds -le 0 -and -not $SkipSimulation) {
        throw "$Tier audit timeoutSeconds must be a positive stop budget. Update config.json or run a narrower explicit command."
    }

    Invoke-RepoCommand -Label 'recommender smoke preflight' -Quiet -Command {
        & $config.godotExe --headless --path . --script $config.recommendSmokeScript --log-file $config.recommendSmokeLog
    }
    Add-Check -Name 'recommender_smoke_preflight' -Status 'passed' -Detail $config.recommendSmokeLog
    Write-StepSummary -Step 'recommender smoke preflight' -Status 'passed' -LogPath $config.recommendSmokeLog -Detail $config.recommendSmokeScript

    if ($SkipVisualCapture) {
        Add-Check -Name 'visual_capture' -Status 'skipped' -Detail 'Skipped by parameter.'
        Write-StepSummary -Step 'visual screenshot capture' -Status 'skipped' -LogPath $config.visualCaptureLog -Detail 'Skipped by parameter.'
    } else {
        $visualCaptureStartedAt = Get-Date
        Invoke-RepoCommand -Label 'visual screenshot capture' -Command {
            $visualArgs = @('--path', '.', '--script', $config.visualCaptureScript, '--log-file', $config.visualCaptureLog)
            $visualConsoleLog = Join-Path $repoRoot '.godot_logs\visual_review_capture.console.log'
            $visualConsoleErrorLog = Join-Path $repoRoot '.godot_logs\visual_review_capture.console.err.log'
            $visualConsoleDir = Split-Path -Parent $visualConsoleLog
            if (-not (Test-Path -LiteralPath $visualConsoleDir)) {
                New-Item -ItemType Directory -Path $visualConsoleDir | Out-Null
            }
            $visualProcess = Start-Process -FilePath $config.godotExe -ArgumentList $visualArgs -WorkingDirectory $repoRoot -Wait -PassThru -RedirectStandardOutput $visualConsoleLog -RedirectStandardError $visualConsoleErrorLog
            $global:LASTEXITCODE = $visualProcess.ExitCode
        }
        $visualFolderForSummary = Get-LatestVisualReviewFolder -RepoRoot $repoRoot -EarliestWriteTime $visualCaptureStartedAt
        $visualCompleteness = Test-VisualReviewCompleteness -Folder $visualFolderForSummary -Config $config
        if (-not [bool]$visualCompleteness.passed) {
            throw "Visual capture did not produce a complete fresh screenshot packet. $($visualCompleteness.detail)"
        }
        Add-Check -Name 'visual_capture' -Status 'passed' -Detail $visualCompleteness.detail
        $visualDetail = "$($visualFolderForSummary.FullName); $($visualCompleteness.detail)"
        Write-StepSummary -Step 'visual screenshot capture' -Status 'passed' -LogPath $config.visualCaptureLog -Detail $visualDetail
    }

    if ($SkipSimulation) {
        Add-Check -Name 'simulation' -Status 'skipped' -Detail 'Skipped by parameter.'
        Write-StepSummary -Step "$Tier simulation" -Status 'skipped' -LogPath $config.playtestLog -Detail 'Skipped by parameter.'
    } else {
        $simulationStartedAt = Get-Date
        $oldNoOpen = $env:HV_NO_OPEN
        $oldNoPause = $env:HV_NO_PAUSE
        $env:HV_NO_OPEN = '1'
        $env:HV_NO_PAUSE = '1'
        try {
            Invoke-RepoCommand -Label "$Tier simulation" -Command {
                & (Join-Path $repoRoot $config.launcher) $tierConfig.runs $tierConfig.steps $tierConfig.seed $tierConfig.scenario $tierConfig.trace $tierConfig.profile $tierConfig.timeoutSeconds $tierConfig.scenarioProbes
            }
        } finally {
            $env:HV_NO_OPEN = $oldNoOpen
            $env:HV_NO_PAUSE = $oldNoPause
        }
        Add-Check -Name 'simulation' -Status 'passed' -Detail "$($tierConfig.runs) runs, $($tierConfig.steps) steps, $($tierConfig.profile) profile"
        $simulationSummaryPath = Join-Path $repoRoot $config.simulationSummary
        $performancePath = Join-Path $repoRoot $config.performanceObservations
        $simulationSummary = Read-FreshJsonFileOrNull -Path $simulationSummaryPath -EarliestWriteTime $simulationStartedAt
        $performanceCheck = Read-FreshJsonFileOrNull -Path $performancePath -EarliestWriteTime $simulationStartedAt
        if ($null -eq $simulationSummary) {
            throw "Simulation completed but did not write a fresh summary.json for run $runId."
        }
        if ($null -eq $performanceCheck) {
            throw "Simulation completed but did not write a fresh performance_observations.json for run $runId."
        }
        $simIssues = [int](Get-ObjectProperty -Object $simulationSummary -Name 'issue_occurrences' -Default 0)
        $simSamples = [int](Get-ObjectProperty -Object $simulationSummary -Name 'issue_samples' -Default 0)
        Write-StepSummary -Step "$Tier simulation" -Status 'passed' -LogPath $config.playtestLog -Detail "$($tierConfig.runs) runs, $($tierConfig.steps) steps, $($tierConfig.profile) profile, issues=$simIssues, samples=$simSamples"
    }

    if ($SkipSmokes) {
        Add-Check -Name 'focused_smoke_matrix' -Status 'skipped' -Detail 'Skipped by parameter.'
        Write-StepSummary -Step 'focused smoke matrix' -Status 'skipped' -Detail 'Skipped by parameter.'
    } else {
        foreach ($smoke in $config.smokes) {
            $logPath = ".godot_logs\$($smoke.name).log"
            Invoke-RepoCommand -Label "smoke $($smoke.name)" -Quiet -Command {
                & $config.godotExe --headless --path . --script $smoke.script --log-file $logPath
            }
            $logText = if (Test-Path -LiteralPath $logPath) { Get-Content -Raw -LiteralPath $logPath } else { '' }
            $passedMessage = $logText.Contains([string]$smoke.expected)
            if (-not $passedMessage) {
                throw "Smoke $($smoke.name) exited 0 but expected pass message was not found: $($smoke.expected)"
            }
            $smokeResults.Add([pscustomobject]@{
                name = $smoke.name
                status = 'passed'
                log = $logPath
                expected = $smoke.expected
            })
        }
        Add-Check -Name 'focused_smoke_matrix' -Status 'passed' -Detail "$($smokeResults.Count)/$($config.smokes.Count) smokes passed"
        Write-StepSummary -Step 'focused smoke matrix' -Status 'passed' -Detail "$($smokeResults.Count)/$($config.smokes.Count) smokes passed; logs are under .godot_logs\<smoke>.log"
    }

    Invoke-RepoCommand -Label 'git diff --check' -Command {
        git -c core.autocrlf=false diff --check
    }
    Add-Check -Name 'diff_hygiene' -Status 'passed' -Detail 'git diff --check exited 0'
    Write-StepSummary -Step 'git diff --check' -Status 'passed' -Detail 'git diff --check exited 0'

    $summary = Read-FreshJsonFileOrNull -Path (Join-Path $repoRoot $config.simulationSummary) -EarliestWriteTime $simulationStartedAt
    $performance = Read-FreshJsonFileOrNull -Path (Join-Path $repoRoot $config.performanceObservations) -EarliestWriteTime $simulationStartedAt
    $visualFolder = Get-LatestVisualReviewFolder -RepoRoot $repoRoot -EarliestWriteTime $visualCaptureStartedAt
    $scores = @(Get-ScoreRows -Summary $summary)
    $finalGitStatus = @(Get-ShortGitStatus -RepoRoot $repoRoot)

    $writtenStatus = Write-AuditOutputs -RunId $runId -Status $finalStatus -Failure $failureMessage -InitialGitStatus $initialStatus -FinalGitStatus $finalGitStatus -Summary $summary -Performance $performance -VisualFolder $visualFolder -Scores $scores
    Write-StepSummary -Step 'audit report write' -Status $writtenStatus -LogPath $config.auditReport -Detail "$($findings.Count) finding rows, $($gaps.Count) residual gap rows"
} catch {
    $finalStatus = 'fail'
    $failureMessage = $_.Exception.Message
    Add-Check -Name 'workflow_failure' -Status 'failed' -Detail $failureMessage
    $summary = Read-FreshJsonFileOrNull -Path (Join-Path $repoRoot $config.simulationSummary) -EarliestWriteTime $simulationStartedAt
    $performance = Read-FreshJsonFileOrNull -Path (Join-Path $repoRoot $config.performanceObservations) -EarliestWriteTime $simulationStartedAt
    $visualFolder = Get-LatestVisualReviewFolder -RepoRoot $repoRoot -EarliestWriteTime $visualCaptureStartedAt
    $scores = @(Get-ScoreRows -Summary $summary)
    $finalGitStatus = @(Get-ShortGitStatus -RepoRoot $repoRoot)
    $initialStatusForReport = if ($initialStatusRecorded) { $initialStatus } else { @('not recorded before workflow failure') }
    $writtenStatus = Write-AuditOutputs -RunId $runId -Status $finalStatus -Failure $failureMessage -InitialGitStatus $initialStatusForReport -FinalGitStatus $finalGitStatus -Summary $summary -Performance $performance -VisualFolder $visualFolder -Scores $scores
    Write-StepSummary -Step 'audit report write' -Status $writtenStatus -LogPath $config.auditReport -Detail $failureMessage
    exit 1
} finally {
    Pop-Location
}
