#!/bin/sh
set -eu

DEFAULT_REPO_URL="https://github.com/HoChiPants/token-bar.git"
REPO_URL="${TOKEN_BAR_REPO:-$DEFAULT_REPO_URL}"
INSTALL_ROOT="${TOKEN_BAR_INSTALL_ROOT:-$HOME/.local/share/token-bar}"
APP_TARGET_DIR="${TOKEN_BAR_APP_DIR:-$HOME/Applications}"
BIN_TARGET_DIR="${TOKEN_BAR_BIN_DIR:-$HOME/.local/bin}"
SHOULD_OPEN="${TOKEN_BAR_OPEN:-1}"

if [ -z "${TOKEN_BAR_REPO+x}" ] && [ -f "Package.swift" ] && [ -d "Sources/TokenBar" ]; then
  REPO_URL=$(pwd)
fi

if printf "%s" "$REPO_URL" | grep -q "YOUR_GITHUB_USER"; then
  if [ -f "Package.swift" ] && [ -d "Sources/TokenBar" ]; then
    REPO_URL=$(pwd)
  else
    echo "Set TOKEN_BAR_REPO to your public repo URL first." >&2
    echo "Example:" >&2
    echo "  TOKEN_BAR_REPO=https://github.com/you/token-bar.git sh Scripts/bootstrap.sh" >&2
    exit 64
  fi
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git is required." >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift/Xcode command line tools are required." >&2
  echo "Install Xcode from the App Store or run: xcode-select --install" >&2
  exit 1
fi

mkdir -p "$(dirname "$INSTALL_ROOT")"

if [ -d "$INSTALL_ROOT/.git" ]; then
  echo "Updating Token Bar..."
  git -C "$INSTALL_ROOT" pull --ff-only
else
  echo "Cloning Token Bar..."
  rm -rf "$INSTALL_ROOT"
  git clone "$REPO_URL" "$INSTALL_ROOT"
fi

cd "$INSTALL_ROOT"

echo "Building Token Bar..."
Scripts/install.sh

mkdir -p "$APP_TARGET_DIR" "$BIN_TARGET_DIR"
rm -rf "$APP_TARGET_DIR/Token Bar.app"
cp -R "dist/Token Bar.app" "$APP_TARGET_DIR/Token Bar.app"

ln -sf "$APP_TARGET_DIR/Token Bar.app/Contents/MacOS/tokenbar-cli" "$BIN_TARGET_DIR/tokenbar"

echo "Installed app: $APP_TARGET_DIR/Token Bar.app"
echo "Installed CLI: $BIN_TARGET_DIR/tokenbar"

if ! printf "%s" "$PATH" | tr ':' '\n' | grep -qx "$BIN_TARGET_DIR"; then
  echo
  echo "Add this to your shell profile if tokenbar is not found:"
  echo "  export PATH=\"$BIN_TARGET_DIR:\$PATH\""
fi

if [ "$SHOULD_OPEN" != "0" ]; then
  open "$APP_TARGET_DIR/Token Bar.app"
  echo "Token Bar is running."
fi
