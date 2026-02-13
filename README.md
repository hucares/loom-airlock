# Loom Airlock

Sandboxed Docker environment for running [Loom](https://github.com/rjwalters/loom) autonomous development daemons. Isolates agent activity so nothing can blow up your host machine.

## Why This Exists

Loom orchestrates multiple Claude Code instances via tmux to autonomously implement features, review PRs, and merge code. Running this on bare metal is risky — agents run with `--dangerously-skip-permissions` and can execute arbitrary shell commands. The airlock contains the blast radius.

## Prerequisites

Docker Desktop must be running before any `make` commands will work:

```bash
open -a Docker               # macOS — start Docker Desktop
```

## Quick Start

```bash
# First-time setup
cp env.example .env          # Add your ANTHROPIC_API_KEY
make create                  # Build image + create persistent container
make auth                    # Open shell to authenticate (once)

# Inside the auth shell:
claude /login                # Authenticate Claude Code
gh auth login                # Authenticate GitHub
exit                         # Back to host

# Daily use
make run                     # Start container + launch daemon
```

## Commands

| Command | What it does |
|---------|-------------|
| `make build` | Build the Docker image |
| `make create` | Create persistent container (run once) |
| `make start` | Start and attach to container |
| `make stop` | Stop the container |
| `make attach` | Reattach to running container |
| `make shell` | Open second shell into running container |
| `make auth` | Open shell to authenticate Claude Code and GitHub (first-time) |
| `make run` | Start container and launch daemon |
| `make daemon` | Start Loom daemon from outside the container |
| `make logs` | Tail shepherd logs |
| `make status` | Check container status |
| `make clean` | Remove container (keeps image) |
| `make nuke` | Remove everything |

Override the workspace: `make create WORKSPACE=~/Projects/my-repo`

## Loom Architecture

```
Layer 3: Human          — You. Watch, intervene, override.
Layer 2: /loom daemon   — System orchestrator. Generates work, scales shepherds.
Layer 1: /shepherd      — Per-issue orchestrator. Lifecycle from issue to merge.
Layer 0: /builder, etc. — Single-task workers. Build, review, curate.
```

The daemon spawns agents into tmux sessions. Each agent is a separate Claude Code process running a specialized role.

### Agent Roles

| Role | What it does | Mode |
|------|-------------|------|
| **Shepherd** | Orchestrates one issue end-to-end (curate → build → review → fix → merge) | Per-issue |
| **Builder** | Implements features and fixes in git worktrees | Per-task |
| **Judge** | Reviews PRs, approves or requests changes | Polling |
| **Champion** | Evaluates proposals, auto-merges approved PRs | Polling |
| **Curator** | Enhances issue descriptions with technical details | Polling |
| **Architect** | Creates architectural proposals for new features | Polling |
| **Hermit** | Identifies simplification and cleanup opportunities | Polling |
| **Doctor** | Fixes bugs, resolves merge conflicts, addresses PR feedback | Polling |
| **Guide** | Prioritizes and triages the issue backlog | Polling |
| **Auditor** | Validates main branch build and runtime health | Polling |

### Label-Based Coordination

Agents coordinate via GitHub labels — no database, no message queue. The lifecycle:

```
Issue created
  → loom:curating (Curator picks it up)
  → loom:curated (Curator done)
  → loom:issue (Champion approves, ready for work)
  → loom:building (Shepherd/Builder claims it)
  → PR created with loom:review-requested
  → loom:pr (Judge approves)
  → Auto-merged by Champion
```

### Daemon Modes

- **Normal**: `loom-daemon.sh` — proposals require human approval via Champion
- **Merge**: `loom-daemon.sh --merge` — auto-promotes proposals, auto-merges after Judge approval

### How to Feed It Work

1. **Create GitHub issues** describing features you want
2. The Curator enhances them, Champion promotes to `loom:issue`
3. Shepherds pick them up and drive implementation

Or let the Architect generate proposals autonomously — the daemon triggers it periodically.

## Critical Gotchas

### Nested Claude Code sessions
Claude Code refuses to launch inside another Claude Code session. The `CLAUDECODE` env var must be unset. The entrypoint handles this, but if you're debugging manually inside the container, run `unset CLAUDECODE` first.

### Bypass permissions prompt
`--dangerously-skip-permissions` shows an interactive confirmation dialog. The env var `CLAUDE_BYPASS_PERMISSIONS_ACCEPTED=1` must be set to skip it. Already set in the Dockerfile.

### Stale tmux sessions
If agents crash, tmux sessions linger with no Claude process inside. The daemon detects this and recycles them, but if things get stuck:
```bash
tmux -L loom kill-server    # Nuclear option: kill all sessions
tmux -L loom list-sessions  # Check what's running
```

### CI must pass
The daemon warns on `ci_failing` and may block merges. Check with:
```bash
gh run list --limit 5
```

### Authentication
- **Claude Code**: Run `claude /login` inside the container to authenticate via OAuth (opens a browser URL to copy). Alternatively, set `ANTHROPIC_API_KEY` in `.env` to skip interactive auth. Credentials persist at `/root/.claude/` (mounted from host via `~/.claude`).
- **GitHub**: Run `gh auth login` once inside the container. Credentials persist at `/root/.config/gh/` (mounted from host via `~/.config/gh`).
- **API Key**: Set `ANTHROPIC_API_KEY` in `.env` for headless/daemon usage.

### Worktrees
Builders work in git worktrees at `.loom/worktrees/issue-N`. These are isolated copies of the repo so multiple agents can work on different issues simultaneously. Always use `./.loom/scripts/worktree.sh <issue>` — never run `git worktree` directly.

### Graceful shutdown
```bash
touch .loom/stop-daemon     # Daemon stops after current iteration
```

### Monitoring
```bash
# Attach to any agent's terminal
tmux -L loom attach -t loom-shepherd-1
tmux -L loom attach -t loom-judge

# Tail logs
tail -f .loom/logs/loom-shepherd-1.log

# Check daemon state
cat .loom/daemon-state.json | jq .
```

## Workspace Layout

The container mounts your repo at `/workspace`. Loom adds:

```
/workspace/
├── .loom/
│   ├── config.json            # Terminal/role configuration
│   ├── daemon-state.json      # Current daemon state
│   ├── logs/                  # Agent log files
│   ├── progress/              # Shepherd milestone tracking
│   ├── roles/                 # Role definitions (markdown)
│   ├── scripts/               # Orchestration scripts
│   ├── worktrees/             # Git worktrees for builders
│   └── stop-daemon            # Touch to trigger shutdown
├── .claude/
│   ├── commands/              # Slash commands (/builder, /judge, etc.)
│   └── settings.json          # Tool permissions
└── .github/
    ├── labels.yml             # Label definitions
    └── workflows/             # CI workflows
```
