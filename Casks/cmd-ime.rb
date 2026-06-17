cask "cmd-ime" do
  version "0.1.8"
  sha256 "bec5552046f949b5c30562ae9f050b121e783e4975f99eece9d35ed20aa11401"

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
