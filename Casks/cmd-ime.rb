cask "cmd-ime" do
  version "0.1.11"
  sha256 "b3ae83d20266197e302ee3b472ad578b8286df8e6eef277667c50ababdec8dfd"

  url "https://github.com/ShunmeiCho/cmd-ime/releases/download/v#{version}/CmdIME-#{version}.zip"
  name "CmdIME"
  desc "Custom macOS input-source switcher with configurable shortcuts"
  homepage "https://github.com/ShunmeiCho/cmd-ime"

  depends_on macos: ">= :ventura"

  app "CmdIME.app"
  binary "#{appdir}/CmdIME.app/Contents/Resources/keyboardctl"

  zap trash: [
    "~/.config/cmd-ime",
  ]
end
