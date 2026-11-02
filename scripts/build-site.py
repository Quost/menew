#!/usr/bin/env python3
"""Gera o site (docs/) em todos os idiomas a partir de site/template.html e site/i18n/*.json.

    python3 scripts/build-site.py

Inglês fica em docs/index.html; os outros em docs/<idioma>/index.html.
Edite o modelo e os textos, nunca os HTML gerados.
As imagens de prévia de links (docs/assets/og) saem de: swift scripts/make-og.swift
"""
import datetime, html as htmllib, json, re, shutil, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = "https://menew.web.app"
LANGS = {  # código: (atributo lang, nome nativo)
    "en": ("en", "English"),
    "pt": ("pt-BR", "Português"),
    "de": ("de", "Deutsch"),
    "es": ("es", "Español"),
    "zh": ("zh-Hans", "中文"),
}

# Contador de visitas do site (GoatCounter: sem cookies, sem dados pessoais). Vazio = desligado.
# O app em si continua sem nenhuma telemetria.
GOATCOUNTER = "menew"
ANALYTICS = (f'<script data-goatcounter="https://{GOATCOUNTER}.goatcounter.com/count" async src="//gc.zgo.at/count.js"></script>'
             if GOATCOUNTER else "")

# Versão atual (primeira seção do CHANGELOG) e data da última mudança no site, para buscadores e IAs
VERSION = re.search(r"^## (\d+\.\d+\.\d+)", (ROOT / "CHANGELOG.md").read_text(), re.M).group(1)
# Só commits que mexem no site ou nas novidades: o bump automático do Homebrew não muda a data (e não quebra a checagem do CI)
# Com mudanças ainda não commitadas, a data é hoje (a que o commit vai ter); assim o CI gera a mesma página
_pending = subprocess.run(["git", "status", "--porcelain", "--", "site", "CHANGELOG.md"], cwd=ROOT,
                          capture_output=True, text=True).stdout.strip()
UPDATED = datetime.date.today().isoformat() if _pending else (
    subprocess.run(["git", "log", "-1", "--format=%cs", "--", "site", "CHANGELOG.md"], cwd=ROOT,
                   capture_output=True, text=True).stdout.strip() or datetime.date.today().isoformat())

def plain(text):
    """Texto sem HTML, para os dados estruturados"""
    return htmllib.unescape(re.sub(r"<[^>]+>", "", text))

def fold(text, more, tag="p"):
    """Primeira frase à mostra e o resto num <details>: a página fica leve e o texto inteiro continua no HTML
    (buscadores e IAs leem o conteúdo recolhido)."""
    # Fim de frase fora de tags: ". " seguido de algo, ou "。"
    best = None
    for m in re.finditer(r"([.!?])\s+(?=[^\s<])|。", text):
        before = text[:m.end()]
        if before.count("<") != before.count(">"):
            continue
        # Chinês diz muito mais com menos caracteres
        if len(plain(before)) >= (24 if re.search("[\u4e00-\u9fff]", text) else 60):
            best = m
            break
    if not best or len(plain(text[best.end():])) < 40:
        return f"<{tag}>{text}</{tag}>"
    lead, rest = text[:best.end()].rstrip(), text[best.end():].lstrip()
    # O resto em tópicos, uma frase por linha (fica fácil de bater o olho)
    items, start = [], 0
    for m in re.finditer(r"(?<=[.!?])\s+(?=[^\s<])|(?<=。)", rest):
        chunk = rest[start:m.start()].strip()
        if chunk and chunk.count("<") == chunk.count(">"):
            items.append(chunk)
            start = m.end()
    if rest[start:].strip():
        items.append(rest[start:].strip())
    bullets = "".join(f"<li>{i}</li>" for i in items)
    return f'<{tag}>{lead}</{tag}><details class="more"><summary>{more}</summary><ul>{bullets}</ul></details>'


def url(lang):
    return SITE + "/" if lang == "en" else f"{SITE}/{lang}"

# Só a página principal redireciona, e só quem ainda não escolheu um idioma no seletor
DETECT = """<script>
  (function () {
    try {
      var supported = ["pt", "de", "es", "zh"];
      var pick = localStorage.getItem("menew-lang") || (navigator.languages || [navigator.language])
        .map(function (l) { return l.slice(0, 2).toLowerCase(); })
        .filter(function (l) { return l === "en" || supported.indexOf(l) >= 0; })[0];
      if (pick && supported.indexOf(pick) >= 0) location.replace("/" + pick + location.hash);
    } catch (e) {}
  })();
</script>"""

