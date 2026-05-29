class Tokenbar < Formula
  desc "CLI for local Codex token usage"
  homepage "https://github.com/YOUR_GITHUB_USER/token-bar"
  url "https://github.com/YOUR_GITHUB_USER/token-bar/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_SOURCE_TARBALL_SHA256"
  license "MIT"

  depends_on xcode: ["14.0", :build]

  def install
    system "swift", "build", "-c", "release", "--product", "tokenbar-cli", "--disable-sandbox"
    bin.install ".build/release/tokenbar-cli" => "tokenbar"
  end

  test do
    assert_match "Usage: tokenbar", shell_output("#{bin}/tokenbar help")
  end
end
