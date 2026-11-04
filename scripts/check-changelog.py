#!/usr/bin/env python3
"""Confere o CHANGELOG.md, que vira as notas de cada versão (no app e no GitHub).

    python3 scripts/check-changelog.py

- Toda versão publicada (tag vX.Y.Z) desde a primeira seção do arquivo tem a sua seção "## X.Y.Z";
  sem ela, as notas daquela versão grudam na seção de cima.
- As seções estão da mais nova para a mais antiga, sem repetir.
- "## Unreleased" só no topo, e nenhum "###" fora de uma seção de versão.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# Saíram no mesmo dia, antes do CHANGELOG ter uma seção por versão; as notas delas estão na 1.2.4
WITHOUT_SECTION = {"1.2.0", "1.2.1", "1.2.2", "1.2.3"}

def version(v):
    return tuple(int(x) for x in v.split("."))

def main():
    lines = (ROOT / "CHANGELOG.md").read_text().splitlines()
    problems, heads, current = [], [], None
    for n, line in enumerate(lines, 1):
        if line.startswith("## "):
            name = line[3:].strip()
            if name == "Unreleased":
                if heads:
                    problems.append(f"CHANGELOG.md:{n}: \"## Unreleased\" precisa ficar no topo, antes das versões")
            elif re.fullmatch(r"\d+\.\d+\.\d+", name):
                heads.append((name, n))
            else:
                problems.append(f"CHANGELOG.md:{n}: título de seção inesperado: {line!r}")
            current = name
        elif line.startswith("### ") and current is None:
            problems.append(f"CHANGELOG.md:{n}: \"{line}\" fora de uma seção \"## X.Y.Z\"")

    names = [h for h, _ in heads]
    for (a, na), (b, _) in zip(heads, heads[1:]):
        if version(a) <= version(b):
            problems.append(f"CHANGELOG.md:{na}: {a} deveria vir depois de {b} (mais nova primeiro, sem repetir)")

    tags = subprocess.run(["git", "tag", "-l", "v*"], cwd=ROOT, capture_output=True, text=True).stdout.split()
    released = [t[1:] for t in tags if re.fullmatch(r"v\d+\.\d+\.\d+", t)]
    if names and released:
        oldest = min(map(version, names))
        for v in sorted(released, key=version):
            if version(v) >= oldest and v not in names and v not in WITHOUT_SECTION:
                problems.append(f"CHANGELOG.md: a versão {v} foi publicada, mas não tem a seção \"## {v}\"")

    for p in problems:
        print(p)
    if problems:
        return 1
    print(f"CHANGELOG em dia: {len(names)} versões.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
