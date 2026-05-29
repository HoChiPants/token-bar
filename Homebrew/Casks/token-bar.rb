cask "token-bar" do
  version "0.1.0"
  sha256 "REPLACE_WITH_RELEASE_ZIP_SHA256"

  url "https://github.com/YOUR_GITHUB_USER/token-bar/releases/download/v#{version}/TokenBar-#{version}.zip"
  name "Token Bar"
  desc "macOS menu bar utility for Codex token usage"
  homepage "https://github.com/YOUR_GITHUB_USER/token-bar"

  app "Token Bar.app"
  binary "#{appdir}/Token Bar.app/Contents/MacOS/tokenbar-cli", target: "tokenbar"

  zap trash: [
    "~/Library/Preferences/local.tokenbar.app.plist",
  ]
end
