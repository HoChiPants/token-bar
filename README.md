# Token Bar

Token Bar is a small macOS menu bar utility for Codex usage. It reads local Codex session logs from `~/.codex/sessions` and shows the latest Codex 5-hour and weekly rate-window usage in the menu bar.

The menu also includes local token totals for the last 5 hours and 7 days, the latest Codex session total, reset times, and a manual refresh action.

## Run During Development

```sh
swift run TokenBar
```

## Build A macOS App

```sh
chmod +x Scripts/install.sh
Scripts/install.sh
open "dist/Token Bar.app"
```

The app is an `LSUIElement` menu bar app, so it appears in the macOS top bar without a Dock icon.

## Data Source

Codex emits `token_count` events into local JSONL rollout files. Token Bar does not need an API key and does not send data anywhere. It only reads local files under:

```text
~/.codex/sessions
~/.codex/archived_sessions
```
