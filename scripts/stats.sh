#!/bin/bash
# Números do Menew sem telemetria: tudo vem das estatísticas públicas do GitHub.
#
#   scripts/stats.sh
#
# - .dmg: instalações novas (inclui o Homebrew)
# - .zip: atualizações automáticas baixadas
# - appcast.xml: verificações de atualização; por dia ≈ apps abertos (zera a cada release)
set -euo pipefail
REPO=Quost/menew
GH=$(command -v gh || echo /opt/homebrew/bin/gh)

echo "== Downloads por versão"
"$GH" api "repos/$REPO/releases" --jq '.[] |
  ([.assets[] | {(.name): .download_count}] | add // {}) as $a |
  "\(.tag_name)\t.dmg \($a["Menew.dmg"] // 0)\t.zip \($a["Menew.zip"] // 0)\tverificações \($a["appcast.xml"] // 0)\t(\(.published_at[:10]))"' | column -t -s $'\t'

echo
echo "== Totais"
"$GH" api "repos/$REPO/releases" --jq '[.[].assets[]] |
  "instalações (.dmg): \([.[] | select(.name == "Menew.dmg") | .download_count] | add // 0)  ·  atualizações (.zip): \([.[] | select(.name == "Menew.zip") | .download_count] | add // 0)"'

echo
echo "== Repositório"
"$GH" api "repos/$REPO" --jq '"⭐ \(.stargazers_count)  ·  👀 \(.subscribers_count)  ·  🍴 \(.forks_count)  ·  issues abertas \(.open_issues_count)"'
"$GH" api "repos/$REPO/traffic/views" --jq '"visitas (14 dias): \(.count)  ·  visitantes únicos: \(.uniques)"' 2>/dev/null || true
"$GH" api "repos/$REPO/traffic/clones" --jq '"clones (14 dias): \(.count)"' 2>/dev/null || true
REFS=$("$GH" api "repos/$REPO/traffic/popular/referrers" --jq '.[] | "  \(.referrer): \(.count) visitas"' 2>/dev/null || true)
[ -n "$REFS" ] && echo "de onde vêm:" && echo "$REFS"
exit 0
