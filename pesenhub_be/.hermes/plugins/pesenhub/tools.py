"""Network handlers for the PesenHub Hermes plugin."""

import json
import os
from urllib import error, parse, request

MAX_RESPONSE_BYTES = 2 * 1024 * 1024


def _failure(message: str) -> str:
    return json.dumps({"error": message}, separators=(",", ":"))


def fetch_catalog(params: dict) -> str:
    """Fetch the protected catalog and return a JSON string to Hermes."""
    base_url = os.getenv("PESENHUB_API_BASE_URL", "").strip().rstrip("/")
    api_key = os.getenv("HERMES_TOOL_API_KEY", "").strip()
    parsed_base = parse.urlparse(base_url)
    if parsed_base.scheme not in {"http", "https"} or not parsed_base.netloc:
        return _failure("PESENHUB_API_BASE_URL is not configured correctly")
    if not api_key:
        return _failure("HERMES_TOOL_API_KEY is not configured")

    category_id = str((params or {}).get("category_id", "")).strip()
    query = ""
    if category_id:
        query = "?" + parse.urlencode({"category_id": category_id})
    endpoint = f"{base_url}/api/v1/hermes/tools/catalog{query}"
    http_request = request.Request(
        endpoint,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Accept": "application/json",
        },
        method="GET",
    )

    try:
        with request.urlopen(http_request, timeout=5) as response:
            raw = response.read(MAX_RESPONSE_BYTES + 1)
    except (error.HTTPError, error.URLError, TimeoutError):
        return _failure("PesenHub catalog is temporarily unavailable")

    if len(raw) > MAX_RESPONSE_BYTES:
        return _failure("PesenHub catalog response exceeded the safe size limit")
    try:
        payload = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError):
        return _failure("PesenHub catalog returned invalid JSON")
    if not isinstance(payload, dict) or not isinstance(payload.get("data"), list):
        return _failure("PesenHub catalog returned an invalid schema")
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
