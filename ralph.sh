#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.sh [options] [max_iterations] [tool]
# Tools: amp, opencode, claude, copilot (default: opencode)
# Can also use RALPH_TOOL and RALPH_MODEL env vars
#
# Options:
#   --model <model>   Model to use (overrides RALPH_MODEL and tool defaults)
#   --dry-run         Show what would be executed without running
#   --help            Show this help message

set -e

# =============================================================================
# Configuration
# =============================================================================

DRY_RUN=false
MODEL=""

# Tool-specific default models
DEFAULT_MODEL_OPENCODE="litellm/github-copilot/claude-opus-4.5"
DEFAULT_MODEL_CLAUDE="claude-opus-4-5"
DEFAULT_MODEL_AMP="github-copilot/claude-opus-4.5"
DEFAULT_MODEL_COPILOT="github-copilot/claude-opus-4.5"

# =============================================================================
# Helper Functions
# =============================================================================

show_help() {
  cat << 'EOF'
Ralph Wiggum - Long-running AI agent loop

Usage: ./ralph.sh [options] [max_iterations] [tool]

Options:
  --model <model>   Model to use (overrides RALPH_MODEL and tool defaults)
  --dry-run         Show what would be executed without running
  --help            Show this help message

Arguments:
  max_iterations    Maximum number of iterations (default: 10)
  tool              AI tool to use: amp, opencode, claude, copilot (default: opencode)

Environment variables:
  RALPH_TOOL          Default tool to use
  RALPH_MODEL         Default model to use (overrides tool-specific defaults)

Tool-specific default models:
  opencode, amp, copilot: github-copilot/claude-opus-4.5
  claude:                 claude-opus-4-5
EOF
}

init_progress_file() {
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
}

# Get a field from a story by ID
get_story_field() {
  local story_id="$1" field="$2"
  jq -r --arg id "$story_id" ".userStories[] | select(.id == \$id) | .$field // empty" "$PRD_FILE" 2>/dev/null
}

# Get all dependencies for a story as newline-separated list
get_story_deps() {
  local story_id="$1"
  jq -r --arg id "$story_id" '.userStories[] | select(.id == $id) | .dependsOn // [] | .[]' "$PRD_FILE" 2>/dev/null
}

# Check if all dependencies are satisfied for a story
check_dependencies() {
  local story_id="$1"
  local deps dep_passes
  deps=$(get_story_deps "$story_id")

  [ -z "$deps" ] && return 0  # No dependencies

  for dep in $deps; do
    dep_passes=$(get_story_field "$dep" "passes")
    [ "$dep_passes" != "true" ] && return 1
  done
  return 0
}

# Get next eligible story ID (respecting dependencies, sorted by priority)
get_next_story() {
  local stories story_id
  stories=$(jq -r '[.userStories[] | select(.passes != true)] | sort_by(.priority) | .[].id' "$PRD_FILE" 2>/dev/null)

  for story_id in $stories; do
    check_dependencies "$story_id" && { echo "$story_id"; return 0; }
  done
  return 1
}

# Get pending (unsatisfied) dependencies for a story as comma-separated string
get_pending_deps() {
  local story_id="$1"
  local deps dep_passes pending=""
  deps=$(get_story_deps "$story_id")

  for dep in $deps; do
    dep_passes=$(get_story_field "$dep" "passes")
    [ "$dep_passes" != "true" ] && pending="${pending:+$pending, }$dep"
  done
  echo "$pending"
}

# Get the model to use for a given tool
get_model_for_tool() {
  local tool="$1"
  if [ -n "$MODEL" ]; then
    echo "$MODEL"
  elif [ -n "$RALPH_MODEL" ]; then
    echo "$RALPH_MODEL"
  else
    case "$tool" in
      opencode) echo "$DEFAULT_MODEL_OPENCODE" ;;
      claude)   echo "$DEFAULT_MODEL_CLAUDE" ;;
      amp)      echo "$DEFAULT_MODEL_AMP" ;;
      copilot)  echo "$DEFAULT_MODEL_COPILOT" ;;
    esac
  fi
}

# Build the command for a given tool
build_command() {
  local tool="$1" story_id="$2" story_title="$3"
  local task="Execute story $story_id: $story_title"
  local model
  model=$(get_model_for_tool "$tool")

  case "$tool" in
    amp)
      echo "cat \"$PROMPT_FILE\" | amp --model \"$model\" --dangerously-allow-all \"$task\""
      ;;
    opencode)
      local prefix=""
      prefix="OPENCODE_PERMISSION='{\"*\": \"allow\"}' "
      echo "${prefix}opencode run --model \"$model\" --agent build \"$task\" --file \"$PROMPT_FILE\""
      ;;
    claude)
      local flags=""
      flags="--dangerously-skip-permissions "
      echo "cat \"$PROMPT_FILE\" | claude -p --model \"$model\" ${flags}\"$task\""
      ;;
    copilot)
      local flags="--add-dir \"\$(pwd)\" "
      flags+="--allow-all "
      echo "cat \"$PROMPT_FILE\" | copilot -p --model \"$model\" ${flags}\"$task\""
      ;;
  esac
}

