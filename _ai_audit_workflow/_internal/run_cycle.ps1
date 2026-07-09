param(
    [ValidateSet('Light', 'Deep')]
    [string] $Tier = 'Light',
    [int] $MaxPasses = 0,
    [switch] $SkipAudit
)

. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Assert-HearthvaleRepo

if (-not $SkipAudit) {
    & (Join-Path $PSScriptRoot 'run_deep_audit.ps1') -Tier $Tier
    $exitCode = Get-SafeLastExitCode
    if ($exitCode -ne 0) {
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
    & (Join-Path $PSScriptRoot 'run_improvement_pass.ps1')
    $exitCode = Get-SafeLastExitCode
    if ($exitCode -ne 0) {
        Write-Host 'fail'
        exit $exitCode
    }
    Write-Host "Prepared the next improvement pass prompt. Run it, validate it, then rerun this cycle after the batch."
} else {
    Write-Host 'pass'
    Write-Host 'Audit and queue generation complete.'
    Write-Host 'Interactive runs ask what to do next when evidence-backed fixes or review-backed polish prompts are queued. Non-interactive runs can use .\_ai_audit_workflow\RUN_AUDIT.ps1 -NextFix.'
}
