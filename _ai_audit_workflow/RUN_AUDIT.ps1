param(
    [ValidateSet('Light', 'Deep')]
    [string] $Tier = 'Light',
    [switch] $NextFix,
    [switch] $SkipAudit,
    [switch] $AllowDirtyApply
)

$ErrorActionPreference = 'Stop'
$internal = Join-Path $PSScriptRoot '_internal'
$preflightIssues = New-Object System.Collections.Generic.List[object]
$transcriptStarted = $false
$transcriptPath = $null
$transcriptArchivePath = $null

function Pause-IfInteractive {
    param([bool] $Interactive)
    if ($Interactive) {
        Write-Host ''
        Read-Host 'Press Enter to close'
    }
}

function Initialize-RunLog {
    $stateDir = Join-Path $internal 'current'
    if (-not (Test-Path -LiteralPath $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir | Out-Null
    }
    $archiveDir = Join-Path $stateDir 'run_logs'
    if (-not (Test-Path -LiteralPath $archiveDir)) {
        New-Item -ItemType Directory -Path $archiveDir | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:transcriptPath = Join-Path $stateDir 'latest_run.log'
    $script:transcriptArchivePath = Join-Path $archiveDir "run_$timestamp.log"

    "Hearthvale AI Audit Workflow log started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Set-Content -LiteralPath $script:transcriptPath -Encoding UTF8
    "Archive copy: $script:transcriptArchivePath" | Add-Content -LiteralPath $script:transcriptPath -Encoding UTF8

    Start-Transcript -Path $script:transcriptPath -Append | Out-Null
    $script:transcriptStarted = $true
    Write-Host "Full run log: $script:transcriptPath"
    Write-Host "Archived run log: $script:transcriptArchivePath"
}

function Stop-RunLog {
    if ($script:transcriptStarted) {
        try {
            Stop-Transcript | Out-Null
        } catch {
        }
        $script:transcriptStarted = $false
    }
    if ($script:transcriptPath -and $script:transcriptArchivePath -and (Test-Path -LiteralPath $script:transcriptPath)) {
        Copy-Item -LiteralPath $script:transcriptPath -Destination $script:transcriptArchivePath -Force
    }
}

function Write-RootStepSummary {
    param(
        [Parameter(Mandatory)][string] $Step,
        [Parameter(Mandatory)][string] $Status,
        [string] $Detail = ''
    )
    Write-Host ''
    Write-Host "STEP SUMMARY: $Step"
    Write-Host "  Status: $Status"
    if ($Detail.Trim().Length -gt 0) {
        Write-Host "  Detail: $Detail"
    }
    Write-Host ''
}

function Show-Menu {
    Write-Host ''
    Write-Host 'Hearthvale AI Audit Workflow'
    Write-Host ''
    Write-Host '1. Light audit'
    Write-Host '2. Deep audit'
    Write-Host '3. Cancel'
    Write-Host ''
    return (Read-Host 'Choose 1-3')
}

$interactive = $PSBoundParameters.Count -eq 0
Initialize-RunLog

function Get-SafeLastExitCode {
    $lastExit = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
    if ($null -eq $lastExit -or $null -eq $lastExit.Value) {
        return 0
    }
    return [int]$lastExit.Value
}

function Add-PreflightIssue {
    param(
        [string] $Title,
        [string] $Problem,
        [string] $Fix
    )
    $script:preflightIssues.Add([pscustomobject]@{
        title = $Title
        problem = $Problem
        fix = $Fix
    })
}

function Show-PreflightIssues {
    Write-Host ''
    Write-Host 'Preflight failed. No audit, simulation, smoke, or apply step was run.'
    Write-Host 'A launcher transcript may still have been written under _ai_audit_workflow\_internal\current.'
    Write-Host ''
    foreach ($issue in $script:preflightIssues) {
        Write-Host "Problem: $($issue.title)"
        Write-Host "What happened: $($issue.problem)"
        Write-Host "How to fix it: $($issue.fix)"
        Write-Host ''
    }
}

function Get-RepoRootOrNull {
    try {
        return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    } catch {
        Add-PreflightIssue -Title 'Cannot find project folder' -Problem "The workflow folder is not inside the Hearthvale project folder." -Fix 'Move _ai_audit_workflow back under C:\Users\donny\Desktop\hearthvale_godot, then run RUN_AUDIT.ps1 again.'
        return $null
    }
}

function Read-ConfigOrNull {
    $configPath = Join-Path $internal 'config.json'
    if (-not (Test-Path -LiteralPath $configPath)) {
        Add-PreflightIssue -Title 'Missing workflow config' -Problem "The file was not found: $configPath" -Fix 'Restore _ai_audit_workflow/_internal/config.json from the project files, then run the workflow again.'
        return $null
    }
    try {
        return Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
    } catch {
        Add-PreflightIssue -Title 'Broken workflow config' -Problem "config.json could not be parsed as JSON. $($_.Exception.Message)" -Fix 'Open _ai_audit_workflow/_internal/config.json, fix the JSON syntax, then run the workflow again.'
        return $null
    }
}

function Test-AuditQueue {
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] $Config
    )
    $queuePath = Join-Path (Join-Path $RepoRoot $Config.currentDir) 'improvement_queue.json'
    if (-not (Test-Path -LiteralPath $queuePath)) {
        Add-PreflightIssue -Title 'No audit queue yet' -Problem "The next-fix queue does not exist: $queuePath" -Fix 'Run a Light or Deep audit first, then use the post-audit prompt handling.'
        return
    }
    try {
        $queue = Get-Content -Raw -LiteralPath $queuePath | ConvertFrom-Json
        $queuedItems = @($queue.items | Where-Object { $_.status -eq 'queued' })
        if ($queuedItems.Count -eq 0) {
            Add-PreflightIssue -Title 'No queued fix or review prompt' -Problem 'The latest audit queue exists, but it does not contain a queued evidence-backed fix or review-backed polish prompt.' -Fix 'Run a fresh Light or Deep audit, or review the audit report for residual gaps that need manual evidence.'
        }
    } catch {
        Add-PreflightIssue -Title 'Broken audit queue' -Problem "The improvement queue could not be parsed: $queuePath. $($_.Exception.Message)" -Fix 'Run a fresh Light or Deep audit to rebuild the queue.'
    }
}

