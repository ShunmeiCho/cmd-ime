cask "cmd-ime" do
  version "0.6.4"
  sha256 "825e446dd3abfbdb4fd80b3b5cb99633f2ba0274e22b5f8d9d6eae35e42cd789"

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
