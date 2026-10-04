"""Model-visible schemas for the PesenHub plugin."""

CATALOG_SCHEMA = {
    "name": "pesenhub_catalog",
    "description": (
        "Fetch the current read-only PesenHub menu catalog, availability, "
        "modifier choices, and backend-authoritative prices."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "category_id": {
                "type": "string",
                "description": "Optional exact category ID; omit to fetch all active categories.",
            }
        },
        "additionalProperties": False,
    },
}
