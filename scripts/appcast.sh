#!/bin/bash
# Gera o appcast.xml do Sparkle com as notas da versão (do CHANGELOG.md) embutidas.
#
#   scripts/appcast.sh VERSION TAG BUILD 'sparkle:edSignature="…" length="…"' > appcast.xml
#
# As notas viram HTML pela API de Markdown do GitHub (precisa do gh logado ou GH_TOKEN).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$1 TAG=$2 BUILD=$3 SIG=$4

NOTES=$(awk -v v="$VERSION" '/^## /{p = ($2 == v); next} p' CHANGELOG.md)
[ -z "$NOTES" ] && NOTES="See what's new on GitHub: https://github.com/Quost/menew/releases/tag/$TAG"
HTML=$(gh api markdown -f text="$NOTES" -f mode=gfm -f context=Quost/menew)

cat <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Menew</title>
    <item>
      <title>Menew $VERSION</title>
      <pubDate>$(date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/Quost/menew/releases/tag/$TAG</sparkle:fullReleaseNotesLink>
      <description><![CDATA[
<meta name="color-scheme" content="light dark">
<style>
  body { font: 13px/1.5 -apple-system, system-ui, sans-serif; margin: 14px 18px; }
  ul { padding-left: 18px; margin: 0; }
  li { margin: 0 0 7px; }
  code { font: 12px ui-monospace, Menlo, monospace; padding: 1px 4px; border-radius: 4px; background: rgba(127,127,127,.18); }
  a { color: #6c5ce7; }
</style>
$HTML
]]></description>
      <enclosure url="https://github.com/Quost/menew/releases/download/$TAG/Menew.zip" type="application/octet-stream" $SIG />
    </item>
  </channel>
</rss>
XML
