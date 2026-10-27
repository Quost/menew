#!/bin/bash
# Compila e monta o Menew.app em ./build
#
#   ./build.sh            → build/Menew.app
#   ./build.sh --install  → e copia para /Applications e abre
#   ./build.sh --dmg      → e gera build/Menew.dmg
#
# Variáveis opcionais:
#   VERSION=1.2.0                                   versão no Info.plist
#   UNIVERSAL=1                                     binário arm64 + x86_64
#   SIGN_IDENTITY="Developer ID Application: ..."   assina para distribuição (senão, ad-hoc)
#
# Para builds locais, coloque o nome ou o SHA-1 de um certificado seu em
# .signing-identity (fora do git). Com assinatura estável, o macOS lembra a
# permissão de Acessibilidade entre um build e outro; com ad-hoc, pede de novo.
set -euo pipefail
cd "$(dirname "$0")"

if [ -z "${SIGN_IDENTITY:-}" ] && [ -f .signing-identity ]; then
  SIGN_IDENTITY=$(head -1 .signing-identity)
fi

ARCH_FLAGS=()
[ "${UNIVERSAL:-0}" = 1 ] && ARCH_FLAGS=(--arch arm64 --arch x86_64)

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR=$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)

APP=build/Menew.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Menew" "$APP/Contents/MacOS/Menew"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

# Sparkle (atualização automática). App sem sandbox: os serviços XPC não são necessários.
mkdir -p "$APP/Contents/Frameworks"
cp -R "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" \
       "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"

if [ -n "${VERSION:-}" ]; then
  plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
  plutil -replace CFBundleVersion -string "$(git rev-list --count HEAD 2>/dev/null || echo 1)" "$APP/Contents/Info.plist"
fi

# Assina de dentro para fora: partes do Sparkle, o framework e por fim o app
if [ -n "${SIGN_IDENTITY:-}" ]; then
  SIGN=(codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY")
else
  SIGN=(codesign --force --sign -)
fi
FW="$APP/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" "$FW/Versions/B/Autoupdate"
"${SIGN[@]}" "$FW/Versions/B/Updater.app"
"${SIGN[@]}" "$FW"
"${SIGN[@]}" --entitlements Resources/Menew.entitlements "$APP"
codesign --verify --strict "$APP"
echo "Pronto: $APP"

for arg in "$@"; do
  case "$arg" in
    --dmg)
      # Janela de instalação com fundo, seta e ícones posicionados (Resources/dmg)
      if [ ! -x .build/dmgvenv/bin/dmgbuild ]; then
        python3 -m venv .build/dmgvenv
        .build/dmgvenv/bin/pip install -q dmgbuild
      fi
      rm -f build/Menew.dmg
      .build/dmgvenv/bin/dmgbuild -s Resources/dmg/settings.py -D app="$APP" Menew build/Menew.dmg > /dev/null
      [ -n "${SIGN_IDENTITY:-}" ] && codesign --force --timestamp --sign "$SIGN_IDENTITY" build/Menew.dmg
      echo "Pronto: build/Menew.dmg"
      ;;
    --install)
      pkill -x Menew 2>/dev/null || true
      pkill -x MeuMenu 2>/dev/null || true
      rm -rf /Applications/Menew.app
      cp -R "$APP" /Applications/
      open /Applications/Menew.app
      echo "Instalado em /Applications"
      ;;
  esac
done
