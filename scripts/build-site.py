#!/usr/bin/env python3
"""Gera o site (docs/) em todos os idiomas a partir de site/template.html e site/i18n/*.json.

    python3 scripts/build-site.py
    MENEW_LINUX_DIR=../menew-linux python3 scripts/build-site.py   # usa uma cópia local do menew-linux, sem rede

Inglês fica em docs/index.html; os outros em docs/<idioma>/index.html.
Páginas por plataforma, nos 5 idiomas: /mac (site/mac.html), /linux (site/linux.html) e /windows (site/windows.html, "em breve").
A principal (site/template.html) apresenta o Menew e as três plataformas; a instalação detalhada do Mac fica em /mac.
Edite o modelo e os textos, nunca os HTML gerados.
A página /linux é a exceção: os textos (site/linux.json) e as capturas (docs/assets/) vêm do repositório
Quost/menew-linux (clone raso da main, ou a pasta de MENEW_LINUX_DIR), e as páginas geradas ficam fora do git.
As imagens de prévia de links (docs/assets/og) saem de: swift scripts/make-og.swift
"""
import atexit, datetime, html as htmllib, json, os, re, shutil, subprocess, tempfile
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

# Fatos diretos para o llms.txt: o que cada parte faz, sem a IA precisar deduzir (ela errava "não tem terços", "não tem temperatura")
FACTS = [
    ("Window manager", "Snap windows to halves, quarters (corners), thirds and two-thirds, maximize, center and restore, with the same ⌃⌥ shortcuts as Rectangle; drag a window to a screen edge or corner to snap it; move it to the next display; a layout grid in Actions; work profiles bring apps and window layouts back."),
    ("Command palette (⌃⌥Space)", "Apps, Menew actions, window layouts, snippets, notes and clipboard items; math, unit, currency and time zone conversions; text transforms (case, JSON, Base64, word count); developer tools (ports in use, UUID, Unix timestamps, JWT); quick links and web search; emoji and symbols; timers, alarms and reminders; your own script commands in shell, Python, Node or AppleScript (Raycast-compatible); natural-language commands with on-device AI."),
    ("Clipboard history (⌘⇧V)", "Text, links, images and files with search (including text inside images, read on the Mac, and search by meaning), pins, filters and previews; snippets with abbreviations that expand as you type, variables, fields and cursor position; a paste queue; items marked by password managers are skipped; a Passwords tab pastes passwords notes after Touch ID."),
    ("System monitor", "CPU and GPU with live graphs, memory pressure and swap, disk space and read/write speed, network usage per app, battery health, cycles and wear over time, temperatures of the chip, SSD and battery, fan speed, performance and efficiency cores, power in watts, SSD health, 24-hour, 7-day and 30-day history, custom alert rules, a plain-language 'Why is my Mac slow?' diagnosis and screen time."),
    ("Screenshots and recording", "Capture an area, window or the whole screen; annotate with arrows, text and blur; pin on screen; record the screen with sound, as video or GIF; scrolling capture; copy text from anywhere on screen (OCR on the Mac)."),
    ("Meetings and recordings", "Next meeting with a Join button for Zoom, Meet, Teams and Webex; notch alerts that skip calendar blocks; record Mac audio and the microphone as separate tracks; on-device transcription; minutes with the main topic, a summary, each topic discussed, decisions, a task table with owner and deadline, and next steps; tasks to Reminders."),
    ("Memory", "⌃⌥⌘K saves what is on screen with its text, app and link; ask in plain words and get an answer with sources; a knowledge graph of topics; items appear in Spotlight."),
    ("Files and cleanup", "A drag-and-drop shelf with image and PDF tools (convert, compress, split, OCR, password-protect); organize a folder by file content with review and undo; disk cleaner for caches, logs, large and duplicate files (files go to the Trash); app uninstaller with leftovers; login and background items."),
    ("AI coding agents", "Claude Code, Codex, Gemini CLI, Cursor, Copilot CLI, Kiro, OpenCode, Droid, Qwen Code, Amp, OpenClaw, Kimi, Goose and Pi sessions with their state (working, done, waiting for a permission or answer) through each tool's hooks (or its running process and logs when it has none), shown in the notch with a button that opens the right terminal; plan limits (5-hour and weekly windows) with reset times, a forecast at the current pace and alerts at 75% and 90%; tokens per day, estimated cost at Anthropic API prices, cache savings, top models and projects, read from the tools' local logs; Ollama and LM Studio models loaded in memory; a local MCP server (Menew --mcp) for Claude Code, Codex, Gemini CLI, Claude Desktop, Cursor, Kiro, Copilot CLI, OpenCode, Qwen Code, Droid, Amp and Kimi to search Memory, notes and meeting minutes, check the Mac and save notes."),
    ("Made for macOS", "Live notch alerts and a hover panel with call controls; desktop widgets; Siri, Shortcuts and Spotlight actions; Focus filters; Live Text in images; Continuity Camera; live translated captions; Liquid Glass design on macOS 26; English, Portuguese, German, Spanish and Chinese."),
]
NOT_INCLUDED = ("Menew does not hide or rearrange other apps' menu bar icons (use Ice or Thaw), has no extension store "
                "(it runs your own scripts), does not sync to a cloud, and does not embed a web browser in the menu bar.")

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

