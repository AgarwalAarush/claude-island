#!/bin/bash
# install-remote-hooks.sh — Install claude-island hooks on a remote SSH host
#
# Usage: ./scripts/install-remote-hooks.sh <ssh-host>
# Example: ./scripts/install-remote-hooks.sh babel
#
# What it does:
#   1. Creates ~/.claude/hooks/ on the remote
#   2. Copies claude-island-state.py to the remote
#   3. Merges hook entries into remote ~/.claude/settings.json (idempotent)
#
# Prerequisites:
#   - SSH access to the target host (configured in ~/.ssh/config)
#   - RemoteForward /tmp/claude-island.sock /tmp/claude-island.sock in SSH config
#   - Claude Code installed on the remote machine
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
HOOK_SCRIPT="$PROJECT_DIR/ClaudeIsland/Resources/claude-island-state.py"

usage() {
    echo "Usage: $0 <ssh-host>"
    echo ""
    echo "Known hosts: babel, falcon, jetson-orin, old_raspi, raspi, desktop"
    exit 1
}

[[ $# -ne 1 ]] && usage
HOST="$1"

if [[ ! -f "$HOOK_SCRIPT" ]]; then
    echo "Error: hook script not found at $HOOK_SCRIPT" >&2
    exit 1
fi

echo "=== Installing claude-island hooks on $HOST ==="
echo ""

# 1. Create hook directory on remote
echo "→ Creating ~/.claude/hooks/ ..."
ssh "$HOST" 'mkdir -p ~/.claude/hooks'

# 2. Copy the Python hook script
echo "→ Copying claude-island-state.py ..."
scp -q "$HOOK_SCRIPT" "$HOST:~/.claude/hooks/claude-island-state.py"
ssh "$HOST" 'chmod 755 ~/.claude/hooks/claude-island-state.py'

# 3. Detect python3 on remote
PYTHON=$(ssh "$HOST" 'which python3 2>/dev/null || which python 2>/dev/null || echo python3')
echo "→ Using Python: $PYTHON"

# 4. Merge hook entries into remote ~/.claude/settings.json
echo "→ Updating ~/.claude/settings.json ..."
ssh "$HOST" "$PYTHON" << PYEOF
import json
import os

settings_path = os.path.expanduser("~/.claude/settings.json")
cmd = "$PYTHON ~/.claude/hooks/claude-island-state.py"

entry            = [{"type": "command", "command": cmd}]
entry_long       = [{"type": "command", "command": cmd, "timeout": 86400}]
with_matcher     = [{"matcher": "*", "hooks": entry}]
with_matcher_long= [{"matcher": "*", "hooks": entry_long}]
without_matcher  = [{"hooks": entry}]
pre_compact      = [{"matcher": "auto",   "hooks": entry},
                    {"matcher": "manual", "hooks": entry}]

hook_events = {
    "UserPromptSubmit":  without_matcher,
    "PreToolUse":        with_matcher,
    "PostToolUse":       with_matcher,
    "PermissionRequest": with_matcher_long,
    "Notification":      with_matcher,
    "Stop":              without_matcher,
    "SubagentStop":      without_matcher,
    "SessionStart":      without_matcher,
    "SessionEnd":        without_matcher,
    "PreCompact":        pre_compact,
}

existing = {}
if os.path.exists(settings_path):
    try:
        with open(settings_path) as f:
            existing = json.load(f)
    except (json.JSONDecodeError, IOError):
        pass

hooks = existing.get("hooks", {})

for event, config in hook_events.items():
    existing_entries = hooks.get(event, [])
    # Idempotent: skip if our hook is already present
    has_our_hook = any(
        "claude-island-state.py" in h.get("command", "")
        for entry in existing_entries
        for h in entry.get("hooks", [])
    )
    if not has_our_hook:
        hooks[event] = existing_entries + config

existing["hooks"] = hooks

with open(settings_path, "w") as f:
    json.dump(existing, f, indent=2, sort_keys=True)
    f.write("\n")

print("  settings.json updated")
PYEOF

echo ""
echo "=== Done! ==="
echo ""
echo "To use:"
echo "  1. Make sure Claude Island is running on your Mac"
echo "  2. SSH to $HOST (RemoteForward will auto-activate)"
echo "  3. Run 'claude' in any project directory"
echo "  4. The session will appear in Claude Island with a network indicator"
echo ""
echo "Verify the tunnel is active on the remote:"
echo "  ssh $HOST 'ls -la /tmp/claude-island.sock'"
