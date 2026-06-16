cask "cmd-ime" do
  version "0.1.3"
  sha256 "9014d3c7271142c7dd82485ebad91383bafeefb02adfa512eb54a66a1c1a9219"

  url "https://github.com/ShunmeiCho/cmd-ime/releases/download/v#{version}/CmdIME-#{version}.zip"
  name "CmdIME"
  desc "Custom macOS input-source switcher for English, Chinese, and Japanese"
  homepage "https://github.com/ShunmeiCho/cmd-ime"

  depends_on macos: ">= :ventura"

  app "CmdIME.app"
  binary "#{appdir}/CmdIME.app/Contents/Resources/keyboardctl"

  zap trash: [
    "~/.config/cmd-ime",
  ]
end
