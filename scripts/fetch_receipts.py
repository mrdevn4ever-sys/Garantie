#!/usr/bin/env python3
"""Lädt frei lizenzierte Belegfotos von Wikimedia Commons für den Erkennungstest.

Die Bilder werden nur zur Laufzeit geladen und nicht ins Repository übernommen.
Titel, Urheber und Lizenz jedes Bildes stehen in <Zielordner>/quellen.json.
"""
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

API = "https://commons.wikimedia.org/w/api.php"
AGENT = "ReceiptRecognitionEval/1.0 (automated CI test; Python urllib)"
QUERIES = [
    "Kassenbon", "Kassenzettel", "Kassenbeleg", "Quittung Kasse", "Rechnung Kassenbon Supermarkt",
    "Kassenbon Mediamarkt", "Kassenbon Elektronik", "Quittung Migros", "Quittung Coop", "Kassenbon Rewe",
    "Kassenbon Aldi", "Kassenbon Lidl", "Kassenbon dm", "Kassenbon Ikea", "Kassenbon Baumarkt",
    "ticket de caisse", "scontrino", "receipt supermarket", "sales receipt", "till receipt",
]
PER_QUERY = 6
LIMIT = int(sys.argv[2]) if len(sys.argv) > 2 else 45


def get(url):
    request = urllib.request.Request(url, headers={"User-Agent": AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def strip_html(text):
    return re.sub(r"<[^>]+>", "", text or "").strip()


def main():
    target = sys.argv[1] if len(sys.argv) > 1 else "receipts"
    os.makedirs(target, exist_ok=True)
    seen, sources = set(), []
    for query in QUERIES:
        if len(sources) >= LIMIT:
            break
        params = {
            "action": "query", "format": "json", "generator": "search",
            "gsrsearch": f"filetype:bitmap {query}", "gsrnamespace": "6", "gsrlimit": str(PER_QUERY),
            "prop": "imageinfo", "iiprop": "url|size|mime|extmetadata", "iiurlwidth": "2000",
        }
        try:
            data = json.loads(get(API + "?" + urllib.parse.urlencode(params)))
        except Exception as error:  # noqa: BLE001
            print(f"Suche '{query}' fehlgeschlagen: {error}")
            continue
        pages = sorted(data.get("query", {}).get("pages", {}).values(), key=lambda p: p.get("index", 0))
        for page in pages:
            if len(sources) >= LIMIT:
                break
            title = page.get("title", "")
            info = (page.get("imageinfo") or [{}])[0]
            if title in seen or info.get("mime") not in ("image/jpeg", "image/png"):
                continue
            # Sehr kleine Bilder sind für eine Texterkennung nicht aussagekräftig.
            if min(info.get("width", 0), info.get("height", 0)) < 500:
                continue
            seen.add(title)
            url = info.get("thumburl") or info.get("url")
            extension = ".png" if info.get("mime") == "image/png" else ".jpg"
            name = f"{len(sources) + 1:02d}_" + re.sub(r"[^A-Za-z0-9]+", "_", title.replace("File:", ""))[:60] + extension
            try:
                with open(os.path.join(target, name), "wb") as handle:
                    handle.write(get(url))
            except Exception as error:  # noqa: BLE001
                print(f"Download {title} fehlgeschlagen: {error}")
                continue
            meta = info.get("extmetadata", {})
            sources.append({
                "datei": name, "titel": title, "suche": query,
                "seite": info.get("descriptionurl", ""),
                "urheber": strip_html(meta.get("Artist", {}).get("value", "")),
                "lizenz": meta.get("LicenseShortName", {}).get("value", ""),
            })
            print(f"{name}  <- {title}  [{sources[-1]['lizenz']}]  Suche: {query}")
            time.sleep(0.5)
    with open(os.path.join(target, "quellen.json"), "w", encoding="utf-8") as handle:
        json.dump(sources, handle, ensure_ascii=False, indent=2)
    print(f"{len(sources)} Bilder geladen")
    if not sources:
        sys.exit(1)


if __name__ == "__main__":
    main()
