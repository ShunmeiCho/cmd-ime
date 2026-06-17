cask "cmd-ime" do
  version "0.1.10"
  sha256 "3c25937c947478ffa1f24d344debb20e8a62f3036e4746782e79659aa9c52e5c"

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
