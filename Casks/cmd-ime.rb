cask "cmd-ime" do
  version "0.17.1"
  sha256 "a175b9426f9e15d315f32a31d9a959860b9b96c35375435e6f29d2b3ba754875"

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