# Pururucos (a empresa que faz o Menew) e os outros apps dela: cópia local de https://pururucos.com.br/products.json
# (site/family.json + imagens em docs/assets/family/), atualizada à mão com scripts/sync-family.py; o build não usa a rede para isso
FAMILY = json.loads((ROOT / "site/family.json").read_text(encoding="utf-8"))
MAKER = FAMILY["maker"]
PURURUCOS_ORG = {"@type": "Organization", "@id": MAKER["id"], "name": MAKER["name"], "url": MAKER["url"]}

def family_img(remote):
    """Imagem da Pururucos servida daqui (mesmo nome do arquivo remoto; scripts/sync-family.py baixa)"""
    local = "/assets/family/" + remote.rsplit("/", 1)[-1]
    assert (ROOT / "docs" / local.lstrip("/")).exists(), f"{local} não existe: rode scripts/sync-family.py"
    return local

def utm(link, medium):
    if link.count("/") == 2:  # https://site.app -> https://site.app/
        link += "/"
    return link + ("&" if "?" in link else "?") + f"utm_source=menew&utm_medium={medium}"

def maker_url(lang, medium):
    """Site da Pururucos: a raiz é em português; os outros idiomas vão para /en/"""
    return utm(MAKER["url"].rstrip("/") + ("/" if lang == "pt" else "/en/"), medium)

def family_band(lang):
    """Faixa "Outros apps da Pururucos", acima do rodapé de todas as páginas"""
    esc = htmllib.escape
    card = ('      <li><a class="family-card{cls}" href="{href}" data-goatcounter-click="{click}" target="_blank" rel="noopener">'
            '<img src="{img}" width="44" height="44" alt="" loading="lazy" decoding="async">'
            '<span><b>{name}</b><span>{text}</span></span></a></li>')
    cards = [card.format(cls="", href=esc(utm(p["url"], "apps_band")), click=f"family-{p['id']}", img=family_img(p["icon"]),
                         name=esc(p["name"]), text=esc(p["tagline"][lang]))
             for p in FAMILY["products"] if p["id"] != "menew"]
    idea = MAKER["yourIdea"]
    cards.append(card.format(cls=" idea", href=esc(maker_url(lang, "apps_band")), click="family-your-idea", img=family_img(MAKER["logo"]),
                             name=esc(idea["title"][lang]), text=esc(idea["body"][lang])))
    title = esc(MAKER["othersTitle"][lang])
    return (f'<aside class="family" aria-labelledby="family-title">\n  <div class="wrap">\n'
            f'    <h2 id="family-title">{title}</h2>\n    <ul class="family-grid">\n' + "\n".join(cards)
            + '\n    </ul>\n  </div>\n</aside>')

def family_credit(lang):
    """Crédito do rodapé: "Um produto Pururucos" com o logo, e o convite para falar com a empresa"""
    esc = htmllib.escape
    return (f'<a class="maker" href="{esc(maker_url(lang, "footer"))}" data-goatcounter-click="footer-pururucos">'
            f'<img src="{family_img(MAKER["logo"])}" width="16" height="16" alt="">{esc(MAKER["credit"][lang])}</a>'
            f' · <a href="{esc(maker_url(lang, "footer"))}" data-goatcounter-click="footer-pururucos-cta">{esc(MAKER["cta"][lang])}</a>')

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

def path(lang, page=""):
    """Caminho local de uma página num idioma ('' = principal, 'mac', 'linux', 'windows')"""
    if lang == "en":
        return f"/{page}" if page else "/"
    return f"/{lang}/{page}" if page else f"/{lang}"

def page_link(lang, page):
    return SITE + path(lang, page)

def page_hreflang(page):
    links = "\n".join(f'<link rel="alternate" hreflang="{LANGS[c][0]}" href="{page_link(c, page)}">' for c in LANGS)
    return links + f'\n<link rel="alternate" hreflang="x-default" href="{page_link("en", page)}">'

# Páginas que este script gera (as checagens de links aceitam todas, mesmo antes de serem escritas)
PAGES = {path(c, pg) for c in LANGS for pg in ("", "mac", "linux", "windows")}

# Menew para Windows ainda não tem versão: a página /windows fica com noindex e fora do sitemap até a primeira release
WINDOWS_RELEASED = False

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

def lang_paths(page=""):
    """Endereço de cada idioma ('' = página principal, 'linux' = a página do Linux)"""
    return "{" + ",".join(f"{c}:'" + (f"/{page}" if c == "en" else f"/{c}" + (f"/{page}" if page else "")) + "'" for c in LANGS) + "}"

LANG_PATHS = lang_paths()

