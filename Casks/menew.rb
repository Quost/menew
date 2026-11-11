# Atualizado automaticamente pelo workflow de release
cask "menew" do
  version "1.101.0"
  sha256 "4798cff2f08a55c7f0f9d49db9538ffb7930e495850f69c4094eedb789fee97f"

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
