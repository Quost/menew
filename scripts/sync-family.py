#!/usr/bin/env python3
"""Atualiza a cópia local da lista de produtos da Pururucos (faixa "Outros apps da Pururucos" e rodapé do site).

    python3 scripts/sync-family.py                      # baixa https://pururucos.com.br/products.json e as imagens
    python3 scripts/sync-family.py --json products.json # usa um arquivo local (ex.: antes do deploy do site da Pururucos)

Grava site/family.json e as imagens (ícones dos outros apps e o logo da Pururucos) em docs/assets/family/.
NÃO roda no build: scripts/build-site.py só lê a cópia local, para o build continuar determinístico e sem rede.
Rode à mão quando a Pururucos lançar ou mudar um produto, confira o diff, rode o build-site.py e faça commit.
"""
import argparse, json, sys, urllib.request
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
SOURCE = "https://pururucos.com.br/products.json"
OUT_JSON = ROOT / "site/family.json"
OUT_IMG = ROOT / "docs/assets/family"
LANGS = ("en", "pt", "de", "es", "zh")
IMAGE_TYPES = (".webp", ".png", ".svg", ".jpg", ".jpeg")

def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "menew-site-sync"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()

def local_name(url):
    """Nome do arquivo local de uma imagem remota (o build-site.py usa a mesma regra)"""
    name = Path(urlparse(url).path).name
    assert name and Path(name).suffix.lower() in IMAGE_TYPES, f"imagem inesperada: {url}"
    return name

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", help="arquivo local no lugar de " + SOURCE)
    ap.add_argument("--images", help="pasta com as imagens (ex.: public/ do site da Pururucos), no lugar de baixar")
    args = ap.parse_args()

    data = json.loads(Path(args.json).read_text(encoding="utf-8") if args.json else fetch(SOURCE).decode("utf-8"))
    maker = data["maker"]
    for key in ("credit", "about", "cta", "othersTitle"):
        assert set(LANGS) <= set(maker[key]), f"maker.{key}: faltam idiomas"
    for key in ("title", "body"):
        assert set(LANGS) <= set(maker["yourIdea"][key]), f"maker.yourIdea.{key}: faltam idiomas"
    for p in data["products"]:
        assert set(LANGS) <= set(p["tagline"]), f"{p['id']}: faltam idiomas no tagline"

    # Só as imagens que o site mostra: o logo e os ícones dos outros apps (o do Menew já está em docs/assets/icon.png)
    urls = [maker["logo"]] + [p["icon"] for p in data["products"] if p["id"] != "menew"]
    OUT_IMG.mkdir(parents=True, exist_ok=True)
    keep = set()
    for url in urls:
        name = local_name(url)
        if args.images:
            body = (Path(args.images) / urlparse(url).path.lstrip("/")).read_bytes()
        else:
            body = fetch(url)
        (OUT_IMG / name).write_bytes(body)
        keep.add(name)
        print(f"docs/assets/family/{name} ({len(body)} bytes)")
    for old in OUT_IMG.iterdir():
        if old.name not in keep:
            old.unlink()
            print(f"removido: docs/assets/family/{old.name}")

    OUT_JSON.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{OUT_JSON.relative_to(ROOT)}: {len(data['products'])} produtos")
    print("Agora: python3 scripts/build-site.py")

if __name__ == "__main__":
    sys.exit(main())