def switch(current, paths=None):
    options = "".join(
        f'<option value="{code}"{" selected" if code == current else ""}>{name}</option>'
        for code, (_, name) in LANGS.items())
    return ('<select class="lang" aria-label="Language" onchange="'
            "try{localStorage.setItem('menew-lang',this.value)}catch(e){}"
            "try{goatcounter.count({path:'lang-'+this.value,event:true})}catch(e){}"
            # Endereços fixos: o valor do <select> nunca vira URL direto (alerta do CodeQL)
            "var u=" + (paths or LANG_PATHS) + "[this.value];if(u)location.href=u\">" + options + "</select>")

# "Alternativa a X" como as pessoas buscam em cada idioma
ALT = {"en": "alternative", "pt": "alternativa", "de": "Alternative", "es": "alternativa", "zh": "替代"}

# Dados estruturados: o Menew como aplicativo (grátis, macOS) e as perguntas frequentes da página
def jsonld(lang, texts):
    shots = "/assets" if lang == "en" else f"/assets/{lang}"
    app = {
        "@type": "SoftwareApplication",
        "name": "Menew",
        # O nome sozinho também é de um sistema de restaurantes (Linx Menew): estes deixam claro qual é qual
        "alternateName": ["Menew for Mac", "Menew Mac app", "Menew menu bar app", "Quost Menew"],
        "disambiguatingDescription": "Free, open source macOS menu bar app by Pururucos (pururucos.com.br; source at github.com/Quost/menew). Not related to Linx Menew, a restaurant point-of-sale system.",
        "url": url(lang),
        "description": htmllib.unescape(texts["meta_desc"]),
        "inLanguage": LANGS[lang][0],
        "operatingSystem": "macOS 14 or later",
        "applicationCategory": "UtilitiesApplication",
        "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
        "downloadUrl": "https://github.com/Quost/menew/releases/latest/download/Menew.dmg",
        "image": f"{SITE}/assets/og/{lang}.png",
        "screenshot": [f"{SITE}{shots}/{name}-dark.png" for name in
                       ("popover-now", "hub-memory", "hub-recordings", "palette", "panel0", "popover-actions",
                        "capture", "popover-notes")],
        "softwareVersion": VERSION,
        "dateModified": UPDATED,
        "featureList": [plain(texts[f"b{i}_t"]) + ": " + plain(texts[f"b{i}_d"]) for i in range(1, 6)]
                       + [plain(texts[f"f{i}_t"]) + ": " + plain(texts[f"f{i}_d"]) for i in range(1, 7)]
                       + [plain(texts[f"act_l{i}"]) for i in range(1, 11)]
                       + [plain(texts[f"nat{i}_t"]) + ": " + plain(texts[f"nat{i}_d"]) for i in range(1, 8)]
                       + [plain(texts[f"rep{i}_d"]) for i in range(1, N_REP + 1)],
        "license": "https://www.gnu.org/licenses/gpl-3.0.html",
        "isAccessibleForFree": True,
        "keywords": ", ".join(plain(texts[k]) for k in ("b1_t", "b2_t", "b3_t", "b4_t", "f2_t", "f1_t", "f3_t"))
                    + ", " + ", ".join(f"{n} {ALT[lang]}" for i in range(1, N_REP + 1) for n in texts[f"rep{i}_t"].split(" · ")),
        "author": PURURUCOS_ORG,
        "publisher": PURURUCOS_ORG,
        "sameAs": ["https://github.com/Quost/menew"],
    }
    faq = {
        "@type": "FAQPage",
        "mainEntity": [{"@type": "Question", "name": plain(texts[f"faq{i}_q"]),
                        "acceptedAnswer": {"@type": "Answer", "text": plain(texts[f"faq{i}_a"])}} for i in range(1, N_FAQ + 1)],
    }
    site = {"@type": "WebSite", "name": "Menew", "alternateName": "Menew for Mac", "url": url(lang), "inLanguage": LANGS[lang][0],
            "description": htmllib.unescape(texts["og_desc"])}
    return json.dumps({"@context": "https://schema.org", "@graph": [site, app, faq]}, ensure_ascii=False).replace("</", "<\\/")

# Capturas em WebP (cerca de 1/3 do tamanho do PNG): o site carrega mais rápido, o que também conta para o Google.
# Só as que as páginas mostram, e só onde o cwebp existe (brew install webp); no CI os .webp já vêm no repositório.
CWEBP = shutil.which("cwebp")

def webp_for(png):
    webp = png.with_suffix(".webp")
    if CWEBP and png.exists() and (not webp.exists() or webp.stat().st_mtime < png.stat().st_mtime):
        subprocess.run([CWEBP, "-quiet", "-q", "88", str(png), "-o", str(webp)], check=True)
    return webp

HERO = ("popover-now-dark",)  # na primeira tela: carregam já; o resto só quando chega perto

def optimize_images(page):
    def fix(m):
        tag, src = m.group(0), m.group(1)
        if webp_for(ROOT / "docs" / src.lstrip("/")).exists():
            tag = tag.replace(f'src="{src}"', f'src="{src[:-4]}.webp"')
        if 'class="shot' in tag and not any(h in src for h in HERO):
            tag = tag.replace("<img ", '<img loading="lazy" decoding="async" ', 1)
        return tag
    return re.sub(r'<img [^>]*src="(/assets/[^"]+\.png)"[^>]*>', fix, page)