function Test-RepoCleanForApply {
    param([Parameter(Mandatory)] [string] $RepoRoot)
    Push-Location $RepoRoot
    try {
        $status = @(git status --short)
        if ($status.Count -gt 0) {
            Add-PreflightIssue -Title 'Repo is dirty before applying a fix' -Problem "The apply-now path can edit files, but git status already has $($status.Count) row(s)." -Fix 'Review/preserve the current worktree first, or rerun with -AllowDirtyApply if applying into the dirty tree is intentional.'
        }
    } finally {
        Pop-Location
    }
}

function Test-AuditTierStopBudget {
    param(
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)][string] $AuditTier
    )
    $tierConfig = $Config.tiers.$AuditTier
    if ($null -eq $tierConfig) {
        Add-PreflightIssue -Title 'Missing audit tier config' -Problem "No config.json tier entry exists for $AuditTier." -Fix 'Restore or repair _ai_audit_workflow/_internal/config.json before running the audit.'
        return
    }
    if ([int]$tierConfig.timeoutSeconds -le 0) {
        Add-PreflightIssue -Title 'Audit stop budget is disabled' -Problem "$AuditTier timeoutSeconds is $($tierConfig.timeoutSeconds), which would allow an uncapped simulation run." -Fix 'Set a positive timeoutSeconds in _ai_audit_workflow/_internal/config.json, or run a narrower explicit command outside this workflow.'
    }
}

function Invoke-Preflight {
    param(
        [bool] $NeedsGodot,
        [bool] $NeedsCodex,
        [bool] $NeedsAuditQueue,
        [bool] $NeedsCleanApply = $false,
        [bool] $AllowDirtyApply = $false,
        [string] $AuditTier = ''
    )
    $script:preflightIssues.Clear()

    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Add-PreflightIssue -Title 'PowerShell is too old' -Problem "This workflow needs Windows PowerShell 5 or newer. Current version: $($PSVersionTable.PSVersion)" -Fix 'Run it from normal Windows PowerShell on Windows 10/11, or install a newer PowerShell.'
    }

    $repoRoot = Get-RepoRootOrNull
    $config = Read-ConfigOrNull

    if ($null -ne $repoRoot) {
        $projectFile = Join-Path $repoRoot 'project.godot'
        if (-not (Test-Path -LiteralPath $projectFile)) {
            Add-PreflightIssue -Title 'Wrong folder' -Problem "project.godot was not found in $repoRoot" -Fix 'Run RUN_AUDIT.ps1 from C:\Users\donny\Desktop\hearthvale_godot\_ai_audit_workflow.'
        }
    }

    if ($NeedsGodot -and $null -ne $config) {
        if (-not (Test-Path -LiteralPath $config.godotExe)) {
            Add-PreflightIssue -Title 'Godot was not found' -Problem "The configured Godot executable does not exist: $($config.godotExe)" -Fix 'Install Godot 4.7 stable at that path, or update godotExe in _ai_audit_workflow/_internal/config.json.'
        }
        if ($AuditTier.Trim().Length -gt 0) {
            Test-AuditTierStopBudget -Config $config -AuditTier $AuditTier
        }
    }

    if ($NeedsCodex) {
        $codex = Get-Command codex -ErrorAction SilentlyContinue
        if ($null -eq $codex) {
            Add-PreflightIssue -Title 'Codex CLI was not found' -Problem 'The command `codex` is not available in this terminal path.' -Fix 'Open Codex once normally or install/fix the Codex CLI, then reopen this launcher.'
        }
    }

    if ($NeedsAuditQueue -and $null -ne $repoRoot -and $null -ne $config) {
        Test-AuditQueue -RepoRoot $repoRoot -Config $config
    }

    if ($NeedsCleanApply -and -not $AllowDirtyApply -and $null -ne $repoRoot) {
        Test-RepoCleanForApply -RepoRoot $repoRoot
    }

    if ($script:preflightIssues.Count -gt 0) {
        Show-PreflightIssues
        return $false
    }
    return $true
}

