# Token Bar

Token Bar is a small macOS menu bar utility for Codex usage. It reads local Codex session logs from `~/.codex/sessions` and shows the latest Codex 5-hour and weekly rate-window usage in the menu bar.

The menu also includes local token totals for the last 5 hours and 7 days, the latest Codex session total, reset times, and a manual refresh action.

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

## Homebrew Packaging

This repo includes starter templates for both install styles:

- [Homebrew/Casks/token-bar.rb](Homebrew/Casks/token-bar.rb) installs the macOS app.
- [Homebrew/Formula/tokenbar.rb](Homebrew/Formula/tokenbar.rb) installs the CLI.

Before publishing, replace `YOUR_GITHUB_USER` and the placeholder SHA values in those files.

### Release The App Cask

1. Create a GitHub repo named `token-bar` and add it as `origin`.
2. Commit the code, tag a release, and push it:

   ```sh
   git tag v0.1.0
   git push origin main --tags
   ```

3. Build the release zip:

   ```sh
   Scripts/release.sh 0.1.0
   ```

4. Upload `dist/TokenBar-0.1.0.zip` to the GitHub release for `v0.1.0`.
5. Copy the printed zip SHA into `Homebrew/Casks/token-bar.rb`.
6. Put the cask file in a tap repo, usually `homebrew-token-bar`.

Users can then install with:

```sh
brew tap YOUR_GITHUB_USER/token-bar
brew install --cask token-bar
open -a "Token Bar"
tokenbar status
```

### Release The CLI Formula

After the GitHub tag exists, compute the source tarball SHA:

```sh
curl -L https://github.com/YOUR_GITHUB_USER/token-bar/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256
```

Copy that SHA into [Homebrew/Formula/tokenbar.rb](Homebrew/Formula/tokenbar.rb), then publish it in the same tap.

Users can then install with:

```sh
brew tap YOUR_GITHUB_USER/token-bar
brew install tokenbar
tokenbar status
tokenbar launch
```