english = json.loads((ROOT / "site/i18n/en.json").read_text())
# Quantas perguntas e comparações existem (faq1_q…, rep1_t…): crescem só com os textos
N_FAQ = sum(1 for k in english if re.fullmatch(r"faq\d+_q", k))
N_REP = sum(1 for k in english if re.fullmatch(r"rep\d+_t", k))
template = (ROOT / "site/template.html").read_text()
# Páginas "Menew vs X" (em inglês, onde estão as buscas "X alternative"): site/compare.json + site/compare.html
COMPARE = json.loads((ROOT / "site/compare.json").read_text())

def compare_links(label):
    links = " · ".join(f'<a href="/vs/{slug}" data-goatcounter-click="vs-{slug}">{htmllib.escape(c["other"])}</a>' for slug, c in COMPARE.items())
    return f'<p class="rep-note">{label} {links}</p>'

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
        "linux_path": path(lang, "linux"), "mac_path": path(lang, "mac"), "windows_path": path(lang, "windows"),
        "jsonld": jsonld(lang, texts),
        **{f"f{i}_d_fold": fold(texts[f"f{i}_d"], texts["more"]) for i in range(1, 7)},
        **{f"act_l{i}_fold": "<div>" + fold(texts[f"act_l{i}"], texts["more"], "span") + "</div>" for i in range(1, 11)},
        # Perguntas do FAQ: quantas houver nos textos (faq1_q, faq2_q…)
        "faq_items": "\n".join(f'      <details class="reveal"><summary>{texts[f"faq{i}_q"]}</summary><p>{texts[f"faq{i}_a"]}</p></details>'
                               for i in range(1, N_FAQ + 1)),
        "compare_links": compare_links(texts["compare_label"]),
        "family_band": family_band(lang), "family_credit": family_credit(lang),
        "analytics": ANALYTICS,
        "js_strings": json.dumps({**{k: texts[k] for k in ("version", "notch_meeting", "notch_join", "notch_focus")},
                                  **{k: htmllib.unescape(texts[k]) for k in ("platforms", "plat_linux_cta")}, "win_name": plain(texts["win_h1"]),
                                  "linux_path": path(lang, "linux"), "windows_path": path(lang, "windows")}, ensure_ascii=False),
    })
    page = re.sub(r"\{\{(\w+)\}\}", lambda m: values[m.group(1)], template)
    assert "{{" not in page, f"{lang}: marcador sem valor"
    page = optimize_images(page)
    out = ROOT / "docs" / ("index.html" if lang == "en" else f"{lang}/index.html")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(page)
    print(f"{lang}: {out.relative_to(ROOT)}")


# Páginas de comparação
ctpl = (ROOT / "site/compare.html").read_text()
# O CSS da faixa da Pururucos é o mesmo da página principal (entre os comentários "Pururucos: início/fim" do template)
FAMILY_STYLE = re.search(r"  /\* Pururucos: início.*?/\* Pururucos: fim \*/\n", template, re.S).group(0)
ctpl = ctpl.replace("{{family_style}}", FAMILY_STYLE.rstrip("\n"))
MARK = {"yes": ("✓ Yes", "yes"), "partial": ("◐ Partly", "partial"), "no": ("— No", "no")}
esc = htmllib.escape
for slug, c in COMPARE.items():
    rows = []
    for feature, menew, other, note in c["rows"]:
        n = f'<span class="note">{esc(note)}</span>' if note else ""
        rows.append(f'      <tr><td>{esc(feature)}{n}</td>'
                    f'<td class="mark {MARK[menew][1]}">{MARK[menew][0]}</td><td class="mark {MARK[other][1]}">{MARK[other][0]}</td></tr>')
    page_url = f"{SITE}/vs/{slug}"
    ld = {"@context": "https://schema.org", "@graph": [
        {"@type": "WebPage", "name": c["title"], "url": page_url, "description": c["description"], "inLanguage": "en",
         "about": {"@type": "SoftwareApplication", "name": "Menew", "alternateName": "Menew for Mac", "operatingSystem": "macOS",
                   "url": SITE + "/mac", "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
                   "author": PURURUCOS_ORG, "publisher": PURURUCOS_ORG},
         "dateModified": UPDATED},
        {"@type": "BreadcrumbList", "itemListElement": [
            {"@type": "ListItem", "position": 1, "name": "Menew", "item": SITE + "/"},
            {"@type": "ListItem", "position": 2, "name": "Comparisons", "item": f"{SITE}/vs"},
            {"@type": "ListItem", "position": 3, "name": f"Menew vs {c['other']}", "item": page_url}]},
    ]}
    values = {
        "title": esc(c["title"]), "description": esc(c["description"]), "url": page_url, "slug": slug,
        "other": esc(c["other"]), "short": esc(c["other"]), "intro": esc(c["intro"]),
        "rows": "\n".join(rows),
        "other_better": "".join(f"<li>{esc(x)}</li>" for x in c["other_better"]),
        "menew_better": "".join(f"<li>{esc(x)}</li>" for x in c["menew_better"]),
        "others": " ".join(f'<a href="/vs/{s2}">{esc(c2["other"])}</a>' for s2, c2 in COMPARE.items() if s2 != slug),
        "jsonld": json.dumps(ld, ensure_ascii=False).replace("</", "<\\/"),
        "analytics": ANALYTICS,
        "family_band": family_band("en"), "family_credit": family_credit("en"),
    }
    page = re.sub(r"\{\{(\w+)\}\}", lambda m: values[m.group(1)], ctpl)
    out = ROOT / "docs/vs" / slug / "index.html"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(page)