LANG_PATHS = "{" + ",".join(f"{c}:'" + ("/" if c == "en" else f"/{c}") + "'" for c in LANGS) + "}"

def switch(current):
    options = "".join(
        f'<option value="{code}"{" selected" if code == current else ""}>{name}</option>'
        for code, (_, name) in LANGS.items())
    return ('<select class="lang" aria-label="Language" onchange="'
            "try{localStorage.setItem('menew-lang',this.value)}catch(e){}"
            "try{goatcounter.count({path:'lang-'+this.value,event:true})}catch(e){}"
            # Endereços fixos: o valor do <select> nunca vira URL direto (alerta do CodeQL)
            "var u=" + LANG_PATHS + "[this.value];if(u)location.href=u\">" + options + "</select>")

# Dados estruturados: o Menew como aplicativo (grátis, macOS) e as perguntas frequentes da página
def jsonld(lang, texts):
    shots = "/assets" if lang == "en" else f"/assets/{lang}"
    app = {
        "@type": "SoftwareApplication",
        "name": "Menew",
        "url": url(lang),
        "description": htmllib.unescape(texts["meta_desc"]),
        "inLanguage": LANGS[lang][0],
        "operatingSystem": "macOS 14 or later",
        "applicationCategory": "UtilitiesApplication",
        "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
        "downloadUrl": "https://github.com/Quost/menew/releases/latest/download/Menew.dmg",
        "image": f"{SITE}/assets/og/{lang}.png",
        "screenshot": [f"{SITE}{shots}/{name}-dark.png" for name in
                       ("panel0", "popover-system", "popover-actions", "palette", "capture", "popover-notes")],
        "softwareVersion": VERSION,
        "dateModified": UPDATED,
        "featureList": [plain(texts[f"f{i}_t"]) + ": " + plain(texts[f"f{i}_d"]) for i in range(1, 7)]
                       + [plain(texts[f"act_l{i}"]) for i in range(1, 11)]
                       + [plain(texts[f"nat{i}_t"]) + ": " + plain(texts[f"nat{i}_d"]) for i in range(1, 7)]
                       + [plain(texts[f"rep{i}_d"]) for i in range(1, 9)],
        "license": "https://www.gnu.org/licenses/gpl-3.0.html",
        "isAccessibleForFree": True,
        "author": {"@type": "Person", "name": "Quost", "url": "https://github.com/Quost"},
        "sameAs": ["https://github.com/Quost/menew"],
    }
    faq = {
        "@type": "FAQPage",
        "mainEntity": [{"@type": "Question", "name": plain(texts[f"faq{i}_q"]),
                        "acceptedAnswer": {"@type": "Answer", "text": plain(texts[f"faq{i}_a"])}} for i in range(1, 13)],
    }
    return json.dumps({"@context": "https://schema.org", "@graph": [app, faq]}, ensure_ascii=False).replace("</", "<\\/")

# Capturas em WebP (cerca de 1/3 do tamanho do PNG): o site carrega mais rápido, o que também conta para o Google.
# Só as que as páginas mostram, e só onde o cwebp existe (brew install webp); no CI os .webp já vêm no repositório.
CWEBP = shutil.which("cwebp")

def webp_for(png):
    webp = png.with_suffix(".webp")
    if CWEBP and png.exists() and (not webp.exists() or webp.stat().st_mtime < png.stat().st_mtime):
        subprocess.run([CWEBP, "-quiet", "-q", "88", str(png), "-o", str(webp)], check=True)
    return webp

HERO = ("panel0", "popover-system")  # na primeira tela: carregam já; o resto só quando chega perto

def optimize_images(page):
    def fix(m):
        tag, src = m.group(0), m.group(1)
        if webp_for(ROOT / "docs" / src.lstrip("/")).exists():
            tag = tag.replace(f'src="{src}"', f'src="{src[:-4]}.webp"')
        if 'class="shot' in tag and not any(h in src for h in HERO):
            tag = tag.replace("<img ", '<img loading="lazy" decoding="async" ', 1)
        return tag
    return re.sub(r'<img [^>]*src="(/assets/[^"]+\.png)"[^>]*>', fix, page)

template = (ROOT / "site/template.html").read_text()
english = json.loads((ROOT / "site/i18n/en.json").read_text())
hreflang = "\n".join(f'<link rel="alternate" hreflang="{LANGS[c][0]}" href="{url(c)}">' for c in LANGS)
hreflang += f'\n<link rel="alternate" hreflang="x-default" href="{url("en")}">'

