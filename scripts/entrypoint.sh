#!/bin/bash
set -e

# Prevent nested Claude Code detection
unset CLAUDECODE

# Kill any stale tmux sessions from previous runs
tmux -L loom kill-server 2>/dev/null || true

# Auth status check
echo "=== Loom Airlock ==="

if [ -n "$ANTHROPIC_API_KEY" ]; then
    echo "[ok] Anthropic API key set"
else
    echo "[!!] ANTHROPIC_API_KEY not set - run: export ANTHROPIC_API_KEY=..."
fi

if gh auth status &>/dev/null; then
    echo "[ok] GitHub authenticated as $(gh api user --jq .login 2>/dev/null || echo 'unknown')"
else
    echo "[!!] GitHub not authenticated - run: gh auth login"
fi

echo "===================="
echo ""
echo "Quick start:"
echo "  ./.loom/scripts/loom-daemon.sh --merge    # full autonomous mode"
echo "  claude                                     # interactive session"
echo ""

exec "$@"
