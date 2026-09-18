cask "cmd-ime" do
  version "0.3.0"
  sha256 "a1b9aed7287c9da58ddcc6c7ceca0d7027a53f808ad0732392a35721243d08b0"

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
