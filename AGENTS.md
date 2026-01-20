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

## Repository Structure

```
ralph-opencode/
├── AGENTS.md              # This file - agent instructions
├── README.md              # Project documentation
├── ralph.sh               # Main bash loop script
├── ralph.ps1              # PowerShell version for Windows
├── prompt.md              # Instructions given to each AI tool instance
├── prd.json.example       # Example PRD format with dependency support
├── ralph-flowchart.png    # Static flowchart image
├── ralph.webp             # Ralph logo/mascot
├── flowchart/             # Interactive React Flow visualization
│   ├── src/
│   │   ├── App.tsx        # Main flowchart component (11 steps, 4 notes)
│   │   ├── App.css        # Flowchart styles
│   │   └── main.tsx       # React entry point
│   ├── package.json       # Uses React 19, @xyflow/react, Vite 7, TypeScript 5.9
│   └── vite.config.ts     # Vite configuration
├── skills/                # Skills for AI tools (Opencode/Amp/Claude)
│   ├── prd/
│   │   └── SKILL.md       # PRD generator skill - creates tasks/prd-*.md files
│   └── ralph/
│       └── SKILL.md       # PRD-to-JSON converter skill - creates tasks/prd.json
└── .github/
    └── workflows/
        └── deploy.yml     # GitHub Pages deployment for flowchart (Node 20)
```

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

### Tech Stack
- **React 19** with TypeScript 5.9
- **@xyflow/react** (v12) for the flowchart
- **Vite 7** for bundling
- Deployed to GitHub Pages via `.github/workflows/deploy.yml`

### Flowchart Steps (11 total)

| Step | Label | Description | Phase |
|------|-------|-------------|-------|
| 1 | You write a PRD | Define what you want to build | setup |
| 2 | Convert to prd.json | Break into small user stories | setup |
| 3 | Run ralph.sh | Starts the autonomous loop | setup |
| 4 | Pick next story | By priority, check dependsOn | loop |
| 5 | Deps satisfied? | All dependsOn stories pass | decision |
| 6 | Implements it | Writes code, runs tests | loop |
| 7 | Commits changes | If tests pass | loop |
| 8 | Updates prd.json | Sets passes: true | loop |
| 9 | Logs to progress.txt | Saves learnings | loop |
| 10 | More stories? | Decision point | decision |
| 11 | Done! | All stories complete | done |

### Annotation Notes

The flowchart includes 4 contextual notes that appear at specific steps:

1. **prd.json example** (step 2) - Shows story structure with `dependsOn` field
2. **CLI options** (step 3) - Documents `--auto-approve` and `--dry-run` flags
3. **Dependency explanation** (step 5) - Explains how `dependsOn` ordering works
4. **AGENTS.md updates** (step 9) - Notes about pattern discovery

To run locally:
```bash
cd flowchart
npm install
npm run dev
```

## Skills

Two skills are provided for AI tools:

### PRD Skill (`skills/prd/SKILL.md`)
- Triggers on: "create a prd", "write prd for", "plan this feature"
- Asks 3-5 clarifying questions with lettered options
- Outputs: `tasks/prd-[feature-name].md`
- Always include "Verify in browser using dev-browser skill" for UI stories

### Ralph Skill (`skills/ralph/SKILL.md`)
- Triggers on: "convert this prd", "create prd.json from this"
- Converts markdown PRD to JSON format
- Outputs: `tasks/prd.json`
- Archives previous runs when branchName changes

## Patterns

- Each iteration spawns a fresh AI tool instance with clean context
- Memory persists via git history, `progress.txt`, and `prd.json`
- Stories should be small enough to complete in one context window
- Always update AGENTS.md with discovered patterns for future iterations
- Use `dependsOn` to ensure database/API changes happen before UI changes
- Use `--dry-run` to verify story execution order before running
- The `tasks/` directory structure: `prd.json`, `progress.txt`, `archive/`
- OpenCode uses `--model github-copilot/claude-opus-4.5 --agent build` by default

## Auto-Approve Mode

When running in automation (CI/CD), use `--auto-approve` to skip interactive prompts:

- **Amp**: Already uses `--dangerously-allow-all`
- **OpenCode**: Sets `OPENCODE_PERMISSION='"allow"'`
- **Claude Code**: Adds `--dangerously-skip-permissions` flag

**Warning**: This grants the AI full permissions. Only use in trusted environments.
