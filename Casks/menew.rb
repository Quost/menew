# Atualizado automaticamente pelo workflow de release
cask "menew" do
  version "1.106.0"
  sha256 "0de1864bc9cb1c7b9813aa4419c2c9b9e9f6b0fe2996038dce65a3ec2575e90c"

  url "https://github.com/Quost/menew/releases/download/v#{version}/Menew.dmg"
  name "Menew"
  desc "Menu bar app with system monitor, clipboard history and quick actions"
  homepage "https://menew.pururucos.com.br/"

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
    "~/Library/Group Containers/9527N6XKKW.com.matheusquost.menew",
    "~/Library/HTTPStorages/com.matheusquost.menew",
    "~/Library/Preferences/com.matheusquost.menew.plist",
  ]
end
