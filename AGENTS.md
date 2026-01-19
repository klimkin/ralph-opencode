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
./ralph.sh [max_iterations] [tool]

# Examples:
./ralph.sh 10 amp      # Use Amp
./ralph.sh 10 opencode # Use Opencode (default)
./ralph.sh 10 claude   # Use Claude Code

# Or via environment variable:
RALPH_TOOL=claude ./ralph.sh 10
```

## Key Files

- `ralph.sh` - The bash loop that spawns fresh AI tool instances
- `ralph.ps1` - PowerShell version for Windows
- `prompt.md` - Instructions given to each AI tool instance
- `prd.json.example` - Example PRD format
- `flowchart/` - Interactive React Flow diagram explaining how Ralph works

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
