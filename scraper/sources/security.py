from __future__ import annotations

import logging
import re
from datetime import datetime
from typing import Any

import httpx

from scraper.models import Article

_logger = logging.getLogger(__name__)

_CVE_PATTERN = re.compile(r"CVE-\d{4}-\d+", re.IGNORECASE)
_RELEVANT_KEYWORDS = ("openshift", "ocp", "kubernetes", "container", "podman")

# Red Hat deprecated the legacy RSS errata feeds in favor of the JSON
# Security Data API. We query it once per relevant package keyword and
# dedupe by CVE id.
_API_URL = "https://access.redhat.com/hydra/rest/securitydata/cve.json"
_PACKAGE_QUERIES = ("openshift", "kubernetes", "podman")
_PER_PAGE = 50
_SOURCE = "Red Hat Security"
_BASE_TAGS = ["security", "advisory"]


def _parse_public_date(raw: str | None) -> datetime | None:
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None


def _is_relevant(entry: dict[str, Any]) -> bool:
    title = entry.get("bugzilla_description") or entry.get("CVE") or ""
    haystack = title.lower()
    packages = entry.get("affected_packages") or []
    for pkg in packages:
        haystack += f" {str(pkg).lower()}"
    return any(keyword in haystack for keyword in _RELEVANT_KEYWORDS)


def _article_from_cve(entry: dict[str, Any]) -> Article | None:
    cve_id = entry.get("CVE")
    if not cve_id:
        return None

    description = entry.get("bugzilla_description") or ""
    severity = entry.get("severity")
    public_date = entry.get("public_date")

    title = f"{cve_id}: {description}".strip(": ").strip()
    if not title:
        title = cve_id

    url = f"https://access.redhat.com/security/cve/{cve_id}"

    tags = list(_BASE_TAGS)
    tags.append("cve")
    if severity:
        tags.append(str(severity).lower())
    tags.append(cve_id.upper())

    for cve in _CVE_PATTERN.findall(description)[:2]:
        cve_upper = cve.upper()
        if cve_upper not in tags:
            tags.append(cve_upper)

    return Article(
        title=title,
        url=url,
        source=_SOURCE,
        tags=tags,
        summary=description or None,
        published_at=_parse_public_date(public_date),
    )


def _fetch_package(client: httpx.Client, package: str) -> list[dict[str, Any]]:
    try:
        response = client.get(
            _API_URL,
            params={"package": package, "per_page": _PER_PAGE},
            timeout=10.0,
        )
        response.raise_for_status()
        payload = response.json()
    except Exception:
        _logger.exception(
            "Failed to fetch Red Hat Security CVEs for package=%s", package
        )
        return []

    if not isinstance(payload, list):
        _logger.warning("Unexpected payload for package=%s: %r", package, payload)
        return []
    return payload


def fetch_security_advisories() -> list[Article]:
    articles: list[Article] = []
    seen_cves: set[str] = set()

    with httpx.Client(follow_redirects=True) as client:
        for package in _PACKAGE_QUERIES:
            _logger.info(
                "Fetching security advisories: %s (package=%s)",
                _SOURCE,
                package,
            )
            for entry in _fetch_package(client, package):
                try:
                    cve_id = entry.get("CVE")
                    if not cve_id or cve_id in seen_cves:
                        continue
                    if not _is_relevant(entry):
                        continue
                    article = _article_from_cve(entry)
                    if article is None:
                        continue
                    seen_cves.add(cve_id)
                    articles.append(article)
                except Exception:
                    _logger.exception(
                        "Failed to process CVE entry: %r", entry.get("CVE")
                    )

    return articles
