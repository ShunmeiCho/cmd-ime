cask "cmd-ime" do
  version "0.16.0"
  sha256 "34cdbf8ee239c43d5172cd9d67a3f80bb449a712471842ffc50c25c27b6e4c2b"

  url "https://github.com/ShunmeiCho/cmd-ime/releases/download/v#{version}/CmdIME-#{version}.zip"
  name "CmdIME"
  desc "Custom macOS input-source switcher with configurable shortcuts"
  homepage "https://github.com/ShunmeiCho/cmd-ime"

  depends_on arch: :arm64
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
