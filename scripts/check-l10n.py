#!/usr/bin/env python3
"""Confere se todo texto da interface tem as 4 traduções em Sources/Menew/L10n.swift.

    python3 scripts/check-l10n.py

Procura L("…") com texto fixo em Sources/ e falha se a chave (em português) não estiver na tabela
ou não tiver exatamente inglês, alemão, espanhol e chinês. Chaves montadas em tempo de execução,
como L(variavel), não têm como ser conferidas aqui.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TABLE = ROOT / "Sources/Menew/L10n.swift"

# Uma string Swift entre aspas, com escapes
STRING = r'"((?:[^"\\]|\\.)*)"'

def table_entries(text):
    """Chave → quantidade de traduções, só das linhas `"chave": ["…", "…", …],` da tabela.
    Também devolve as chaves repetidas: num dicionário literal do Swift, elas derrubam o app ao abrir."""
    entries, repeated = {}, []
    for m in re.finditer(r'^\s*' + STRING + r'\s*:\s*\[(.*)\],?\s*$', text, re.M):
        if m.group(1) in entries:
            repeated.append(m.group(1))
        entries[m.group(1)] = len(re.findall(STRING, m.group(2)))
    return entries, repeated

def used_keys():
    keys = {}
    for path in sorted((ROOT / "Sources").rglob("*.swift")):
        if path == TABLE:
            continue
        for n, line in enumerate(path.read_text().splitlines(), 1):
            # L("texto") ou L("texto %d", valor)
            for m in re.finditer(r'\bL\(\s*' + STRING, line):
                keys.setdefault(m.group(1), f"{path.relative_to(ROOT)}:{n}")
    return keys

def main():
    entries, repeated = table_entries(TABLE.read_text())
    problems = [f"{TABLE.relative_to(ROOT)}: chave repetida (o app fecha ao abrir): {k!r}" for k in repeated]
    for key, where in sorted(used_keys().items(), key=lambda kv: kv[1]):
        if key not in entries:
            problems.append(f"{where}: sem tradução: {key!r}")
        elif entries[key] != 4:
            problems.append(f"{where}: {entries[key]} traduções em vez de 4: {key!r}")
    for p in problems:
        print(p)
    if problems:
        print(f"\n{len(problems)} texto(s) sem as 4 traduções (en, de, es, zh) em {TABLE.relative_to(ROOT)}.")
        return 1
    print(f"Traduções em dia: {len(entries)} textos na tabela.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