# Índice das comparações, com o mesmo visual
head, rest = ctpl.split("<main", 1)
cards = "".join(f'<div class="box" style="margin-bottom:14px"><h3><a href="/vs/{slug}">Menew vs {esc(c["other"])}</a></h3>'
                f'<p style="color:var(--muted);font-size:15px">{esc(c["description"])}</p></div>' for slug, c in COMPARE.items())
index_values = {"title": "Menew compared: free, open source alternatives for Mac utilities",
                "description": "How Menew, a free and open source Mac menu bar app, compares with Raycast, Maccy, Rectangle, iStat Menus, CleanShot X and Otter.",
                "url": f"{SITE}/vs", "short": "All", "jsonld": "{}", "analytics": ANALYTICS}
index = re.sub(r"\{\{(\w+)\}\}", lambda m: index_values.get(m.group(1), ""), head)
index += ('<main class="wrap"><header><div class="eyebrow">Comparisons</div><h1>Menew compared</h1>'
          '<p class="intro">Menew is one free, open source app for the Mac menu bar that covers the everyday part of several utilities. '
          'Here is how it compares, including where the specialized apps go further.</p></header><div style="margin-top:28px">'
          + cards + '</div><p class="disclaimer">Names are trademarks of their owners and appear only for comparison.</p></main>'
          + family_band("en") + '\n<footer><div class="wrap">' + family_credit("en") + '<br>Menew · <a href="/">menew.web.app</a> · '
          '<a href="https://github.com/Quost/menew" data-goatcounter-click="footer-source">Source on GitHub</a> · Not related to Linx Menew.</div></footer></body></html>\n')
(ROOT / "docs/vs/index.html").write_text(index)
print("docs/vs/ (" + str(len(COMPARE)) + " comparações)")

# Página /linux (Menew para Linux), nos 5 idiomas: site/linux.html + site/linux.json
# O CSS é o da página principal (lido do template); só o que é específico do Linux fica em site/linux.html
# Os textos e as capturas pertencem ao repositório menew-linux: clone raso da main, ou MENEW_LINUX_DIR (testes locais)
LINUX_REPO = "https://github.com/Quost/menew-linux"

def linux_source():
    local = os.environ.get("MENEW_LINUX_DIR")
    if local:
        return Path(local).expanduser().resolve()
    tmp = tempfile.mkdtemp(prefix="menew-linux-")
    atexit.register(shutil.rmtree, tmp, True)
    # MENEW_LINUX_REPO troca a origem do clone (um caminho ou URL), para testar sem mexer na main do menew-linux
    subprocess.run(["git", "clone", "--quiet", "--depth", "1", "--branch", "main", os.environ.get("MENEW_LINUX_REPO", LINUX_REPO), tmp], check=True)
    return Path(tmp)

LINUX_SRC = linux_source()
LINUX = json.loads((LINUX_SRC / "site/linux.json").read_text(encoding="utf-8"))
# Versão que o texto estático mostra (sem JS ou com a API fora do ar); a página atualiza sozinha ao carregar
LINUX_VERSION = re.search(r'^version = "([^"]+)"', (LINUX_SRC / "Cargo.toml").read_text(encoding="utf-8"), re.M).group(1)
LINUX_PRE = "-" in LINUX_VERSION
LINUX_RELEASE_URL = f"{LINUX_REPO}/releases/tag/v{LINUX_VERSION}"
# Capturas do menew-linux (docs/assets/*.png em inglês, docs/assets/<idioma>/*.png) para docs/assets/linux/ (fora do git)
LINUX_ASSETS = ROOT / "docs/assets/linux"
shutil.rmtree(LINUX_ASSETS, ignore_errors=True)
for png in sorted((LINUX_SRC / "docs/assets").glob("*.png")) + sorted((LINUX_SRC / "docs/assets").glob("*/*.png")):
    if png.name == "icon.png":
        continue
    dest = LINUX_ASSETS / png.relative_to(LINUX_SRC / "docs/assets")
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(png, dest)
linux_tpl = (ROOT / "site/linux.html").read_text()
STYLE = re.search(r"<style>\n(.*?)</style>", template, re.S).group(1)

def linux_url(lang):
    return f"{SITE}/linux" if lang == "en" else f"{SITE}/{lang}/linux"

