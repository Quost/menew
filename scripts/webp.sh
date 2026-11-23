#!/bin/bash
# WebP copies of the screenshots (about 1/3 of the PNG size). The website serves the .webp when it sits next to the .png.
#   scripts/webp.sh                       # refreshes every docs/assets/**/*.webp whose .png is newer
#   scripts/webp.sh docs/assets/a.png ... # creates or refreshes the .webp of these PNGs
# Needs cwebp (brew install webp).
set -e
cd "$(dirname "$0")/.."
command -v cwebp >/dev/null || { echo "cwebp not found: brew install webp"; exit 1; }
if [ $# -gt 0 ]; then pngs=("$@"); else
  pngs=(); while IFS= read -r w; do p="${w%.webp}.png"; [ -f "$p" ] && [ "$p" -nt "$w" ] && pngs+=("$p"); done < <(find docs/assets -name '*.webp')
fi
for p in "${pngs[@]}"; do cwebp -quiet -q 88 "$p" -o "${p%.png}.webp" && echo "${p%.png}.webp"; done
