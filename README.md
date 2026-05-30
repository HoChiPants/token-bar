# Token Bar

Token Bar is a small macOS menu bar utility for Codex usage. It reads local Codex session logs from `~/.codex/sessions` and shows the latest Codex 5-hour and weekly rate-window usage in the menu bar.

The menu also includes local token totals for the last 5 hours and 7 days, the latest Codex session total, reset times, and a manual refresh action.

From the menu you can choose how the usage appears in the macOS menu bar:

- Compact text: `5h 24% W 5%`
- Donut: a thin ring with the 5-hour percent inside
- Progress bar: a left-to-right fill meter with the 5-hour percent inside

You can also switch the weekly label between short, long, or hidden, and hide reset-time rows when you want a quieter menu.

## Quick Install From GitHub

After this repo is public, the easiest install path is the bootstrap script. Replace `YOUR_GITHUB_USER` with the GitHub owner for the public repo:

```sh
TOKEN_BAR_REPO=https://github.com/YOUR_GITHUB_USER/token-bar.git \
  /bin/sh -c "$(curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USER/token-bar/main/Scripts/bootstrap.sh)"
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
   git remote add origin git@github.com:YOUR_GITHUB_USER/token-bar.git
   git push -u origin main
   ```

3. In this README and [Scripts/bootstrap.sh](Scripts/bootstrap.sh), replace `YOUR_GITHUB_USER` with the actual GitHub owner.
4. Commit and push that replacement.
5. Share the Quick Install command above.

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
