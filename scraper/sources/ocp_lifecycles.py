"""Synchronize OpenShift lifecycle dates from Red Hat's product API.

The API is the source of truth for lifecycle boundaries.  In particular an
EUS release can have several purchased EUS terms; ``eus_end`` is the final
date among the base term and Terms 2 and 3, not merely the first EUS end.
"""

from __future__ import annotations

import json
import logging
import re
from dataclasses import dataclass
from datetime import date, datetime, timezone

from scraper.sources.safe_fetch import FeedFetchError, fetch_feed_bytes

PRODUCT_API_URL = (
    "https://access.redhat.com/product-life-cycles/api/v1/products?"
    "name=Red%20Hat%20OpenShift%20Container%20Platform"
)
_PRODUCT_NAME = "Red Hat OpenShift Container Platform"
_MINOR_VERSION_RE = re.compile(r"^\d+\.\d+$")
_EUS_PHASE_RE = re.compile(r"^Extended update support(?: Term [123])?$", re.I)
_REQUIRED_PHASES = {
    "General availability": "ga",
    "Full support": "full_support_end",
    "Maintenance support": "maintenance_end",
}

_logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class OcpLifecycle:
    minor_version: str
    ga: date
    full_support_end: date
    maintenance_end: date
    eus_end: date | None

    @property
    def is_eus(self) -> bool:
        return self.eus_end is not None


def _parse_date(value: object) -> date | None:
    """Parse an API ISO timestamp, returning None for values such as N/A."""
    if not isinstance(value, str) or value == "N/A":
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).date()
    except ValueError:
        return None


def parse_ocp_lifecycles(payload: str | bytes) -> list[OcpLifecycle]:
    """Extract valid minor-version lifecycle records from an API response."""
    decoded = json.loads(payload)
    if not isinstance(decoded, dict):
        raise ValueError("product lifecycle response is not an object")
    products = decoded.get("data")
    if not isinstance(products, list):
        raise ValueError("product lifecycle response has no data list")
    product = next(
        (item for item in products if item.get("name") == _PRODUCT_NAME), None
    )
    if not isinstance(product, dict):
        raise ValueError(f"response did not contain {_PRODUCT_NAME!r}")

    lifecycles: list[OcpLifecycle] = []
    for version in product.get("versions", []):
        if not isinstance(version, dict):
            continue
        minor = version.get("name")
        if not isinstance(minor, str) or not _MINOR_VERSION_RE.fullmatch(minor):
            continue
        phase_ends: dict[str, date] = {}
        eus_ends: list[date] = []
        for phase in version.get("phases", []):
            if not isinstance(phase, dict):
                continue
            name = phase.get("name")
            end = _parse_date(phase.get("end_date"))
            if not isinstance(name, str) or end is None:
                continue
            field = _REQUIRED_PHASES.get(name)
            if field:
                phase_ends[field] = end
            elif _EUS_PHASE_RE.fullmatch(name):
                eus_ends.append(end)
        if set(phase_ends) != set(_REQUIRED_PHASES.values()):
            _logger.warning("Skipping %s: missing required lifecycle dates", minor)
            continue
        lifecycles.append(
            OcpLifecycle(
                minor_version=minor,
                ga=phase_ends["ga"],
                full_support_end=phase_ends["full_support_end"],
                maintenance_end=phase_ends["maintenance_end"],
                eus_end=max(eus_ends, default=None),
            )
        )
    return lifecycles


def fetch_ocp_lifecycles(supabase_client) -> int:
    """Fetch lifecycle data and merge it into existing OCP channel rows.

    ``ocp_versions`` remains owned by the Cincinnati channel scraper for
    ``latest_stable``.  This synchronizer only enriches channels that already
    exist there, so it never manufactures a version without a stable release.
    """
    try:
        lifecycles = parse_ocp_lifecycles(fetch_feed_bytes(PRODUCT_API_URL))
    except (FeedFetchError, ValueError, json.JSONDecodeError) as error:
        _logger.error("Failed to fetch OCP lifecycle data: %s", error)
        return 0

    try:
        result = (
            supabase_client.client.table("ocp_versions")
            .select("minor_version, latest_stable")
            .execute()
        )
        existing = {
            row["minor_version"]: row["latest_stable"]
            for row in (result.data or [])
        }
    except Exception as error:
        _logger.error("Failed to load OCP versions for lifecycle sync: %s", error)
        return 0

    synced = 0
    for lifecycle in lifecycles:
        latest_stable = existing.get(lifecycle.minor_version)
        if latest_stable is None:
            continue
        try:
            supabase_client.client.table("ocp_versions").upsert(
                {
                    "minor_version": lifecycle.minor_version,
                    "latest_stable": latest_stable,
                    "ga": lifecycle.ga.isoformat(),
                    "is_eus": lifecycle.is_eus,
                    "full_support_end": lifecycle.full_support_end.isoformat(),
                    "maintenance_end": lifecycle.maintenance_end.isoformat(),
                    "eus_end": (
                        lifecycle.eus_end.isoformat()
                        if lifecycle.eus_end is not None
                        else None
                    ),
                    "updated_at": datetime.now(timezone.utc).isoformat(),
                },
                on_conflict="minor_version",
            ).execute()
            synced += 1
        except Exception:
            _logger.exception("Failed to save lifecycle for %s", lifecycle.minor_version)
    return synced
