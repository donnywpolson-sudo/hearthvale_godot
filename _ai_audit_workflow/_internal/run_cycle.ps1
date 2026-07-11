param(
    [ValidateSet('Light', 'Deep')]
    [string] $Tier = 'Light',
    [int] $MaxPasses = 0,
    [switch] $AutoImprove,
    [switch] $VerifyAfterFix,
    [switch] $AllowDirtyApply,
    [switch] $SkipAudit
)

. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Assert-HearthvaleRepo

if (-not $SkipAudit) {
    & (Join-Path $PSScriptRoot 'run_deep_audit.ps1') -Tier $Tier
    $exitCode = Get-SafeLastExitCode
    if ($exitCode -ne 0) {
        try {
            & (Join-Path $PSScriptRoot 'build_improvement_queue.ps1') | Out-Host
        } catch {
            Write-Host "Queue invalidation after failed audit did not complete: $($_.Exception.Message)"
        }
        Write-Host 'fail'
        exit $exitCode
    }
}

& (Join-Path $PSScriptRoot 'build_improvement_queue.ps1')
$exitCode = Get-SafeLastExitCode
if ($exitCode -ne 0) {
    Write-Host 'fail'
    exit $exitCode
}
$config = Read-WorkflowConfig
$stateDir = Ensure-WorkflowState -Config $config
$queuePath = Join-Path $stateDir 'improvement_queue.json'
$queue = Read-JsonFileOrNull -Path $queuePath
$queueCount = [int](Get-ObjectProperty -Object $queue -Name 'count' -Default 0)
$evidenceBackedCount = [int](Get-ObjectProperty -Object $queue -Name 'evidenceBackedCount' -Default 0)
$reviewBackedCount = [int](Get-ObjectProperty -Object $queue -Name 'reviewBackedCount' -Default 0)
Write-StepSummary -Step 'improvement queue build' -Status 'passed' -LogPath $queuePath -Detail "$queueCount queued item(s): $evidenceBackedCount evidence-backed, $reviewBackedCount review-backed"

if ($MaxPasses -gt 0) {
    if (-not $AutoImprove) {
        & (Join-Path $PSScriptRoot 'run_improvement_pass.ps1') -PrintPrompt
        $exitCode = Get-SafeLastExitCode
        if ($exitCode -ne 0) {
            Write-Host 'fail'
            exit $exitCode
        }
        Write-Host 'Prepared the next improvement pass prompt. Review it, run it, validate it, then rerun this cycle.'
        exit 0
    }

    for ($pass = 1; $pass -le $MaxPasses; $pass++) {
        $queue = Read-JsonFileOrNull -Path $queuePath
        $queuedItems = @((Get-ObjectProperty -Object $queue -Name 'items' -Default @()) | Where-Object { $_.status -eq 'queued' })
        if ($queuedItems.Count -eq 0) {
            Write-Host "No queued improvement item remains before pass $pass."
            break
        }

        Write-Host "Starting improvement pass $pass of ${MaxPasses}: $($queuedItems[0].title)"
        $allowPassDirtyApply = $AllowDirtyApply -or $pass -gt 1
        & (Join-Path $PSScriptRoot 'run_improvement_pass.ps1') -PrintPrompt -RunCodex -AllowDirtyApply:$allowPassDirtyApply
        $exitCode = Get-SafeLastExitCode
        if ($exitCode -ne 0) {
            Write-Host 'fail'
            exit $exitCode
        }

        if ($VerifyAfterFix) {
            Write-Host "Verifying improvement pass $pass with a fresh Light audit."
            & (Join-Path $PSScriptRoot 'run_deep_audit.ps1') -Tier Light
            $verifyExitCode = Get-SafeLastExitCode
            if ($verifyExitCode -ne 0) {
                Write-Host 'fail'
                exit $verifyExitCode
            }
            & (Join-Path $PSScriptRoot 'build_improvement_queue.ps1')
            $queueExitCode = Get-SafeLastExitCode
            if ($queueExitCode -ne 0) {
                Write-Host 'fail'
                exit $queueExitCode
            }
        }
    }
    Write-Host 'pass'
    Write-Host "Completed up to $MaxPasses bounded improvement pass(es)."
} else {
    Write-Host 'pass'
    Write-Host 'Audit and queue generation complete.'
    Write-Host 'Use .\_ai_audit_workflow\RUN_AUDIT.ps1 -NextFix to apply one queued item intentionally.'
}