linux_hreflang = "\n".join(f'<link rel="alternate" hreflang="{LANGS[c][0]}" href="{linux_url(c)}">' for c in LANGS)
linux_hreflang += f'\n<link rel="alternate" hreflang="x-default" href="{linux_url("en")}">'
N_PC = N_CC = 8
N_TOOLS = 6
N_NEXT = 5

def cards(texts, prefix, n):
    return "\n".join(f'      <div class="feature reveal"><h3>{texts[f"{prefix}{i}_t"]}</h3><p>{texts[f"{prefix}{i}_d"]}</p></div>'
                     for i in range(1, n + 1))

for lang in LANGS:
    t = LINUX[lang]
    home = json.loads((ROOT / f"site/i18n/{lang}.json").read_text())
    assert not (set(LINUX["en"]) - set(t)), f"linux {lang}: faltam {sorted(set(LINUX['en']) - set(t))}"
    shots = "/assets/linux" if lang == "en" else f"/assets/linux/{lang}"
    page_url = linux_url(lang)
    feats = [plain(t[f"pc{i}_t"]) + ": " + plain(t[f"pc{i}_d"]) for i in range(1, N_PC + 1)] \
          + [plain(t[f"cc{i}_t"]) + ": " + plain(t[f"cc{i}_d"]) for i in range(1, N_CC + 1)]           + [plain(t[f"tl{i}_t"]) + ": " + plain(t[f"tl{i}_d"]) for i in range(1, N_TOOLS + 1)]
    ld = {"@context": "https://schema.org", "@graph": [
        {"@type": "WebPage", "name": plain(t["title"]), "url": page_url, "description": htmllib.unescape(t["meta_desc"]),
         "inLanguage": LANGS[lang][0], "dateModified": UPDATED,
         "isPartOf": {"@type": "WebSite", "name": "Menew", "url": url(lang)}},
        {"@type": "SoftwareApplication", "name": "Menew for Linux", "alternateName": ["Menew Linux", "Quost Menew for Linux"],
         "disambiguatingDescription": "Free, open source Linux port of the Menew menu bar app by Pururucos (pururucos.com.br). Early preview releases for testers. Not related to Linx Menew, a restaurant point-of-sale system.",
         "url": page_url, "description": htmllib.unescape(t["meta_desc"]), "inLanguage": LANGS[lang][0],
         "operatingSystem": "Linux", "applicationCategory": "UtilitiesApplication",
         "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
         "image": f"{SITE}/assets/og/{lang}.png",
         "screenshot": [f"{SITE}{shots}/{n}-dark.png" for n in ("palette", "palette-conversion", "clipboard", "clipboard-images", "capture-editor", "monitor")],
         "featureList": feats, "license": "https://www.gnu.org/licenses/gpl-3.0.html", "isAccessibleForFree": True,
         "author": PURURUCOS_ORG, "publisher": PURURUCOS_ORG,
         "sameAs": [LINUX_REPO], "isBasedOn": {"@type": "SoftwareApplication", "name": "Menew", "operatingSystem": "macOS", "url": url(lang)}},
        {"@type": "BreadcrumbList", "itemListElement": [
            {"@type": "ListItem", "position": 1, "name": "Menew", "item": url(lang)},
            {"@type": "ListItem", "position": 2, "name": "Linux", "item": page_url}]},
    ]}
    values = dict(t)
    values.update({
        "html_lang": LANGS[lang][0], "url": page_url, "hreflang": linux_hreflang, "shots": shots,
        "home": "/" if lang == "en" else f"/{lang}", "mac_path": path(lang, "mac"),
        "og_image": f"{SITE}/assets/og/{lang}.png",
        "og_locale": {"en": "en_US", "pt": "pt_BR", "de": "de_DE", "es": "es_ES", "zh": "zh_CN"}[lang],
        "lang_switch": switch(lang, lang_paths("linux")),
        "jsonld": json.dumps(ld, ensure_ascii=False).replace("</", "<\\/"),
        "analytics": ANALYTICS, "style": STYLE,
        "palette_cards": cards(t, "pc", N_PC), "clipboard_cards": cards(t, "cc", N_CC), "tools_cards": cards(t, "tl", N_TOOLS),
        "release_url": LINUX_RELEASE_URL, "release_version": "v" + LINUX_VERSION,
        "badge_label": t["badge_pre"] if LINUX_PRE else t["badge_stable"], "next_cards": cards(t, "n", N_NEXT),
        "family_band": family_band(lang), "family_credit": family_credit(lang),
        **{k: home[k] for k in ("star", "license", "footer_source", "site_stats", "sponsor_button", "coffee_text", "coffee_button",
                                "footer_bug", "footer_contribute")},
    })
    page = re.sub(r"\{\{(\w+)\}\}", lambda m: values[m.group(1)], linux_tpl)
    assert "{{" not in page, f"linux {lang}: marcador sem valor"
    page = optimize_images(page)
    out = ROOT / "docs" / ("linux/index.html" if lang == "en" else f"{lang}/linux/index.html")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(page)
    print(f"linux {lang}: {out.relative_to(ROOT)}")
    # Todo src/srcset/href local da página precisa existir em docs/ (as capturas vieram do menew-linux)
    for ref in re.findall(r'(?:src|href)="(/(?!/)[^"#?]*)"', page):
        target = ROOT / "docs" / ref.lstrip("/")
        assert target.exists() or (target / "index.html").exists() or (ref.rstrip("/") or "/") in PAGES, f"linux {lang}: {ref} não existe em docs/"

