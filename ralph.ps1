#Requires -Version 7.0
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.ps1 [options] [-MaxIterations <n>] [-Tool <tool>]
# Tools: amp, opencode, claude, copilot (default: opencode)
# Can also use RALPH_TOOL env var
#
# Options:
#   -DryRun           Show what would be executed without running
#   -Help             Show this help message

param(
    [int]$MaxIterations = 10,
    [string]$Tool = "",
    [switch]$DryRun,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# =============================================================================
# Helper Functions
# =============================================================================

function Show-Help {
    @"
Ralph Wiggum - Long-running AI agent loop

Usage: ./ralph.ps1 [options] [-MaxIterations <n>] [-Tool <tool>]

Options:
  -DryRun           Show what would be executed without running
  -Help             Show this help message

Arguments:
  -MaxIterations    Maximum number of iterations (default: 10)
  -Tool             AI tool to use: amp, opencode, claude, copilot (default: opencode)

Environment variables:
  RALPH_TOOL          Default tool to use
"@
}

function Initialize-ProgressFile {
    @(
        "# Ralph Progress Log",
        "Started: $(Get-Date)",
        "---"
    ) | Set-Content $script:ProgressFile
}

function Get-StoryById {
    param([string]$StoryId, $PrdContent)
    $PrdContent.userStories | Where-Object { $_.id -eq $StoryId }
}

function Test-Dependencies {
    param([string]$StoryId, $PrdContent)

    $story = Get-StoryById -StoryId $StoryId -PrdContent $PrdContent
    if (-not $story.dependsOn -or $story.dependsOn.Count -eq 0) {
        return $true
    }

    foreach ($depId in $story.dependsOn) {
        $depStory = Get-StoryById -StoryId $depId -PrdContent $PrdContent
        if (-not $depStory -or $depStory.passes -ne $true) {
            return $false
        }
    }
    return $true
}

function Get-NextStory {
    param($PrdContent)

    $PrdContent.userStories |
        Where-Object { $_.passes -ne $true } |
        Sort-Object priority |
        Where-Object { Test-Dependencies -StoryId $_.id -PrdContent $PrdContent } |
        Select-Object -First 1
}

function Get-PendingDeps {
    param([string]$StoryId, $PrdContent)

    $story = Get-StoryById -StoryId $StoryId -PrdContent $PrdContent
    if (-not $story.dependsOn -or $story.dependsOn.Count -eq 0) {
        return @()
    }

    $story.dependsOn | Where-Object {
        $depStory = Get-StoryById -StoryId $_ -PrdContent $PrdContent
        -not $depStory -or $depStory.passes -ne $true
    }
}

function Build-Command {
    param([string]$ToolName, [string]$StoryId, [string]$StoryTitle)

    $task = "Execute story ${StoryId}: $StoryTitle"

    switch ($ToolName) {
        "amp" {
            "Get-Content `"$script:PromptFile`" -Raw | amp --dangerously-allow-all `"$task`""
        }
        "opencode" {
            "[with OPENCODE_PERMISSION='`"allow`"'] opencode run --model github-copilot/claude-opus-4.5 --agent build `"$task`" --file `"$script:PromptFile`""
        }
        "claude" {
            "Get-Content `"$script:PromptFile`" -Raw | claude -p --dangerously-skip-permissions `"$task`""
        }
        "copilot" {
            "Get-Content `"$script:PromptFile`" -Raw | copilot -p --add-dir `"$(Get-Location)`" --allow-all `"$task`""
        }
    }
}

function Invoke-Tool {
    param([string]$ToolName, [string]$StoryId, [string]$StoryTitle)

    $task = "Execute story ${StoryId}: $StoryTitle"

    switch ($ToolName) {
        "amp" {
            Get-Content $script:PromptFile -Raw | amp --dangerously-allow-all $task
        }
        "opencode" {
            $env:OPENCODE_PERMISSION = '"allow"'
            opencode run --model github-copilot/claude-opus-4.5 --agent build $task --file $script:PromptFile
        }
        "claude" {
            Get-Content $script:PromptFile -Raw | claude -p --dangerously-skip-permissions $task
        }
        "copilot" {
            Get-Content $script:PromptFile -Raw | copilot -p --add-dir (Get-Location) --allow-all $task
        }
    }
}

function Show-BlockedStories {
    param($PrdContent)

    Write-Host "Remaining stories and their pending dependencies:"
    $PrdContent.userStories | Where-Object { $_.passes -ne $true } | ForEach-Object {
        $pending = Get-PendingDeps -StoryId $_.id -PrdContent $PrdContent
        $pendingStr = if ($pending.Count -gt 0) { $pending -join ", " } else { "none" }
        Write-Host "  - $($_.id) ($($_.title)): waiting on [$pendingStr]"
    }
}

function Get-Progress {
    param($PrdContent)

    $total = @($PrdContent.userStories).Count
    $complete = @($PrdContent.userStories | Where-Object { $_.passes -eq $true }).Count
    $percent = if ($total -gt 0) { [math]::Floor($complete * 100 / $total) } else { 0 }

    @{ Total = $total; Complete = $complete; Percent = $percent }
}

# =============================================================================
# Argument Processing
# =============================================================================

if ($Help) {
    Show-Help
    exit 0
}

if ([string]::IsNullOrEmpty($Tool)) {
    $Tool = if ($env:RALPH_TOOL) { $env:RALPH_TOOL } else { "opencode" }
}

if ($Tool -notin @("amp", "opencode", "claude", "copilot")) {
    Write-Host "Error: Unknown tool '$Tool'"
    Write-Host "Valid options: amp, opencode, claude, copilot"
    exit 1
}

# =============================================================================
# Path Setup
# =============================================================================

$ScriptDir = $PSScriptRoot
$TasksDir = Join-Path (Get-Location) "tasks"
$PrdFile = Join-Path $TasksDir "prd.json"
$ProgressFile = Join-Path $TasksDir "progress.txt"
$ArchiveDir = Join-Path $TasksDir "archive"
$LastBranchFile = Join-Path $TasksDir ".last-branch"
$PromptFile = Join-Path $ScriptDir "prompt.md"

# =============================================================================
# Archive Previous Run (if branch changed)
# =============================================================================

if ((Test-Path $PrdFile) -and (Test-Path $LastBranchFile)) {
    try {
        $prdContent = Get-Content $PrdFile -Raw | ConvertFrom-Json
        $CurrentBranch = $prdContent.branchName
        $LastBranch = (Get-Content $LastBranchFile -Raw -ErrorAction SilentlyContinue)?.Trim()

        if ($CurrentBranch -and $LastBranch -and ($CurrentBranch -ne $LastBranch)) {
            $FolderName = $LastBranch -replace '^ralph/', ''
            $ArchiveFolder = Join-Path $ArchiveDir "$(Get-Date -Format 'yyyy-MM-dd')-$FolderName"

            Write-Host "Archiving previous run: $LastBranch"
            New-Item -ItemType Directory -Path $ArchiveFolder -Force | Out-Null
            if (Test-Path $PrdFile) { Copy-Item $PrdFile $ArchiveFolder }
            if (Test-Path $ProgressFile) { Copy-Item $ProgressFile $ArchiveFolder }
            Write-Host "   Archived to: $ArchiveFolder"

            Initialize-ProgressFile
        }
    } catch {
        # Ignore errors during archive
    }
}

# Track current branch
if (Test-Path $PrdFile) {
    try {
        $prdContent = Get-Content $PrdFile -Raw | ConvertFrom-Json
        if ($prdContent.branchName) {
            $prdContent.branchName | Set-Content $LastBranchFile
        }
    } catch {
        # Ignore JSON parsing errors
    }
}

# =============================================================================
# Validation
# =============================================================================

if (-not (Test-Path $PrdFile)) {
    Write-Host "Error: $PrdFile not found."
    Write-Host "Create a prd.json file in the tasks/ directory before running Ralph."
    exit 1
}

if (-not (Test-Path $ProgressFile)) {
    Initialize-ProgressFile
}

# =============================================================================
# Main Loop
# =============================================================================

Write-Host "Starting Ralph - Max iterations: $MaxIterations, Tool: $Tool"
if ($DryRun) { Write-Host "  Dry run: ENABLED (no commands will be executed)" }

for ($i = 1; $i -le $MaxIterations; $i++) {
    # Load PRD and get progress
    try {
        $prdContent = Get-Content $PrdFile -Raw | ConvertFrom-Json
        $progress = Get-Progress -PrdContent $prdContent
    } catch {
        $progress = @{ Total = 0; Complete = 0; Percent = 0 }
    }

    # Show progress header
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════"
    Write-Host "  Ralph Iteration $i of $MaxIterations"
    Write-Host "  Progress: $($progress.Complete)/$($progress.Total) stories complete ($($progress.Percent)%)"
    Write-Host "═══════════════════════════════════════════════════════"

    # Exit conditions
    if ($progress.Total -eq 0) {
        Write-Host "`nError: No stories found in prd.json"
        exit 1
    }

    if ($progress.Complete -eq $progress.Total) {
        Write-Host "`nRalph completed all tasks!"
        exit 0
    }

    # Get next eligible story
    $nextStory = Get-NextStory -PrdContent $prdContent

    if (-not $nextStory) {
        Write-Host "`nError: No eligible stories found. Possible dependency cycle or unmet dependencies.`n"
        Show-BlockedStories -PrdContent $prdContent
        exit 1
    }

    Write-Host "  Next story: $($nextStory.id) - $($nextStory.title)"
    Write-Host "───────────────────────────────────────────────────────"

    # Build and execute command
    $cmd = Build-Command -ToolName $Tool -StoryId $nextStory.id -StoryTitle $nextStory.title

    if ($DryRun) {
        Write-Host "[DRY RUN] Would execute:"
        Write-Host "  $cmd"
        Write-Host ""
        Write-Host "[DRY RUN] After execution, would check if story $($nextStory.id) was marked as complete"
    } else {
        try {
            Invoke-Tool -ToolName $Tool -StoryId $nextStory.id -StoryTitle $nextStory.title
        } catch {
            # Continue even if tool fails
        }
    }

    Start-Sleep -Seconds 2
}

Write-Host ""
Write-Host "Ralph reached max iterations ($MaxIterations) without completing all tasks."
Write-Host "Check $ProgressFile for status."
exit 1
