#!/usr/bin/env python3
"""
Claude Island Hook
- Sends session state to ClaudeIsland.app via Unix socket
- For PermissionRequest: waits for user decision from the app
- For remote (SSH) sessions: tails the local JSONL transcript and ships
  new bytes back over the same socket so the app can mirror the conversation
  to a host-namespaced directory and parse it as if it were local.
"""
import base64
import json
import os
import socket
import sys

SOCKET_PATH = "/tmp/claude-island.sock"
TIMEOUT_SECONDS = 300  # 5 minutes for permission decisions
OFFSET_DIR = os.path.expanduser("~/.claude/.island-offsets")
# Hard cap per chunk to avoid blowing the socket buffer on a giant first sync.
# Anything beyond this is sent in the next hook fire — Claude Code fires hooks
# constantly during a turn so the lag is at most one tool call.
MAX_CHUNK_BYTES = 256 * 1024  # 256 KiB


def get_tty():
    """Get the TTY of the Claude process (parent)"""
    import subprocess

    # Get parent PID (Claude process)
    ppid = os.getppid()

    # Try to get TTY from ps command for the parent process
    try:
        result = subprocess.run(
            ["ps", "-p", str(ppid), "-o", "tty="],
            capture_output=True,
            text=True,
            timeout=2
        )
        tty = result.stdout.strip()
        if tty and tty != "??" and tty != "-":
            # ps returns just "ttys001", we need "/dev/ttys001"
            if not tty.startswith("/dev/"):
                tty = "/dev/" + tty
            return tty
    except Exception:
        pass

    # Fallback: try current process stdin/stdout
    try:
        return os.ttyname(sys.stdin.fileno())
    except (OSError, AttributeError):
        pass
    try:
        return os.ttyname(sys.stdout.fileno())
    except (OSError, AttributeError):
        pass
    return None


def encode_project_dir(cwd):
    """Mirror Claude Code's projects-directory naming: replace '/' and '.' with '-'."""
    return cwd.replace("/", "-").replace(".", "-")


def attach_jsonl_chunk(state, session_id, cwd):
    """
    If a JSONL transcript exists for this session, read any bytes that have
    been written since the last hook fire and attach them to `state` as
    `jsonl_chunk` (base64) + `jsonl_offset`. The Mac side mirrors these into
    its own ~/.claude/projects/<host-namespaced-dir>/<session>.jsonl so the
    existing parser pipeline can read it.

    Offset bookkeeping lives in ~/.claude/.island-offsets/<session_id>.offset.
    File shrinkage (e.g. /clear) resets the stored offset to 0 so the next
    chunk goes back to the beginning.
    """
    if not session_id or session_id == "unknown" or not cwd:
        return

    project_dir = encode_project_dir(cwd)
    jsonl_path = os.path.expanduser(
        f"~/.claude/projects/{project_dir}/{session_id}.jsonl"
    )
    if not os.path.exists(jsonl_path):
        return

    try:
        os.makedirs(OFFSET_DIR, exist_ok=True)
    except OSError:
        return

    offset_path = os.path.join(OFFSET_DIR, f"{session_id}.offset")

    last_offset = 0
    if os.path.exists(offset_path):
        try:
            with open(offset_path) as f:
                last_offset = int((f.read() or "0").strip() or 0)
        except (OSError, ValueError):
            last_offset = 0

    try:
        file_size = os.path.getsize(jsonl_path)
    except OSError:
        return

    # File shrunk — likely a /clear that rewrote the transcript. Resync from
    # the start so the mirror gets the new (smaller) contents.
    if file_size < last_offset:
        last_offset = 0

    if file_size == last_offset:
        return  # nothing new since last fire

    # Cap the chunk; the rest streams in on the next hook fire.
    bytes_to_read = min(file_size - last_offset, MAX_CHUNK_BYTES)

    try:
        with open(jsonl_path, "rb") as f:
            f.seek(last_offset)
            new_bytes = f.read(bytes_to_read)
    except OSError:
        return

    if not new_bytes:
        return

    state["jsonl_chunk"] = base64.b64encode(new_bytes).decode("ascii")
    state["jsonl_offset"] = last_offset

    new_offset = last_offset + len(new_bytes)
    try:
        # Atomic-ish: write to temp + rename so a crash mid-write doesn't
        # leave a half-written offset file that future runs can't parse.
        tmp_path = offset_path + ".tmp"
        with open(tmp_path, "w") as f:
            f.write(str(new_offset))
        os.rename(tmp_path, offset_path)
    except OSError:
        pass