# Páginas /mac e /windows, nos 5 idiomas: os textos ficam em site/i18n/<idioma>.json (mac_*, win_*, plat_*) junto com os da principal
mac_tpl = (ROOT / "site/mac.html").read_text(encoding="utf-8")
win_tpl = (ROOT / "site/windows.html").read_text(encoding="utf-8")
OG_LOCALE = {"en": "en_US", "pt": "pt_BR", "de": "de_DE", "es": "es_ES", "zh": "zh_CN"}

def platform_page(lang, page, tpl, ld, extra):
    texts = json.loads((ROOT / f"site/i18n/{lang}.json").read_text(encoding="utf-8"))
    values = dict(texts)
    values.update({
        "html_lang": LANGS[lang][0], "url": page_link(lang, page), "hreflang": page_hreflang(page),
        "home": path(lang), "mac_path": path(lang, "mac"), "linux_path": path(lang, "linux"), "windows_path": path(lang, "windows"),
        "shots": "/assets" if lang == "en" else f"/assets/{lang}",
        "og_image": f"{SITE}/assets/og/{lang}.png", "og_locale": OG_LOCALE[lang],
        "lang_switch": switch(lang, lang_paths(page)), "style": STYLE, "analytics": ANALYTICS,
        "jsonld": json.dumps(ld, ensure_ascii=False).replace("</", "<\\/"),
        "family_band": family_band(lang), "family_credit": family_credit(lang),
        **extra(texts),
    })
    out_page = re.sub(r"\{\{(\w+)\}\}", lambda m: values[m.group(1)], tpl)
    assert "{{" not in out_page, f"{page} {lang}: marcador sem valor"
    out_page = optimize_images(out_page)
    out = ROOT / "docs" / path(lang, page).lstrip("/") / "index.html"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(out_page, encoding="utf-8")
    for ref in re.findall(r'(?:src|href)="(/(?!/)[^"#?]*)"', out_page):
        target = ROOT / "docs" / ref.lstrip("/")
        assert target.exists() or (target / "index.html").exists() or (ref.rstrip("/") or "/") in PAGES, f"{page} {lang}: {ref} não existe em docs/"
    print(f"{page} {lang}: {out.relative_to(ROOT)}")

for lang in LANGS:
    texts = json.loads((ROOT / f"site/i18n/{lang}.json").read_text(encoding="utf-8"))
    mac_url = page_link(lang, "mac")
    platform_page(lang, "mac", mac_tpl, {"@context": "https://schema.org", "@graph": [
        {"@type": "WebPage", "name": plain(texts["mac_title"]), "url": mac_url, "description": plain(texts["mac_meta_desc"]),
         "inLanguage": LANGS[lang][0], "dateModified": UPDATED, "isPartOf": {"@type": "WebSite", "name": "Menew", "url": url(lang)},
         "about": {"@type": "SoftwareApplication", "name": "Menew", "alternateName": "Menew for Mac", "url": mac_url,
                   "operatingSystem": "macOS 14 or later", "applicationCategory": "UtilitiesApplication",
                   "downloadUrl": "https://github.com/Quost/menew/releases/latest/download/Menew.dmg", "softwareVersion": VERSION,
                   "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"}, "isAccessibleForFree": True,
                   "license": "https://www.gnu.org/licenses/gpl-3.0.html", "author": PURURUCOS_ORG, "publisher": PURURUCOS_ORG}},
        {"@type": "BreadcrumbList", "itemListElement": [
            {"@type": "ListItem", "position": 1, "name": "Menew", "item": url(lang)},
            {"@type": "ListItem", "position": 2, "name": "Mac", "item": mac_url}]},
    ]}, lambda tx: {"js_strings": json.dumps({"copied": tx["copied"], "version": tx["version"], "ai_prompt": tx["ai_prompt"],
                                              "platforms": htmllib.unescape(tx["platforms"])}, ensure_ascii=False)})
    win_url = page_link(lang, "windows")
    platform_page(lang, "windows", win_tpl, {"@context": "https://schema.org", "@graph": [
        {"@type": "WebPage", "name": plain(texts["win_title"]), "url": win_url, "description": plain(texts["win_meta_desc"]),
         "inLanguage": LANGS[lang][0], "dateModified": UPDATED, "isPartOf": {"@type": "WebSite", "name": "Menew", "url": url(lang)}},
        {"@type": "BreadcrumbList", "itemListElement": [
            {"@type": "ListItem", "position": 1, "name": "Menew", "item": url(lang)},
            {"@type": "ListItem", "position": 2, "name": "Windows", "item": win_url}]},
    ]}, lambda tx: {"robots": "index, follow" if WINDOWS_RELEASED else "noindex, follow"})

