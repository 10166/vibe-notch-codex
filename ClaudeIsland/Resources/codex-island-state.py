#!/usr/bin/env python3
"""
Vibe Notch Codex Hook
- Adapts Codex CLI hook payloads to the existing app socket state format.
- Keeps permission decisions synchronous when Codex asks the app.
"""
import json
import os
import socket
import sys

SOCKET_PATH = "/tmp/claude-island.sock"
TIMEOUT_SECONDS = 300
CONTROL_CODEX_PERMISSIONS = os.environ.get("VIBE_NOTCH_CODEX_PERMISSION_CONTROL") == "1"


def get_tty():
    ppid = os.getppid()
    try:
        import subprocess

        result = subprocess.run(
            ["ps", "-p", str(ppid), "-o", "tty="],
            capture_output=True,
            text=True,
            timeout=2,
        )
        tty = result.stdout.strip()
        if tty and tty != "??" and tty != "-":
            return tty if tty.startswith("/dev/") else "/dev/" + tty
    except Exception:
        pass

    for stream in (sys.stdin, sys.stdout):
        try:
            return os.ttyname(stream.fileno())
        except (OSError, AttributeError):
            pass
    return None


def send_event(state, wait_for_response=None):
    if wait_for_response is None:
        wait_for_response = state.get("status") == "waiting_for_approval"

    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(TIMEOUT_SECONDS)
        sock.connect(SOCKET_PATH)
        sock.sendall(json.dumps(state).encode())

        if wait_for_response:
            response = sock.recv(4096)
            sock.close()
            if response:
                return json.loads(response.decode())
        else:
            sock.close()
    except (socket.error, OSError, json.JSONDecodeError):
        return None
    return None


def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(1)

    event = data.get("hook_event_name", "")
    state = {
        "session_id": data.get("session_id", "unknown"),
        "cwd": data.get("cwd", ""),
        "event": event,
        "agent": "codex",
        "pid": os.getppid(),
        "tty": get_tty(),
        "transcript_path": data.get("transcript_path"),
    }

    tool_input = data.get("tool_input") or {}

    if event == "SessionStart":
        state["status"] = "waiting_for_input"

    elif event == "UserPromptSubmit":
        state["status"] = "processing"

    elif event == "PreToolUse":
        state["status"] = "running_tool"
        state["tool"] = data.get("tool_name")
        state["tool_input"] = tool_input
        if data.get("tool_use_id"):
            state["tool_use_id"] = data.get("tool_use_id")

    elif event == "PermissionRequest":
        state["status"] = "waiting_for_approval" if CONTROL_CODEX_PERMISSIONS else "processing"
        state["tool"] = data.get("tool_name")
        state["tool_input"] = tool_input
        if data.get("tool_use_id"):
            state["tool_use_id"] = data.get("tool_use_id")

        response = send_event(state, wait_for_response=CONTROL_CODEX_PERMISSIONS)
        if response:
            decision = response.get("decision", "ask")
            reason = response.get("reason", "")
            if decision == "allow":
                print(json.dumps({
                    "hookSpecificOutput": {
                        "hookEventName": "PermissionRequest",
                        "decision": {"behavior": "allow"},
                    }
                }))
                sys.exit(0)
            if decision == "deny":
                print(json.dumps({
                    "hookSpecificOutput": {
                        "hookEventName": "PermissionRequest",
                        "decision": {
                            "behavior": "deny",
                            "message": reason or "Denied by user via Vibe Notch",
                        },
                    }
                }))
                sys.exit(0)
        sys.exit(0)

    elif event == "PostToolUse":
        state["status"] = "processing"
        state["tool"] = data.get("tool_name")
        state["tool_input"] = tool_input
        if data.get("tool_use_id"):
            state["tool_use_id"] = data.get("tool_use_id")

    elif event == "Stop":
        state["status"] = "waiting_for_input"
        if data.get("last_assistant_message"):
            state["message"] = data.get("last_assistant_message")

    else:
        state["status"] = "processing"

    send_event(state)


if __name__ == "__main__":
    main()