for lang in LANGS:
    texts = json.loads((ROOT / f"site/i18n/{lang}.json").read_text())
    missing = set(english) - set(texts)
    assert not missing, f"{lang}: faltam {sorted(missing)}"
    values = dict(texts)
    values.update({
        "html_lang": LANGS[lang][0],
        "url": url(lang),
        "hreflang": hreflang,
        "detect": DETECT if lang == "en" else "",
        "shots": "/assets" if lang == "en" else f"/assets/{lang}",
        "og_image": f"{SITE}/assets/og/{lang}.png",
        "og_locale": {"en": "en_US", "pt": "pt_BR", "de": "de_DE", "es": "es_ES", "zh": "zh_CN"}[lang],
        "lang_switch": switch(lang),
        "jsonld": jsonld(lang, texts),
        **{f"f{i}_d_fold": fold(texts[f"f{i}_d"], texts["more"]) for i in range(1, 7)},
        **{f"act_l{i}_fold": "<div>" + fold(texts[f"act_l{i}"], texts["more"], "span") + "</div>" for i in range(1, 11)},
        "analytics": ANALYTICS,
        "js_strings": json.dumps({**{k: texts[k] for k in ("copied", "version", "ai_prompt")},
                                  "platforms": htmllib.unescape(texts["platforms"])}, ensure_ascii=False),
    })
    page = re.sub(r"\{\{(\w+)\}\}", lambda m: values[m.group(1)], template)
    assert "{{" not in page, f"{lang}: marcador sem valor"
    page = optimize_images(page)
    out = ROOT / "docs" / ("index.html" if lang == "en" else f"{lang}/index.html")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(page)
    print(f"{lang}: {out.relative_to(ROOT)}")


# Mapa do site (com as versões em cada idioma) e robots.txt para os buscadores
alternates = "".join(f'\n    <xhtml:link rel="alternate" hreflang="{LANGS[c][0]}" href="{url(c)}"/>' for c in LANGS)
entries = "".join(f"\n  <url>\n    <loc>{url(c)}</loc>\n    <lastmod>{UPDATED}</lastmod>{alternates}\n  </url>" for c in LANGS)
(ROOT / "docs/sitemap.xml").write_text(
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">'
    + entries + "\n</urlset>\n")
(ROOT / "docs/robots.txt").write_text(f"User-agent: *\nAllow: /\n\nSitemap: {SITE}/sitemap.xml\n")
print("docs/sitemap.xml, docs/robots.txt")

# llms.txt (llmstxt.org): resumo em texto para assistentes de IA (ChatGPT, Claude, Perplexity…) lerem e citarem
e = english
lines = [
    "# Menew", "",
    f"> {plain(e['meta_desc'])}", "",
    f"Menew {VERSION} (updated {UPDATED}). Native Swift/SwiftUI app for macOS 14 or later, Apple Silicon and Intel. "
    "Free and open source (GPL-3.0). Signed with an Apple Developer ID and notarized. Made by Quost.", "",
    "## One app instead of many", "",
    *[f"- Instead of {e[f'rep{i}_t'].replace(' · ', ' or ')}: {plain(e[f'rep{i}_d'])}" for i in range(1, 9)], "",
    "## Features", "",
    *[f"- {plain(e[f'f{i}_t'])}: {plain(e[f'f{i}_d'])}" for i in range(1, 7)], "",
    "## More features", "",
    *[f"- {plain(e[f'act_l{i}'])}" for i in range(1, 11)],
    *[f"- {plain(e[f'nat{i}_t'])}: {plain(e[f'nat{i}_d'])}" for i in range(1, 7)],
    *[f"- {plain(e[f'pro{i}_t'])}: {plain(e[f'pro{i}_d'])}" for i in range(1, 7)], "",
    "## FAQ", "",
    *[f"### {plain(e[f'faq{i}_q'])}\n\n{plain(e[f'faq{i}_a'])}\n" for i in range(1, 13)],
    "## Install", "",
    "- Download: https://github.com/Quost/menew/releases/latest/download/Menew.dmg",
    "- Homebrew: `brew tap quost/menew https://github.com/Quost/menew && brew install --cask menew`", "",
    "## Links", "",
    f"- Website: {SITE}/ (also in Portuguese, German, Spanish and Chinese: {SITE}/pt, {SITE}/de, {SITE}/es, {SITE}/zh)",
    "- Source code and README: https://github.com/Quost/menew",
    "- Releases and changelog: https://github.com/Quost/menew/releases",
]
(ROOT / "docs/llms.txt").write_text("\n".join(lines) + "\n")
print("docs/llms.txt")
