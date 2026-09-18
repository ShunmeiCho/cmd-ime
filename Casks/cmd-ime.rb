cask "cmd-ime" do
  version "0.5.0"
  sha256 "1f7a582261e26b57db21d2cffa6cdffd19020bc92d16b619c9acfb3e9b71f61b"

  url "https://github.com/ShunmeiCho/cmd-ime/releases/download/v#{version}/CmdIME-#{version}.zip"
  name "CmdIME"
  desc "Custom macOS input-source switcher with configurable shortcuts"
  homepage "https://github.com/ShunmeiCho/cmd-ime"

  depends_on macos: :ventura

  app "CmdIME.app"
  binary "#{appdir}/CmdIME.app/Contents/Resources/keyboardctl"

  caveats do
    unsigned_accessibility
  end

  zap trash: [
    "~/.config/cmd-ime",
  ]
end
