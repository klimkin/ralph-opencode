#Requires -Version 7.0
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.ps1 [max_iterations]

param(
    [int]$MaxIterations = 10
)

$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot
$PrdFile = Join-Path $ScriptDir "prd.json"
$ProgressFile = Join-Path $ScriptDir "progress.txt"
$ArchiveDir = Join-Path $ScriptDir "archive"
$LastBranchFile = Join-Path $ScriptDir ".last-branch"

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

for ($i = 1; $i -le $MaxIterations; $i++) {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════"
    Write-Host "  Ralph Iteration $i of $MaxIterations"
    Write-Host "═══════════════════════════════════════════════════════"
    
    # Run amp with the ralph prompt
    $PromptPath = Join-Path $ScriptDir "prompt.md"
    $Output = ""
    try {
        $Output = Get-Content $PromptPath -Raw | amp --dangerously-allow-all 2>&1 | Tee-Object -Variable Output
        $Output | Write-Host
    } catch {
        # Continue even if amp fails
    }
    
    # Check for completion signal
    if ($Output -match "<promise>COMPLETE</promise>") {
        Write-Host ""
        Write-Host "Ralph completed all tasks!"
        Write-Host "Completed at iteration $i of $MaxIterations"
        exit 0
    }
    
    Write-Host "Iteration $i complete. Continuing..."
    Start-Sleep -Seconds 2
}

Write-Host ""
Write-Host "Ralph reached max iterations ($MaxIterations) without completing all tasks."
Write-Host "Check $ProgressFile for status."
exit 1
