# Website content (/mac)

The page https://menew.pururucos.com.br/mac (and `/pt/mac`, `/de/mac`, `/es/mac`, `/zh/mac`) gets its texts and screenshots from this repository. Everything else (layout, the overview page, `/vs`, SEO, hosting) lives in [Quost/menew-site](https://github.com/Quost/menew-site), whose README describes the content contract in full.

## What lives here

- `site/content.json`: every text of the `/mac` page in the 5 languages (`en`, `pt`, `de`, `es`, `zh`), with the same keys in each. A little inline HTML is allowed (`<b>`, `<code>`, `<span class="grad">`…). `"contract": 1` and `"platform": "mac"` identify the format.
- `docs/assets/*` (English) and `docs/assets/<lang>/*`: the screenshots, the same files the README uses (`"assets": "../docs/assets"` in `content.json`). The site publishes them under `/assets/`, and the overview page shows them too. Keep a `.webp` next to each PNG the site shows (`scripts/webp.sh`).

Which keys the page needs is decided by the template in menew-site (`site/templates/mac.html`). If a check fails, the message lists the missing keys, languages or screenshots.

## What updates by itself

- Versions and download links come from this repository's GitHub Releases when the site is built (and in the browser when the page loads). Nothing to change for a release.
- menew-site checks this repository every 30 minutes and rebuilds when `site/` or `docs/assets/` changed on `main`, or a new release is out. No token or workflow is needed here.

## Check and preview

```sh
# from a checkout of Quost/menew-site next to this repository
python3 scripts/content.py mac ../menew/site                    # validate (CI runs the same)
python3 scripts/build.py --content mac=../menew/site --serve    # preview at http://localhost:8000/mac
```

## Rules

English, Portuguese, German, Spanish and Chinese for every text. No em-dash. Never add generated pages, templates or deploy files here.