# Mapa do site (com as versões em cada idioma) e robots.txt para os buscadores
alternates = "".join(f'\n    <xhtml:link rel="alternate" hreflang="{LANGS[c][0]}" href="{url(c)}"/>' for c in LANGS)
entries = "".join(f"\n  <url>\n    <loc>{url(c)}</loc>\n    <lastmod>{UPDATED}</lastmod>{alternates}\n  </url>" for c in LANGS)
entries += "".join(f"\n  <url>\n    <loc>{SITE}/vs{p}</loc>\n    <lastmod>{UPDATED}</lastmod>\n  </url>"
                   for p in [""] + [f"/{slug}" for slug in COMPARE])
linux_alternates = "".join(f'\n    <xhtml:link rel="alternate" hreflang="{LANGS[c][0]}" href="{linux_url(c)}"/>' for c in LANGS)
entries += "".join(f"\n  <url>\n    <loc>{linux_url(c)}</loc>\n    <lastmod>{UPDATED}</lastmod>{linux_alternates}\n  </url>" for c in LANGS)
for extra_page in ["mac"] + (["windows"] if WINDOWS_RELEASED else []):
    page_alternates = "".join(f'\n    <xhtml:link rel="alternate" hreflang="{LANGS[c][0]}" href="{page_link(c, extra_page)}"/>' for c in LANGS)
    entries += "".join(f"\n  <url>\n    <loc>{page_link(c, extra_page)}</loc>\n    <lastmod>{UPDATED}</lastmod>{page_alternates}\n  </url>" for c in LANGS)
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
    "Free and open source (GPL-3.0). Signed with an Apple Developer ID and notarized. "
    "Made by Pururucos (https://pururucos.com.br), a software house in Brazil; the source code is at github.com/Quost/menew.", "",
    "## Highlights", "",
    *[f"- {plain(e[f'b{i}_t'])}: {plain(e[f'b{i}_d'])}" for i in range(1, 6)], "",
    "## Capabilities in detail", "",
    *[f"- {name}: {text}" for name, text in FACTS], "",
    "## Not included", "",
    NOT_INCLUDED, "",
    "## Name", "",
    "Menew (also written Menew for Mac) is the macOS app by Pururucos, published at github.com/Quost/menew. It is not related to Linx Menew, a restaurant point-of-sale system in Brazil.", "",
    "## One app instead of many", "",
    *[f"- Instead of {e[f'rep{i}_t'].replace(' · ', ' or ')}: {plain(e[f'rep{i}_d'])}" for i in range(1, N_REP + 1)], "",
    "## Features", "",
    *[f"- {plain(e[f'f{i}_t'])}: {plain(e[f'f{i}_d'])}" for i in range(1, 7)], "",
    "## More features", "",
    *[f"- {plain(e[f'act_l{i}'])}" for i in range(1, 11)],
    *[f"- {plain(e[f'nat{i}_t'])}: {plain(e[f'nat{i}_d'])}" for i in range(1, 8)],
    *[f"- {plain(e[f'pro{i}_t'])}: {plain(e[f'pro{i}_d'])}" for i in range(1, 7)], "",
    "## FAQ", "",
    *[f"### {plain(e[f'faq{i}_q'])}\n\n{plain(e[f'faq{i}_a'])}\n" for i in range(1, N_FAQ + 1)],
    "## Install", "",
    f"- Mac download page (DMG, Homebrew, from source, requirements): {SITE}/mac",
    "- Download: https://github.com/Quost/menew/releases/latest/download/Menew.dmg",
    "- Homebrew: `brew tap quost/menew https://github.com/Quost/menew && brew install --cask menew`", "",
    "## Links", "",
    f"- Website: {SITE}/ (also in Portuguese, German, Spanish and Chinese: {SITE}/pt, {SITE}/de, {SITE}/es, {SITE}/zh)",
    "- Source code and README: https://github.com/Quost/menew",
    f"- Menew for Linux (early preview releases for testers: command palette, clipboard history, notes, screenshots, QR codes and system monitor for GNOME and KDE Plasma): {SITE}/linux (also {SITE}/pt/linux, {SITE}/de/linux, {SITE}/es/linux, {SITE}/zh/linux); source: https://github.com/Quost/menew-linux",
    f"- Menew for Windows: in progress, no release yet (command palette, clipboard history and notes); watch https://github.com/Quost/menew-windows for releases ({SITE}/windows)",
    *[f"- Menew vs {c['other']}: {SITE}/vs/{slug}" for slug, c in COMPARE.items()],
    "- Releases and changelog: https://github.com/Quost/menew/releases",
    f"- Made by Pururucos: {MAKER['url']} (other apps: "
    + ", ".join(f"{p['name']} {p['url']}" for p in FAMILY["products"] if p["id"] != "menew") + ")",
]
(ROOT / "docs/llms.txt").write_text("\n".join(lines) + "\n")
print("docs/llms.txt")
