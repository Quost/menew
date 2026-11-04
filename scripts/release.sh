#!/bin/bash
# Publica uma versão: confere o CHANGELOG, gera o site, faz os commits, espera a Release anterior,
# cria a tag e acompanha a Release até o fim (appcast e cask do Homebrew).
#
#   scripts/release.sh 1.2.3 "feat(scope): mensagem do commit"
#
# Antes: CHANGELOG.md com a seção "## 1.2.3" (renomeie o "## Unreleased"), README e site atualizados.
set -e
cd "$(dirname "$0")/.."
V=$1; MSG=$2
[ -n "$V" ] && [ -n "$MSG" ] || { echo "uso: scripts/release.sh X.Y.Z \"tipo(escopo): mensagem\""; exit 1; }
T=$'\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
[ ${#MSG} -le 100 ] || { echo "título do commit longo demais: ${#MSG} caracteres (máximo 100)"; exit 1; }
grep -q "^## $V\$" CHANGELOG.md || { echo "CHANGELOG.md não tem a seção ## $V"; exit 1; }
python3 scripts/check-changelog.py
python3 scripts/check-l10n.py
python3 scripts/build-site.py >/dev/null

git add Sources Resources Tests build.sh scripts .github Package.swift 2>/dev/null || true
git diff --cached --quiet || git commit -qS -m "$MSG$T"
git add -A docs site README.md CHANGELOG.md CONTRIBUTING.md
git diff --cached --quiet || git commit -qS -m "docs: readme, site and changelog for $V$T"

# Uma Release por vez: duas em paralelo brigam pelo cask e pelo push
until [ "$(gh run list -w Release -L1 --json status -q '.[0].status')" = completed ]; do sleep 15; done
# Merge, nunca rebase: os commits de bump do cask chegam pelo main
git pull -q --no-rebase && git push -q && git tag -a "v$V" -m "Menew $V" && git push -q origin "v$V"

sleep 10
ID=$(gh run list -w Release -L 1 --json databaseId -q '.[0].databaseId')
gh run watch "$ID" --exit-status >/dev/null 2>&1 || true
echo "Release: $(gh run view "$ID" --json conclusion,headBranch -q '.headBranch+" "+.conclusion')"
gh run view "$ID" --log-failed 2>/dev/null | tail -10
echo "appcast: $(curl -sL https://github.com/Quost/menew/releases/latest/download/appcast.xml | grep -o 'shortVersionString>[0-9.]*' | head -1)"
echo "cask: $(gh api repos/Quost/menew/contents/Casks/menew.rb -q .content | base64 -d | grep 'version "')"
git pull -q --no-rebase
