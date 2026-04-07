#!/bin/bash
# install-remote-hooks.sh — Install claude-island hooks on a remote SSH host
#
# Usage: ./install-remote-hooks.sh <ssh-host>
# Example: ./install-remote-hooks.sh falcon
#
# Designed to be called automatically via SSH LocalCommand on first connect,
# or manually for a forced reinstall (delete ~/.ssh/.ci-hooks-<host> to retry).
set -euo pipefail

[[ $# -ne 1 ]] && { echo "Usage: $0 <ssh-host>"; exit 1; }
HOST="$1"

# Source the locally-installed hook script (HookInstaller keeps this up to date)
HOOK_SCRIPT="$HOME/.claude/hooks/claude-island-state.py"

if [[ ! -f "$HOOK_SCRIPT" ]]; then
    echo "Error: $HOOK_SCRIPT not found — is Claude Island running?" >&2
    exit 1
fi

# Detect python3 on remote
PYTHON=$(ssh "$HOST" 'which python3 2>/dev/null || which python 2>/dev/null || echo python3')

ssh "$HOST" 'mkdir -p ~/.claude/hooks'
scp -q "$HOOK_SCRIPT" "$HOST:~/.claude/hooks/claude-island-state.py"
ssh "$HOST" 'chmod 755 ~/.claude/hooks/claude-island-state.py'

ssh "$HOST" "$PYTHON" << PYEOF
import json, os
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
        with open(settings_path) as f: existing = json.load(f)
    except: pass
hooks = existing.get("hooks", {})
for event, config in hook_events.items():
    entries = hooks.get(event, [])
    has_ours = any("claude-island-state.py" in h.get("command","")
                   for e in entries for h in e.get("hooks",[]))
    if not has_ours: hooks[event] = entries + config
existing["hooks"] = hooks
with open(settings_path, "w") as f: json.dump(existing, f, indent=2, sort_keys=True); f.write("\n")
PYEOF
