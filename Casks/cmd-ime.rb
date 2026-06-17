cask "cmd-ime" do
  version "0.1.7"
  sha256 "23c8269435d9af949c2f1218c26dbecf5becd74f234e1160a8a04bb7b27800ed"

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
