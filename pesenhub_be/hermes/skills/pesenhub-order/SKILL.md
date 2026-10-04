---
name: pesenhub-order
description: "Real-time menu catalog lookup, live pricing, stock availability, and WhatsApp order customer service for PesenHub outlets."
version: 1.0.0
author: PesenHub Team
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [PesenHub, FoodOrder, Catalog, Realtime, CustomerService]
---

# PesenHub Order & Catalog Skill

Provides Hermes Agent with real-time access to PesenHub outlet food & drink catalog, prices, active modifier groups, item availability, and order customer service.

## When to Use

- When a customer asks for the menu, prices, available food/drinks, or recommendations.
- When checking if a specific menu item or variant is currently in stock.
- When verifying order details or line-item prices before drafting an order.

## Tools & Helper Scripts

### 1. Realtime Catalog Lookup

Run `python3 scripts/catalog.py`:

```bash
# View all available menus formatted nicely for CS
python3 scripts/catalog.py

# Include out-of-stock items
python3 scripts/catalog.py --all

# Output raw JSON for structured processing
python3 scripts/catalog.py --json

# Filter by category
python3 scripts/catalog.py --category <category_id>
```

### 2. Environment Variables

- `PESENHUB_API_URL`: Backend API base URL (defaults to `http://localhost:8080`)
- `HERMES_TOOL_API_KEY`: Hermes dedicated tool API key

## Conversational Customer Service Guidelines

1. **Warm & Natural**: Always address customers politely in conversational Indonesian ("Halo kak [Name]!").
2. **Never Demand Rigid Bot Commands**: Do NOT tell customers "Ketik Ya" or "Ketik Batal". Converse naturally and understand their conversational confirmation (e.g. "iya bungkus", "pas kok", "gas kak", "lanjut").
3. **Remember Customer Identity**: When a customer shares their name, acknowledge it and address them by name across the conversation.
4. **Catalog Grounding**: Always base menu availability and prices on live catalog data retrieved from the backend API. Never hallucinate dishes or prices not on the menu.
