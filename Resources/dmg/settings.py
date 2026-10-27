# Aparência da janela do Menew.dmg (dmgbuild). Usado pelo build.sh:
#   dmgbuild -s Resources/dmg/settings.py -D app=build/Menew.app Menew build/Menew.dmg
import os.path

app = defines.get("app", "build/Menew.app")  # noqa: F821 (definido pelo dmgbuild)
appname = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = "Resources/AppIcon.icns"            # ícone do disco montado

background = "Resources/dmg/background.tiff"  # 640×400 com versão @2x
window_rect = ((200, 120), (640, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 128
text_size = 13
# Centros iguais aos do scripts/make-dmg-background.swift
icon_locations = {appname: (170, 205), "Applications": (470, 205)}
