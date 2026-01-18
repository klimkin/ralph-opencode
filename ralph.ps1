#Requires -Version 7.0
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.ps1 [max_iterations]

param(
    [int]$MaxIterations = 10
)

$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot
$TasksDir = Join-Path (Get-Location) "tasks"
$PrdFile = Join-Path $TasksDir "prd.json"
$ProgressFile = Join-Path $TasksDir "progress.txt"
$ArchiveDir = Join-Path $TasksDir "archive"
$LastBranchFile = Join-Path $TasksDir ".last-branch"

# Check if prd.json exists
if (-not (Test-Path $PrdFile)) {
    Write-Host "Error: $PrdFile not found."
    Write-Host "Create a prd.json file in the tasks/ directory before running Ralph."
    exit 1
}

# Archive previous run if branch changed
if ((Test-Path $PrdFile) -and (Test-Path $LastBranchFile)) {
    try {
        $prdContent = Get-Content $PrdFile -Raw | ConvertFrom-Json
        $CurrentBranch = $prdContent.branchName
    } catch {
        $CurrentBranch = $null
    }

    $LastBranch = Get-Content $LastBranchFile -Raw -ErrorAction SilentlyContinue
    if ($LastBranch) { $LastBranch = $LastBranch.Trim() }

    if ($CurrentBranch -and $LastBranch -and ($CurrentBranch -ne $LastBranch)) {
        # Archive the previous run
        $Date = Get-Date -Format "yyyy-MM-dd"
        # Strip "ralph/" prefix from branch name for folder
        $FolderName = $LastBranch -replace '^ralph/', ''
        $ArchiveFolder = Join-Path $ArchiveDir "$Date-$FolderName"

        Write-Host "Archiving previous run: $LastBranch"
        New-Item -ItemType Directory -Path $ArchiveFolder -Force | Out-Null
        if (Test-Path $PrdFile) { Copy-Item $PrdFile $ArchiveFolder }
        if (Test-Path $ProgressFile) { Copy-Item $ProgressFile $ArchiveFolder }
        Write-Host "   Archived to: $ArchiveFolder"

        # Reset progress file for new run
        @(
            "# Ralph Progress Log",
            "Started: $(Get-Date)",
            "---"
        ) | Set-Content $ProgressFile
    }
}

# Track current branch
if (Test-Path $PrdFile) {
    try {
        $prdContent = Get-Content $PrdFile -Raw | ConvertFrom-Json
        $CurrentBranch = $prdContent.branchName
        if ($CurrentBranch) {
            $CurrentBranch | Set-Content $LastBranchFile
        }
    } catch {
        # Ignore JSON parsing errors
    }
}

# Initialize progress file if it doesn't exist
if (-not (Test-Path $ProgressFile)) {
    @(
        "# Ralph Progress Log",
        "Started: $(Get-Date)",
        "---"
    ) | Set-Content $ProgressFile
}

Write-Host "Starting Ralph - Max iterations: $MaxIterations"

$i = 0
while ($i -lt $MaxIterations) {
    $i++
    
    # Get progress
    try {
        $prdContent = Get-Content $PrdFile -Raw | ConvertFrom-Json
        $totalCount = @($prdContent.userStories).Count
        $completeCount = @($prdContent.userStories | Where-Object { $_.passes -eq $true }).Count
        
        if ($totalCount -gt 0) {
            $percent = [math]::Floor($completeCount * 100 / $totalCount)
        } else {
            $percent = 0
        }
    } catch {
        $totalCount = 0
        $completeCount = 0
        $percent = 0
    }
    
    # Show progress
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════"
    Write-Host "  Ralph Iteration $i of $MaxIterations"
    Write-Host "  Progress: $completeCount/$totalCount stories complete ($percent%)"
    Write-Host "═══════════════════════════════════════════════════════"
    
    # Exit if no stories found
    if ($totalCount -eq 0) {
        Write-Host ""
        Write-Host "Error: No stories found in prd.json"
        exit 1
    }
    
    # Exit if all complete
    if ($completeCount -eq $totalCount) {
        Write-Host ""
        Write-Host "Ralph completed all tasks!"
        exit 0
    }
    
    # Run opencode with the ralph prompt
    $PromptPath = Join-Path $ScriptDir "prompt.md"
    try {
        opencode run --model "github-copilot/claude-opus-4.5" --agent Build --file $PromptPath "Execute the next story"
    } catch {
        # Continue even if opencode fails
    }
    
    Start-Sleep -Seconds 2
}

Write-Host ""
Write-Host "Ralph reached max iterations ($MaxIterations) without completing all tasks."
Write-Host "Check $ProgressFile for status."
exit 1
