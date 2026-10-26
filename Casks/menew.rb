# Atualizado automaticamente pelo workflow de release
cask "menew" do
  version "1.2.4"
  sha256 :no_check

  url "https://github.com/Quost/menew/releases/download/v#{version}/Menew.dmg"
  name "Menew"
  desc "Menu bar app with system monitor, clipboard history and quick actions"
  homepage "https://quost.github.io/menew/"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Menew.app"

  zap trash: [
    "~/Library/Application Support/Menew",
    "~/Library/Caches/com.matheusquost.menew",
    "~/Library/HTTPStorages/com.matheusquost.menew",
    "~/Library/Preferences/com.matheusquost.menew.plist",
  ]
end