function Invoke-PostAuditFixMenu {
    param([bool] $Interactive)
    if (-not $Interactive) {
        return 0
    }

    $repoRoot = Get-RepoRootOrNull
    $config = Read-ConfigOrNull
    if ($null -eq $repoRoot -or $null -eq $config) {
        Write-RootStepSummary -Step 'post-audit fix menu' -Status 'skipped' -Detail 'Could not read repo/config after audit.'
        return 0
    }

    $queuePath = Join-Path (Join-Path $repoRoot $config.currentDir) 'improvement_queue.json'
    if (-not (Test-Path -LiteralPath $queuePath)) {
        Write-Host ''
        Write-Host 'No improvement queue was produced.'
        Write-Host 'Check the latest run log and audit report for the failed step.'
        Write-RootStepSummary -Step 'post-audit fix menu' -Status 'skipped' -Detail "Missing queue: $queuePath"
        return 0
    }

    try {
        $queue = Get-Content -Raw -LiteralPath $queuePath | ConvertFrom-Json
        $items = @($queue.items | Where-Object { $_.status -eq 'queued' })
    } catch {
        Write-Host ''
        Write-Host "The improvement queue could not be read: $queuePath"
        Write-Host 'Run a fresh audit to rebuild it.'
        Write-RootStepSummary -Step 'post-audit fix menu' -Status 'failed' -Detail $_.Exception.Message
        return 1
    }

    if ($items.Count -eq 0) {
        Write-Host ''
        Write-Host 'No evidence-backed fixes or review-backed polish prompts were found by this audit.'
        Write-Host 'The audit still wrote the report and residual gaps for review.'
        Write-RootStepSummary -Step 'post-audit fix menu' -Status 'pass with gaps' -Detail '0 queued fix/review prompt(s).'
        return 0
    }

    Write-Host ''
    $codeCount = @($items | Where-Object { $_.lane -eq 'evidence-backed code fix' }).Count
    $reviewCount = @($items | Where-Object { $_.lane -eq 'review-backed polish fix' }).Count
    Write-Host "Queued fixes/prompts found: $($items.Count) ($codeCount evidence-backed, $reviewCount review-backed)"
    foreach ($item in @($items | Select-Object -First 5)) {
        $lane = if ($null -ne $item.PSObject.Properties['lane']) { $item.lane } else { 'evidence-backed code fix' }
        Write-Host "- $($item.id): $($item.title) [$lane, $($item.area), score $($item.score)]"
    }
    if ($items.Count -gt 5) {
        Write-Host "- ...and $($items.Count - 5) more"
    }
    Write-Host ''
    Write-Host '1. Apply next fix/review now'
    Write-Host '2. Show next fix/review prompt only'
    Write-Host '3. Close'
    Write-Host ''
    $fixChoice = Read-Host 'Choose 1-3'

    switch ($fixChoice) {
        '1' {
            if (-not (Invoke-Preflight -NeedsGodot $false -NeedsCodex $true -NeedsAuditQueue $true -NeedsCleanApply $true -AllowDirtyApply $AllowDirtyApply)) {
                Write-RootStepSummary -Step 'post-audit apply fix' -Status 'failed' -Detail 'Codex or queue preflight failed.'
                return 1
            }
            & (Join-Path $internal 'run_improvement_pass.ps1') -PrintPrompt -RunCodex -AllowDirtyApply:$AllowDirtyApply
            $applyExitCode = Get-SafeLastExitCode
            Write-RootStepSummary -Step 'post-audit apply fix' -Status ($(if ($applyExitCode -eq 0) { 'passed' } else { 'failed' })) -Detail "run_improvement_pass exit code $applyExitCode"
            return $applyExitCode
        }
        '2' {
            & (Join-Path $internal 'run_improvement_pass.ps1') -MenuPreview
            $promptExitCode = Get-SafeLastExitCode
            if ($promptExitCode -ne 0) {
                Write-RootStepSummary -Step 'post-audit show fix prompt' -Status 'failed' -Detail "run_improvement_pass exit code $promptExitCode"
                return $promptExitCode
            }

            Write-Host ''
            Write-Host 'Prompt shown. What now?'
            Write-Host ''
            Write-Host '1. Apply this fix/review now'
            Write-Host '2. Close'
            Write-Host ''
            $afterPromptChoice = Read-Host 'Choose 1-2'
            if ($afterPromptChoice -eq '1') {
                if (-not (Invoke-Preflight -NeedsGodot $false -NeedsCodex $true -NeedsAuditQueue $true -NeedsCleanApply $true -AllowDirtyApply $AllowDirtyApply)) {
                    Write-RootStepSummary -Step 'post-prompt apply fix' -Status 'failed' -Detail 'Codex or queue preflight failed.'
                    return 1
                }
                & (Join-Path $internal 'run_improvement_pass.ps1') -RunCodex -AllowDirtyApply:$AllowDirtyApply
                $afterPromptApplyExitCode = Get-SafeLastExitCode
                Write-RootStepSummary -Step 'post-prompt apply fix' -Status ($(if ($afterPromptApplyExitCode -eq 0) { 'passed' } else { 'failed' })) -Detail "run_improvement_pass exit code $afterPromptApplyExitCode"
                return $afterPromptApplyExitCode
            }

            Write-Host 'Closed without applying a fix/review.'
            Write-RootStepSummary -Step 'post-prompt apply choice' -Status 'skipped' -Detail 'User closed after previewing the prompt.'
            return 0
        }
        default {
            Write-Host 'Closed without applying a fix.'
            Write-RootStepSummary -Step 'post-audit fix menu' -Status 'skipped' -Detail 'User closed without applying a fix.'
            return 0
        }
    }
}

