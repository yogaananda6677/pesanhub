#!/usr/bin/env python3
"""
PesenHub Live Catalog Fetcher for Hermes Agent
Retrieves real-time menu items, prices, modifiers, and availability from PesenHub API.
"""

import sys
import os
import json
import argparse
import urllib.request
import urllib.error

DEFAULT_API_URL = os.getenv("PESENHUB_API_URL", "http://localhost:8080")
DEFAULT_API_KEY = os.getenv("HERMES_TOOL_API_KEY", "replace_with_hermes_tool_key_at_least_32_charsxx")

def fetch_catalog(base_url, api_key, category_id=None):
    url = f"{base_url.rstrip('/')}/api/v1/hermes/tools/catalog"
    if category_id:
        url += f"?category_id={category_id}"

    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {api_key}",
        "Accept": "application/json"
    })

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data.get("data", [])
    except urllib.error.HTTPError as e:
        sys.stderr.write(f"HTTP Error {e.code}: {e.read().decode('utf-8')}\n")
        sys.exit(1)
    except Exception as e:
        sys.stderr.write(f"Failed to fetch catalog: {e}\n")
        sys.exit(1)

def format_text(categories, available_only=True):
    lines = []
    lines.append("=== DAFTAR MENU REALTIME PESENHUB ===")
    for cat in categories:
        cat_name = cat.get("name", "Kategori")
        cat_desc = cat.get("description", "")
        lines.append(f"\n📂 [{cat_name}] {cat_desc}")

        menus = cat.get("menus", [])
        if not menus:
            lines.append("  (Tidak ada menu)")
            continue

        for m in menus:
            is_avail = m.get("is_available", False)
            if available_only and not is_avail:
                continue

            status_str = "Tersedia" if is_avail else "HABIS"
            price = m.get("price_amount", 0)
            lines.append(f"  • {m.get('name')} - Rp {price:,} [{status_str}]")
            if m.get("description"):
                lines.append(f"    Deskripsi: {m.get('description')}")

            groups = m.get("modifier_groups", [])
            for g in groups:
                opts = [f"{o.get('name')} (+Rp {o.get('price_delta_amount', 0):,})" if o.get('price_delta_amount', 0) > 0 else o.get('name') for o in g.get("options", []) if o.get("is_available", True)]
                lines.append(f"    Varian [{g.get('name')}]: {', '.join(opts) if opts else 'Tidak ada opsi'}")
    return "\n".join(lines)

def main():
    parser = argparse.ArgumentParser(description="Fetch live PesenHub catalog for Hermes CS")
    parser.add_argument("--url", default=DEFAULT_API_URL, help="PesenHub API base URL")
    parser.add_argument("--key", default=DEFAULT_API_KEY, help="Hermes tool API key")
    parser.add_argument("--category", default=None, help="Filter by category ID")
    parser.add_argument("--all", action="store_true", help="Include unavailable items")
    parser.add_argument("--json", action="store_true", help="Output raw JSON")

    args = parser.parse_args()
    cats = fetch_catalog(args.url, args.key, args.category)

    if args.json:
        print(json.dumps(cats, indent=2))
    else:
        print(format_text(cats, available_only=not args.all))

if __name__ == "__main__":
    main()