def send_event(state):
    """Send event to app, return response if any"""
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(TIMEOUT_SECONDS)
        sock.connect(SOCKET_PATH)
        sock.sendall(json.dumps(state).encode())

        # For permission requests, wait for response
        if state.get("status") == "waiting_for_approval":
            response = sock.recv(4096)
            sock.close()
            if response:
                return json.loads(response.decode())
        else:
            sock.close()

        return None
    except (socket.error, OSError, json.JSONDecodeError):
        return None


def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(1)

    session_id = data.get("session_id", "unknown")
    event = data.get("hook_event_name", "")
    cwd = data.get("cwd", "")
    tool_input = data.get("tool_input", {})

    # Get process info
    claude_pid = os.getppid()
    tty = get_tty()
    hostname = socket.gethostname()

    # Build state object
    state = {
        "session_id": session_id,
        "cwd": cwd,
        "event": event,
        "pid": claude_pid,
        "tty": tty,
        "hostname": hostname,
    }

    # Map events to status
    if event == "UserPromptSubmit":
        # User just sent a message - Claude is now processing
        state["status"] = "processing"

    elif event == "PreToolUse":
        state["status"] = "running_tool"
        state["tool"] = data.get("tool_name")
        state["tool_input"] = tool_input
        # Send tool_use_id to Swift for caching
        tool_use_id_from_event = data.get("tool_use_id")
        if tool_use_id_from_event:
            state["tool_use_id"] = tool_use_id_from_event

    elif event == "PostToolUse":
        state["status"] = "processing"
        state["tool"] = data.get("tool_name")
        state["tool_input"] = tool_input
        # Send tool_use_id so Swift can cancel the specific pending permission
        tool_use_id_from_event = data.get("tool_use_id")
        if tool_use_id_from_event:
            state["tool_use_id"] = tool_use_id_from_event

    elif event == "PermissionRequest":
        # This is where we can control the permission
        state["status"] = "waiting_for_approval"
        state["tool"] = data.get("tool_name")
        state["tool_input"] = tool_input
        # tool_use_id lookup handled by Swift-side cache from PreToolUse

        # Send to app and wait for decision
        response = send_event(state)

        if response:
            decision = response.get("decision", "ask")
            reason = response.get("reason", "")

            if decision == "allow":
                # Output JSON to approve
                output = {
                    "hookSpecificOutput": {
                        "hookEventName": "PermissionRequest",
                        "decision": {"behavior": "allow"},
                    }
                }
                print(json.dumps(output))
                sys.exit(0)

            elif decision == "deny":
                # Output JSON to deny
                output = {
                    "hookSpecificOutput": {
                        "hookEventName": "PermissionRequest",
                        "decision": {
                            "behavior": "deny",
                            "message": reason or "Denied by user via ClaudeIsland",
                        },
                    }
                }
                print(json.dumps(output))
                sys.exit(0)

        # No response or "ask" - let Claude Code show its normal UI
        sys.exit(0)

    elif event == "Notification":
        notification_type = data.get("notification_type")
        # Skip permission_prompt - PermissionRequest hook handles this with better info
        if notification_type == "permission_prompt":
            sys.exit(0)
        elif notification_type == "idle_prompt":
            state["status"] = "waiting_for_input"
        else:
            state["status"] = "notification"
        state["notification_type"] = notification_type
        state["message"] = data.get("message")

    elif event == "Stop":
        state["status"] = "waiting_for_input"

    elif event == "SubagentStop":
        # SubagentStop fires when a subagent completes - usually means back to waiting
        state["status"] = "waiting_for_input"

    elif event == "SessionStart":
        # New session starts waiting for user input
        state["status"] = "waiting_for_input"

    elif event == "SessionEnd":
        state["status"] = "ended"

    elif event == "PreCompact":
        # Context is being compacted (manual or auto)
        state["status"] = "compacting"

    else:
        state["status"] = "unknown"

    # For events that signal new transcript content, ferry the JSONL delta back
    # to the app so remote (SSH) sessions get assistant text and user prompts
    # mirrored locally. The Mac side checks `hostname` and ignores chunks for
    # events that originate on the same machine as the app, so this is safe to
    # call unconditionally — it's effectively a no-op locally.
    if event in (
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "Stop",
        "SubagentStop",
        "PreCompact",
    ):
        attach_jsonl_chunk(state, session_id, cwd)

    # Send to socket (fire and forget for non-permission events)
    send_event(state)


if __name__ == "__main__":
    main()