if ($interactive) {
    $choice = Show-Menu
    switch ($choice) {
        '' { $Tier = 'Light' }
        '1' { $Tier = 'Light' }
        '2' { $Tier = 'Deep' }
        '3' {
            Write-Host 'Cancelled.'
            Pause-IfInteractive -Interactive $true
            Stop-RunLog
            exit 0
        }
        default {
            Write-Host "Invalid choice: $choice"
            Write-RootStepSummary -Step 'menu selection' -Status 'failed' -Detail "Invalid choice: $choice"
            Pause-IfInteractive -Interactive $true
            Stop-RunLog
            exit 1
        }
    }
}

try {
    if ($NextFix) {
        if (-not (Invoke-Preflight -NeedsGodot $false -NeedsCodex $true -NeedsAuditQueue $true -NeedsCleanApply $true -AllowDirtyApply $AllowDirtyApply)) {
            Write-RootStepSummary -Step 'next fix preflight' -Status 'failed' -Detail 'No runnable evidence-backed fix or review-backed polish prompt is available.'
            Pause-IfInteractive -Interactive $interactive
            exit 1
        }
        & (Join-Path $internal 'run_improvement_pass.ps1') -PrintPrompt -RunCodex -AllowDirtyApply:$AllowDirtyApply
        $exitCode = Get-SafeLastExitCode
        Write-Host "Full run log saved: $script:transcriptPath"
        Pause-IfInteractive -Interactive $interactive
        Stop-RunLog
        exit $exitCode
    }

    $auditTierForPreflight = if ($SkipAudit) { '' } else { $Tier }
    if (-not (Invoke-Preflight -NeedsGodot (-not $SkipAudit) -NeedsCodex $false -NeedsAuditQueue $false -AuditTier $auditTierForPreflight)) {
        Write-RootStepSummary -Step 'audit preflight' -Status 'failed' -Detail 'Audit prerequisites are missing.'
        Pause-IfInteractive -Interactive $interactive
        exit 1
    }
    & (Join-Path $internal 'run_cycle.ps1') -Tier $Tier -SkipAudit:$SkipAudit
    $exitCode = Get-SafeLastExitCode
    if ($exitCode -eq 0 -and -not $SkipAudit) {
        $postAuditExitCode = Invoke-PostAuditFixMenu -Interactive $interactive
        if ($postAuditExitCode -ne 0) {
            $exitCode = $postAuditExitCode
        }
    }
    Write-Host "Full run log saved: $script:transcriptPath"
    Pause-IfInteractive -Interactive $interactive
    Stop-RunLog
    exit $exitCode
} catch {
    Write-Host ''
    Write-Host "Failed: $($_.Exception.Message)"
    Write-Host "Full run log saved: $script:transcriptPath"
    Pause-IfInteractive -Interactive $interactive
    Stop-RunLog
    exit 1
}
