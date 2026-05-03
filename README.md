<div align="center">
  <img src="ClaudeIsland/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Logo" width="100" height="100">
  <h3 align="center">Vibe Notch (previously Claude Island)</h3>
  <p align="center">
    A macOS menu bar app that brings Dynamic Island-style notifications to Claude Code and Codex CLI sessions.
    <br />
    <br />
    <a href="https://github.com/10166/vibe-notch-codex/releases/latest" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/github/v/release/10166/vibe-notch-codex?style=rounded&color=white&labelColor=000000&label=release" alt="Release Version" />
    </a>
    <a href="https://github.com/10166/vibe-notch-codex/releases/latest" target="_blank" rel="noopener noreferrer">
      <img alt="GitHub Downloads" src="https://img.shields.io/github/downloads/10166/vibe-notch-codex/total?style=rounded&color=white&labelColor=000000">
    </a>
  </p>
</div>

> **Actively maintained**
>
> Vibe Notch now supports both Claude Code and Codex CLI sessions, including local usage analytics and API quota visibility for both providers.

## Features

- **Notch UI** — Animated overlay that expands from the MacBook notch
- **Live Session Monitoring** — Track multiple Claude Code and Codex CLI sessions in real-time
- **Claude Permission Approvals** — Approve or deny Claude Code tool executions directly from the notch
- **Codex Session Hooks** — Detect Codex session start, prompt, tool, permission, and stop events without taking over Codex's native approval prompt
- **Chat History** — View full conversation history with markdown rendering
- **Usage Heatmap** — Review local Claude Code and Codex CLI token, cost, and session activity over 12 weeks, 6 months, or 1 year
- **API Quota Dashboard** — Check Claude Code and Codex CLI quota windows, reset timing, account identity, and credit balances when available
- **Auto-Setup** — Claude and Codex hooks install automatically on first launch and can be toggled from the menu

## Requirements

- macOS 15.6+
- Claude Code CLI and/or Codex CLI
- Python 3 for hook scripts

## Install

Download the latest release or build from source:

```bash
xcodebuild -scheme ClaudeIsland -configuration Release build
```

## Using Vibe Notch

Launch the app, then open the notch menu to configure display, sound, launch-at-login, hooks, and accessibility access. The app discovers active Claude Code and Codex CLI sessions and shows them in the main instances view.

The menu also includes:

- **Usage** — Local token, estimated cost, and session analytics by agent and time range
- **API Quota** — Claude Code and Codex CLI quota windows with manual refresh
- **Hooks** — Enable or remove the installed Claude and Codex hook scripts

## How It Works

Vibe Notch installs Claude Code hooks into the resolved Claude config directory. It supports `CLAUDE_CONFIG_DIR`, the newer `~/.config/claude/` layout, and the legacy `~/.claude/` fallback. The hook script communicates session state to the app through a Unix socket.

For Codex CLI, Vibe Notch:

- reads session logs from `~/.codex/sessions/` or `CODEX_HOME/sessions`
- installs `codex-island-state.py` into `~/.codex/hooks/` or `CODEX_HOME/hooks`
- updates `hooks.json` for `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, and `Stop`
- enables `codex_hooks = true` in `config.toml`

When Claude needs permission to run a tool, the notch expands with approve/deny buttons, so you do not need to switch to the terminal. Codex permission requests are surfaced in the notch, but the final approval remains in Codex's native prompt.

## Usage Analytics

The Usage view scans local Claude Code and Codex CLI JSONL logs into a small SQLite cache at `~/Library/Application Support/Vibe Notch/usage.sqlite`. It stores aggregate session metadata, token counts, estimated cost, model, agent, and hashed paths. Conversation content is not stored in the analytics cache.

Cost values are estimates based on the local model pricing table and may differ from provider billing.

## API Quota

The API Quota view fetches live quota snapshots for both providers when opened and refreshes every 10 minutes while active:

- **Claude Code** — reads OAuth credentials from the resolved Claude config directory and calls Anthropic's OAuth usage endpoint
- **Codex CLI** — prefers the Codex CLI JSON-RPC rate-limit API, then falls back to ChatGPT OAuth usage data from `auth.json`

If credentials are missing, expired, or unavailable, the dashboard shows the provider-specific error instead of blocking the rest of the app.

## Development

Run the app from Xcode with the `ClaudeIsland` scheme, or build from the terminal:

```bash
xcodebuild -scheme ClaudeIsland -configuration Debug build
```

Run the unit tests:

```bash
xcodebuild test -scheme ClaudeIsland
```

## Analytics

Vibe Notch uses Mixpanel to collect anonymous usage data:

- **App Launched** — App version, build number, macOS version
- **Session Started** — When a new Claude Code or Codex CLI session is detected

No personal data or conversation content is collected.

## License

Apache 2.0
