#!/bin/sh
set -eu

if [ $# -ne 1 ]; then
  echo "Usage: Scripts/release.sh <version>" >&2
  exit 64
fi

VERSION=$1
ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/Token Bar.app"
ZIP_PATH="$DIST_DIR/TokenBar-$VERSION.zip"

cd "$ROOT_DIR"
Scripts/install.sh

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Release zip: $ZIP_PATH"
echo "Zip SHA256:"
shasum -a 256 "$ZIP_PATH"
echo
echo "Source tarball SHA256 after you push tag v$VERSION:"
echo "  curl -L https://github.com/YOUR_GITHUB_USER/token-bar/archive/refs/tags/v$VERSION.tar.gz | shasum -a 256"
