# Ralph Agent Instructions

## Overview

Ralph is an autonomous AI agent loop that runs your preferred AI coding tool (Amp, Opencode, or Claude Code) repeatedly until all PRD items are complete. Each iteration is a fresh instance with clean context.

## Commands

```bash
# Run the flowchart dev server
cd flowchart && npm run dev

# Build the flowchart
cd flowchart && npm run build

# Run Ralph (from your project that has prd.json)
./ralph.sh [options] [max_iterations] [tool]

# Examples:
./ralph.sh 10 amp      # Use Amp
./ralph.sh 10 opencode # Use Opencode (default)
./ralph.sh 10 claude   # Use Claude Code

# With options:
./ralph.sh --auto-approve 10 opencode  # Skip permission prompts
./ralph.sh --dry-run 10                # Show what would run without executing
./ralph.sh --help                      # Show help

# Or via environment variable:
RALPH_TOOL=claude ./ralph.sh 10
RALPH_AUTO_APPROVE=true ./ralph.sh 10
```

## Options

| Option | Env Variable | Description |
|--------|--------------|-------------|
| `--auto-approve` | `RALPH_AUTO_APPROVE=true` | Skip all permission prompts (use with caution) |
| `--dry-run` | - | Show what would be executed without running |
| `--help` | - | Show help message |

## Key Files

- `ralph.sh` - The bash loop that spawns fresh AI tool instances
- `ralph.ps1` - PowerShell version for Windows
- `prompt.md` - Instructions given to each AI tool instance
- `prd.json.example` - Example PRD format with dependency support
- `flowchart/` - Interactive React Flow diagram explaining how Ralph works

## PRD Format

Stories in `prd.json` support the following fields:

```json
{
  "id": "US-001",
  "title": "Story title",
  "description": "User story description",
  "acceptanceCriteria": ["Criterion 1", "Criterion 2"],
  "priority": 1,
  "dependsOn": ["US-000"],
  "passes": false,
  "notes": ""
}
```

### Story Dependencies

The `dependsOn` field specifies which stories must be completed before this story can be started:

```json
{
  "id": "US-002",
  "title": "Display priority on cards",
  "dependsOn": ["US-001"],
  "priority": 2
}
```

Ralph will:
1. Sort stories by priority
2. Only execute stories whose dependencies are all marked as `passes: true`
3. Show helpful error messages if a dependency cycle or unresolvable dependency is detected

## Flowchart

The `flowchart/` directory contains an interactive visualization built with React Flow. It's designed for presentations - click through to reveal each step with animations.

To run locally:
```bash
cd flowchart
npm install
npm run dev
```

## Patterns

- Each iteration spawns a fresh AI tool instance with clean context
- Memory persists via git history, `progress.txt`, and `prd.json`
- Stories should be small enough to complete in one context window
- Always update AGENTS.md with discovered patterns for future iterations
- Use `dependsOn` to ensure database/API changes happen before UI changes
- Use `--dry-run` to verify story execution order before running

## Auto-Approve Mode

When running in automation (CI/CD), use `--auto-approve` to skip interactive prompts:

- **Amp**: Already uses `--dangerously-allow-all`
- **OpenCode**: Sets `OPENCODE_PERMISSION='"allow"'`
- **Claude Code**: Adds `--dangerously-skip-permissions` flag

**Warning**: This grants the AI full permissions. Only use in trusted environments.
