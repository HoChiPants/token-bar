# Token Bar

Token Bar is a small macOS menu bar utility for Codex usage. It reads local Codex session logs from `~/.codex/sessions` and shows the latest Codex 5-hour and weekly rate-window usage in the menu bar.

The menu also includes local token totals for the last 5 hours and 7 days, the latest Codex session total, reset times, and a manual refresh action.

From the menu you can choose how the usage appears in the macOS menu bar:

- Compact text: `5h 24% W 5%`
- Donut: one or two thin rings with the selected percent inside
- Progress bar: one filled meter or two stacked meters with the selected percent inside

You can also choose which usage window appears in any style: 5-hour, week, or both. Weekly labels can be short (`W`) or long (`Week`), and reset-time rows can be hidden when you want a quieter menu.

Detailed totals, reset times, and scan counts live under the `Info` submenu so the main menu stays focused on display controls.

## Quick Install From GitHub

After this repo is public, the easiest install path is the bootstrap script:

```sh
TOKEN_BAR_REPO=https://github.com/HoChiPants/token-bar.git \
  /bin/sh -c "$(curl -fsSL https://raw.githubusercontent.com/HoChiPants/token-bar/main/Scripts/bootstrap.sh)"
```

That script:

- clones or updates Token Bar in `~/.local/share/token-bar`
- builds the app from source
- installs `Token Bar.app` into `~/Applications`
- adds a `tokenbar` CLI symlink in `~/.local/bin`
- opens the menu bar app

If `tokenbar` is not found after install, add this to your shell profile:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

## Run During Development

```sh
swift run TokenBar
```

The companion CLI can inspect the same local Codex data without opening the menu bar app:

```sh
swift run tokenbar-cli status
swift run tokenbar-cli json
swift run tokenbar-cli auth
swift run tokenbar-cli doctor
swift run tokenbar-cli launch
```

## Build A macOS App

```sh
chmod +x Scripts/install.sh
Scripts/install.sh
open "dist/Token Bar.app"
```

The app is an `LSUIElement` menu bar app, so it appears in the macOS top bar without a Dock icon.

## Install Locally From A Clone

If you already cloned the repo:

```sh
Scripts/bootstrap.sh
```

For a local-only run before the repo URL is public:

```sh
TOKEN_BAR_REPO="$(pwd)" Scripts/bootstrap.sh
```

## Publish As A Public Repo

1. Create a public GitHub repo named `token-bar`.
2. Add it as this repo's remote:

   ```sh
   git remote add origin git@github.com:HoChiPants/token-bar.git
   git push -u origin main
   ```

3. Share the Quick Install command above.

## Data Source

Codex emits `token_count` events into local JSONL rollout files. Token Bar does not need an API key and does not send data anywhere. It only reads local files under:

```text
~/.codex/sessions
~/.codex/archived_sessions
```

## Codex Authentication

Token Bar does not read or store Codex credentials. The intended flow is:

1. Sign in through Codex normally.
2. Use Codex enough for it to emit local `token_count` events.
3. Run Token Bar, which reads those local events.

That means the app is effectively authenticated by the presence of a working Codex install, without touching `~/.codex/auth.json` or macOS Keychain entries.

You can check that state from the CLI:

```sh
tokenbar auth
```
