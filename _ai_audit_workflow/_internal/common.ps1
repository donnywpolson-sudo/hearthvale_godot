Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WorkflowRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '.')).Path
}

function Get-RepoRoot {
    if ((Split-Path -Leaf $PSScriptRoot) -eq '_internal') {
        return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    }
    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Read-WorkflowConfig {
    $path = Join-Path (Get-WorkflowRoot) 'config.json'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing workflow config: $path"
    }
    return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
}

function Ensure-WorkflowState {
    param([Parameter(Mandatory)] $Config)
    $stateDir = Join-Path (Get-RepoRoot) $Config.currentDir
    if (-not (Test-Path -LiteralPath $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir | Out-Null
    }
    return $stateDir
}

function Assert-HearthvaleRepo {
    $repoRoot = Get-RepoRoot
    $projectFile = Join-Path $repoRoot 'project.godot'
    if (-not (Test-Path -LiteralPath $projectFile)) {
        throw "project.godot was not found in repo root: $repoRoot"
    }
    return $repoRoot
}

function ConvertTo-JsonFile {
    param(
        [Parameter(Mandatory)] $Value,
        [Parameter(Mandatory)][string] $Path
    )
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-ShortGitStatus {
    param([Parameter(Mandatory)][string] $RepoRoot)
    Push-Location $RepoRoot
    try {
        $status = @(git status --short)
        return $status
    } finally {
        Pop-Location
    }
}

function Test-GitStatusClean {
    param([Parameter(Mandatory)][string] $RepoRoot)
    $status = @(Get-ShortGitStatus -RepoRoot $RepoRoot)
    return $status.Count -eq 0
}

function Invoke-RepoCommand {
    param(
        [Parameter(Mandatory)][string] $Label,
        [Parameter(Mandatory)][scriptblock] $Command,
        [string] $FailureHint = '',
        [switch] $Quiet,
        [int] $FailureOutputLines = 40
    )
    Write-Host "==> $Label"
    $output = @()
    $global:LASTEXITCODE = 0
    if ($Quiet) {
        $output = @(& $Command 2>&1)
    } else {
        & $Command
    }
    $exitCode = if ($null -eq $global:LASTEXITCODE) { 0 } else { $global:LASTEXITCODE }
    if ($exitCode -ne 0) {
        if ($Quiet -and $output.Count -gt 0) {
            Write-Host "Captured output tail for failed step:"
            $output | Select-Object -Last $FailureOutputLines | ForEach-Object { Write-Host $_ }
        }
        if ($FailureHint.Trim().Length -gt 0) {
            throw "$Label failed with exit code $exitCode. $FailureHint"
        }
        throw "$Label failed with exit code $exitCode."
    }
}

function Get-SafeLastExitCode {
    $lastExit = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
    if ($null -eq $lastExit -or $null -eq $lastExit.Value) {
        return 0
    }
    return [int]$lastExit.Value
}

function Write-StepSummary {
    param(
        [Parameter(Mandatory)][string] $Step,
        [Parameter(Mandatory)][string] $Status,
        [string] $LogPath = '',
        [string] $Detail = ''
    )
    Write-Host ''
    Write-Host "STEP SUMMARY: $Step"
    Write-Host "  Status: $Status"
    if ($LogPath.Trim().Length -gt 0) {
        Write-Host "  Log: $LogPath"
    }
    if ($Detail.Trim().Length -gt 0) {
        Write-Host "  Detail: $Detail"
    }
    Write-Host ''
}

function Get-LatestVisualReviewFolder {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [datetime] $EarliestWriteTime = [datetime]::MinValue
    )
    $root = Join-Path $RepoRoot '.godot\visual_review'
    if (-not (Test-Path -LiteralPath $root)) {
        return $null
    }
    return Get-ChildItem -LiteralPath $root -Directory |
        Where-Object { $_.LastWriteTime -ge $EarliestWriteTime } |
        Sort-Object Name -Descending |
        Select-Object -First 1
}

function Test-ArtifactFresh {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][datetime] $EarliestWriteTime
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    $item = Get-Item -LiteralPath $Path
    return $item.LastWriteTime -ge $EarliestWriteTime
}

function Read-JsonFileOrNull {
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    $raw = Get-Content -Raw -LiteralPath $Path
    if ($raw.Trim().Length -eq 0) {
        return $null
    }
    return $raw | ConvertFrom-Json
}

function Read-FreshJsonFileOrNull {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][datetime] $EarliestWriteTime
    )
    if (-not (Test-ArtifactFresh -Path $Path -EarliestWriteTime $EarliestWriteTime)) {
        return $null
    }
    return Read-JsonFileOrNull -Path $Path
}

function Test-VisualReviewCompleteness {
    param(
        $Folder,
        [Parameter(Mandatory)] $Config
    )
    if ($null -eq $Folder) {
        return [pscustomobject]@{ passed = $false; detail = 'No fresh visual review folder found.' }
    }

    $expectedViewports = [int](Get-ObjectProperty -Object $Config -Name 'visualCaptureExpectedViewports' -Default 3)
    $expectedStatesPerViewport = [int](Get-ObjectProperty -Object $Config -Name 'visualCaptureExpectedStatesPerViewport' -Default 9)
    $promptPath = Join-Path $Folder.FullName 'visual_review_prompt.md'
    if (-not (Test-Path -LiteralPath $promptPath)) {
        return [pscustomobject]@{ passed = $false; detail = "Missing visual_review_prompt.md in $($Folder.FullName)." }
    }

    $viewportDirs = @(Get-ChildItem -LiteralPath $Folder.FullName -Directory)
    if ($viewportDirs.Count -lt $expectedViewports) {
        return [pscustomobject]@{ passed = $false; detail = "Expected $expectedViewports viewport folders; found $($viewportDirs.Count) in $($Folder.FullName)." }
    }

    foreach ($viewportDir in $viewportDirs | Select-Object -First $expectedViewports) {
        $pngCount = @(Get-ChildItem -LiteralPath $viewportDir.FullName -Filter '*.png' -File).Count
        if ($pngCount -lt $expectedStatesPerViewport) {
            return [pscustomobject]@{ passed = $false; detail = "Expected $expectedStatesPerViewport PNGs in $($viewportDir.Name); found $pngCount." }
        }
    }

    $totalExpected = $expectedViewports * $expectedStatesPerViewport
    $totalPngs = @(Get-ChildItem -LiteralPath $Folder.FullName -Filter '*.png' -File -Recurse).Count
    if ($totalPngs -lt $totalExpected) {
        return [pscustomobject]@{ passed = $false; detail = "Expected $totalExpected total PNGs; found $totalPngs in $($Folder.FullName)." }
    }

    return [pscustomobject]@{ passed = $true; detail = "$totalPngs PNGs across $($viewportDirs.Count) viewport folder(s), with visual_review_prompt.md." }
}

function Get-ObjectProperty {
    param(
        $Object,
        [Parameter(Mandatory)][string] $Name,
        $Default = $null
    )
    if ($null -eq $Object) {
        return $Default
    }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        return $Default
    }
    return $prop.Value
}

function Format-StatusBlock {
    param([string[]] $Lines)
    if ($null -eq $Lines -or $Lines.Count -eq 0) {
        return 'None.'
    }
    return ($Lines -join "`n")
}
