# Atualizado automaticamente pelo workflow de release
cask "menew" do
  version "1.104.0"
  sha256 "d015364f8e688c70d7976acf19dcd4b2f25e66c3aaafa908d389b470d0a8c13a"

  url "https://github.com/Quost/menew/releases/download/v#{version}/Menew.dmg"
  name "Menew"
  desc "Menu bar app with system monitor, clipboard history and quick actions"
  homepage "https://menew.web.app/"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sonoma

  app "Menew.app"

  zap trash: [
    "~/Library/Application Support/Menew",
    "~/Library/Caches/com.matheusquost.menew",
    "~/Library/HTTPStorages/com.matheusquost.menew",
    "~/Library/Preferences/com.matheusquost.menew.plist",
  ]
end
