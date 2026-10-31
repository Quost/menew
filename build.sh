#!/bin/bash
# Compila e monta o Menew.app em ./build
#
#   ./build.sh            → build/Menew.app
#   ./build.sh --install  → e copia para /Applications e abre
#   ./build.sh --dmg      → e gera build/Menew.dmg
#
# Variáveis opcionais:
#   VERSION=1.2.0                                   versão no Info.plist
#   BUILD=1                                         número do build (padrão: nº de commits)
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

# Grava no binário a versão real do SDK. Sem isso o SwiftPM pode gravar a do
# deployment target (14.0), e o macOS roda o app em modo de compatibilidade: sem o
# comportamento novo do Liquid Glass, e o build local fica diferente do publicado.
# Só no build de uma arquitetura: o universal (CI) passa pelo XCBuild, que já grava o SDK certo
# e não aceita estes argumentos.
SDK_FLAGS=()
[ "${UNIVERSAL:-0}" = 1 ] || SDK_FLAGS=(-Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$(xcrun --sdk macosx --show-sdk-version)")

# App Intents (Siri, Atalhos, Spotlight): o compilador anota as intents (.swiftconstvalues) e o
# appintentsmetadataprocessor do Xcode gera o Metadata.appintents que o macOS lê do app
INTENT_FLAGS=(-Xswiftc -Xfrontend -Xswiftc -const-gather-protocols-file -Xswiftc -Xfrontend -Xswiftc "$PWD/Resources/intent-protocols.json"
              -Xswiftc -emit-const-values)

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} ${SDK_FLAGS[@]+"${SDK_FLAGS[@]}"} "${INTENT_FLAGS[@]}"
BIN_DIR=$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} ${SDK_FLAGS[@]+"${SDK_FLAGS[@]}"} "${INTENT_FLAGS[@]}" --show-bin-path)

APP=build/Menew.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Menew" "$APP/Contents/MacOS/Menew"
# Sem símbolos de depuração: o binário cai para menos da metade
strip -Sx "$APP/Contents/MacOS/Menew"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

INTENTS_TMP=$(mktemp -d)
find "$PWD/.build" -path "*Release*" -path "*Menew*" -path "*arm64*" -name "*.swiftconstvalues" -newer Package.swift > "$INTENTS_TMP/constvalues.txt"
ls "$PWD"/Sources/Menew/*.swift > "$INTENTS_TMP/sources.txt"
xcrun appintentsmetadataprocessor --output "$APP/Contents/Resources" \
  --toolchain-dir "$(dirname "$(dirname "$(dirname "$(xcrun --find swift)")")")" --module-name Menew \
  --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" --xcode-version "$(xcodebuild -version | awk '/Build version/{print $3}')" \
  --platform-family macOS --deployment-target 14.0 --target-triple arm64-apple-macos14.0 \
  --source-file-list "$INTENTS_TMP/sources.txt" --swift-const-vals-list "$INTENTS_TMP/constvalues.txt" --quiet-warnings > /dev/null
rm -rf "$INTENTS_TMP"
[ -d "$APP/Contents/Resources/Metadata.appintents" ] || { echo "App Intents: Metadata.appintents não foi gerado" >&2; exit 1; }

# Sparkle (atualização automática). App sem sandbox: os serviços XPC não são necessários.
mkdir -p "$APP/Contents/Frameworks"
cp -R "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" \
       "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"
# Cabeçalhos só servem para compilar; das traduções do Sparkle ficam as dos idiomas do Menew
FWB="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
rm -rf "$FWB/Headers" "$FWB/PrivateHeaders" "$FWB/Modules" \
       "$APP/Contents/Frameworks/Sparkle.framework/Headers" "$APP/Contents/Frameworks/Sparkle.framework/PrivateHeaders" \
       "$APP/Contents/Frameworks/Sparkle.framework/Modules"
find "$FWB/Resources" -maxdepth 1 -name '*.lproj' \
  ! -name Base.lproj ! -name en.lproj ! -name de.lproj ! -name es.lproj ! -name 'pt*.lproj' ! -name 'zh_CN.lproj' ! -name 'zh-Hans.lproj' \
  -exec rm -rf {} +

# Sem VERSION, usa a última tag (o build local mostra a versão certa nos Ajustes)
[ -z "${VERSION:-}" ] && VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)

if [ -n "${VERSION:-}" ]; then
  plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
  plutil -replace CFBundleVersion -string "${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}" "$APP/Contents/Info.plist"
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
