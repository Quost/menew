# Atualizado automaticamente pelo workflow de release
cask "menew" do
  version "1.6.2"
  sha256 "74712e5294ac12dc1ccf1b8cfd578b5d0ae5944c05d784828fd41984b5f5c27a"

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