# Show remaining stories with their pending dependencies
show_blocked_stories() {
  echo "Remaining stories and their pending dependencies:"
  local story_ids story_id pending title
  story_ids=$(jq -r '[.userStories[] | select(.passes != true)] | .[].id' "$PRD_FILE" 2>/dev/null)

  for story_id in $story_ids; do
    pending=$(get_pending_deps "$story_id")
    title=$(get_story_field "$story_id" "title")
    echo "  - $story_id ($title): waiting on [$pending]"
  done
}

# =============================================================================
# Argument Parsing
# =============================================================================

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)        MODEL="$2"; shift 2 ;;
    --dry-run)      DRY_RUN=true; shift ;;
    --help)         show_help; exit 0 ;;
    -*)             echo "Error: Unknown option '$1'"; echo "Use --help for usage information"; exit 1 ;;
    *)              break ;;
  esac
done

# =============================================================================
# Path Setup
# =============================================================================

MAX_ITERATIONS=${1:-10}
TOOL="${2:-${RALPH_TOOL:-opencode}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASKS_DIR="$(pwd)/tasks"
PRD_FILE="$TASKS_DIR/prd.json"
PROGRESS_FILE="$TASKS_DIR/progress.txt"
ARCHIVE_DIR="$TASKS_DIR/archive"
LAST_BRANCH_FILE="$TASKS_DIR/.last-branch"
PROMPT_FILE="$SCRIPT_DIR/prompt.md"

# Validate tool selection
case "$TOOL" in
  amp|opencode|claude|copilot) ;;
  *) echo "Error: Unknown tool '$TOOL'"; echo "Valid options: amp, opencode, claude, copilot"; exit 1 ;;
esac

# =============================================================================
# Archive Previous Run (if branch changed)
# =============================================================================

if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")

  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$(date +%Y-%m-%d)-$(echo "$LAST_BRANCH" | sed 's|^ralph/||')"

    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"

    init_progress_file
  fi
fi

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  [ -n "$CURRENT_BRANCH" ] && echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
fi

# =============================================================================
# Validation
# =============================================================================

if [ ! -f "$PRD_FILE" ]; then
  echo "Error: $PRD_FILE not found."
  echo "Create a prd.json file in the tasks/ directory before running Ralph."
  exit 1
fi

[ ! -f "$PROGRESS_FILE" ] && init_progress_file

# =============================================================================
# Main Loop
# =============================================================================

echo "Starting Ralph - Max iterations: $MAX_ITERATIONS, Tool: $TOOL, Model: $(get_model_for_tool $TOOL)"
[ "$DRY_RUN" = true ] && echo "  Dry run: ENABLED (no commands will be executed)"

for (( i=1; i<=MAX_ITERATIONS; i++ )); do
  # Get progress counts
  TOTAL_COUNT=$(jq '[.userStories[]] | length' "$PRD_FILE" 2>/dev/null || echo "0")
  COMPLETE_COUNT=$(jq '[.userStories[] | select(.passes == true)] | length' "$PRD_FILE" 2>/dev/null || echo "0")
  PERCENT=$(( TOTAL_COUNT > 0 ? COMPLETE_COUNT * 100 / TOTAL_COUNT : 0 ))

  # Show progress header
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  Ralph Iteration $i of $MAX_ITERATIONS"
  echo "  Progress: $COMPLETE_COUNT/$TOTAL_COUNT stories complete ($PERCENT%)"
  echo "═══════════════════════════════════════════════════════"

  # Exit conditions
  if [ "$TOTAL_COUNT" -eq 0 ]; then
    echo -e "\nError: No stories found in prd.json"
    exit 1
  fi

  if [ "$COMPLETE_COUNT" -eq "$TOTAL_COUNT" ]; then
    echo -e "\nRalph completed all tasks!"
    exit 0
  fi

  # Get next eligible story
  NEXT_STORY_ID=$(get_next_story)

  if [ -z "$NEXT_STORY_ID" ]; then
    echo -e "\nError: No eligible stories found. Possible dependency cycle or unmet dependencies.\n"
    show_blocked_stories
    exit 1
  fi

  NEXT_STORY_TITLE=$(get_story_field "$NEXT_STORY_ID" "title")
  echo "  Next story: $NEXT_STORY_ID - $NEXT_STORY_TITLE"
  echo "───────────────────────────────────────────────────────"

  # Build and execute command
  CMD=$(build_command "$TOOL" "$NEXT_STORY_ID" "$NEXT_STORY_TITLE")

  if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] Would execute:"
    echo "  $CMD"
    echo ""
    echo "[DRY RUN] After execution, would check if story $NEXT_STORY_ID was marked as complete"
  else
    eval "$CMD" || true
  fi

  sleep 2
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."
exit 1
