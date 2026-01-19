#Requires -Version 7.0
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.ps1 [max_iterations] [tool]
# Tools: amp, opencode, claude (default: opencode)
# Can also use RALPH_TOOL env var

param(
    [int]$MaxIterations = 10,
    [string]$Tool = ""
)

$ErrorActionPreference = "Stop"

# Determine tool: param > env var > default
if ([string]::IsNullOrEmpty($Tool)) {
    $Tool = $env:RALPH_TOOL
    if ([string]::IsNullOrEmpty($Tool)) {
        $Tool = "opencode"
    }
}

# Validate tool selection
switch ($Tool) {
    "amp" { }
    "opencode" { }
    "claude" { }
    default {
        Write-Host "Error: Unknown tool '$Tool'"
        Write-Host "Valid options: amp, opencode, claude"
        exit 1
    }
}

$ScriptDir = $PSScriptRoot
$TasksDir = Join-Path (Get-Location) "tasks"
$PrdFile = Join-Path $TasksDir "prd.json"
$ProgressFile = Join-Path $TasksDir "progress.txt"
$ArchiveDir = Join-Path $TasksDir "archive"
$LastBranchFile = Join-Path $TasksDir ".last-branch"
$PromptFile = Join-Path $ScriptDir "prompt.md"

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

# Check if prd.json exists
if (-not (Test-Path $PrdFile)) {
    Write-Host "Error: $PrdFile not found."
    Write-Host "Create a prd.json file in the tasks/ directory before running Ralph."
    exit 1
}

# Initialize progress file if it doesn't exist
if (-not (Test-Path $ProgressFile)) {
    @(
        "# Ralph Progress Log",
        "Started: $(Get-Date)",
        "---"
    ) | Set-Content $ProgressFile
}

Write-Host "Starting Ralph - Max iterations: $MaxIterations, Tool: $Tool"

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
    
    # Pre-select the next story (lowest priority number first)
    $nextStory = $prdContent.userStories | Where-Object { $_.passes -ne $true } | Sort-Object priority | Select-Object -First 1
    $nextStoryId = $nextStory.id
    $nextStoryTitle = $nextStory.title
    
    Write-Host "  Next story: $nextStoryId - $nextStoryTitle"
    Write-Host "───────────────────────────────────────────────────────"
    
    # Run the selected tool with the ralph prompt, passing the specific story
    try {
        switch ($Tool) {
            "amp" {
                Get-Content $PromptFile -Raw | amp --dangerously-allow-all "Execute story ${nextStoryId}: $nextStoryTitle"
            }
            "opencode" {
                opencode run --model github-copilot/claude-opus-4.5 --agent build "Execute story ${nextStoryId}: $nextStoryTitle" --file $PromptFile
            }
            "claude" {
                Get-Content $PromptFile -Raw | claude -p "Execute story ${nextStoryId}: $nextStoryTitle"
            }
        }
    } catch {
        # Continue even if tool fails
    }
    
    Start-Sleep -Seconds 2
}

Write-Host ""
Write-Host "Ralph reached max iterations ($MaxIterations) without completing all tasks."
Write-Host "Check $ProgressFile for status."
exit 1
