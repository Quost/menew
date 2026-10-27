#!/usr/bin/env python3
"""Gera o site (docs/) em todos os idiomas a partir de site/template.html e site/i18n/*.json.

    python3 scripts/build-site.py

Inglês fica em docs/index.html; os outros em docs/<idioma>/index.html.
Edite o modelo e os textos, nunca os HTML gerados.
As imagens de prévia de links (docs/assets/og) saem de: swift scripts/make-og.swift
"""
import html as htmllib, json, re
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

def switch(current):
    options = "".join(
        f'<option value="{code}"{" selected" if code == current else ""}>{name}</option>'
        for code, (_, name) in LANGS.items())
    return ('<select class="lang" aria-label="Language" onchange="'
            "try{localStorage.setItem('menew-lang',this.value)}catch(e){}"
            "location.href=this.value==='en'?'/':'/'+this.value\">" + options + "</select>")

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
        "js_strings": json.dumps({**{k: texts[k] for k in ("copied", "version", "ai_prompt")},
                                  "platforms": htmllib.unescape(texts["platforms"])}, ensure_ascii=False),
    })
    page = re.sub(r"\{\{(\w+)\}\}", lambda m: values[m.group(1)], template)
    assert "{{" not in page, f"{lang}: marcador sem valor"
    out = ROOT / "docs" / ("index.html" if lang == "en" else f"{lang}/index.html")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(page)
    print(f"{lang}: {out.relative_to(ROOT)}")
