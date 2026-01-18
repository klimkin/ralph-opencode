#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.sh [max_iterations]

set -e

MAX_ITERATIONS=${1:-10}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASKS_DIR="$(pwd)/tasks"
PRD_FILE="$TASKS_DIR/prd.json"
PROGRESS_FILE="$TASKS_DIR/progress.txt"
ARCHIVE_DIR="$TASKS_DIR/archive"
LAST_BRANCH_FILE="$TASKS_DIR/.last-branch"

# Check if prd.json exists
if [ ! -f "$PRD_FILE" ]; then
  echo "Error: $PRD_FILE not found."
  echo "Create a prd.json file in the tasks/ directory before running Ralph."
  exit 1
fi

# Archive previous run if branch changed
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")
  
  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    # Archive the previous run
    DATE=$(date +%Y-%m-%d)
    # Strip "ralph/" prefix from branch name for folder
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"
    
    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"
    
    # Reset progress file for new run
    echo "# Ralph Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi
fi

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

echo "Starting Ralph - Max iterations: $MAX_ITERATIONS"

i=0
while [ $i -lt $MAX_ITERATIONS ]; do
  i=$((i + 1))
  
  # Get progress
  TOTAL_COUNT=$(jq '[.userStories[]] | length' "$PRD_FILE" 2>/dev/null || echo "0")
  COMPLETE_COUNT=$(jq '[.userStories[] | select(.passes == true)] | length' "$PRD_FILE" 2>/dev/null || echo "0")
  
  if [ "$TOTAL_COUNT" -gt 0 ]; then
    PERCENT=$((COMPLETE_COUNT * 100 / TOTAL_COUNT))
  else
    PERCENT=0
  fi
  
  # Show progress
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  Ralph Iteration $i of $MAX_ITERATIONS"
  echo "  Progress: $COMPLETE_COUNT/$TOTAL_COUNT stories complete ($PERCENT%)"
  echo "═══════════════════════════════════════════════════════"
  
  # Exit if no stories found
  if [ "$TOTAL_COUNT" -eq 0 ]; then
    echo ""
    echo "Error: No stories found in prd.json"
    exit 1
  fi
  
  # Exit if all complete
  if [ "$COMPLETE_COUNT" = "$TOTAL_COUNT" ]; then
    echo ""
    echo "Ralph completed all tasks!"
    exit 0
  fi
  
  # Run opencode with the ralph prompt
  opencode run --model "github-copilot/claude-opus-4.5" --agent Build --file "$SCRIPT_DIR/prompt.md" "Execute the next story" || true
  
  sleep 2
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."
exit 1
