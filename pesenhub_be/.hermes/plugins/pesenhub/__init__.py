"""Hermes plugin exposing the narrow PesenHub catalog tool."""

from .schemas import CATALOG_SCHEMA
from .tools import fetch_catalog


def register(ctx):
    ctx.register_tool(
        name="pesenhub_catalog",
        toolset="pesenhub",
        schema=CATALOG_SCHEMA,
        handler=lambda params, **kwargs: fetch_catalog(params),
    )
