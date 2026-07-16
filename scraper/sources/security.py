"""
Fetches Red Hat Security Data API CVEs and emits Article rows.

When score data is available the resulting articles also carry a
``cvss:X.X`` tag (e.g. ``cvss:8.5``) which Phase 4 alert rules read to
decide whether a CVE clears the user's CVSS threshold.
"""

from __future__ import annotations

import logging
import re
from datetime import datetime
from typing import Any

import httpx

from scraper.models import Article
from scraper.sources.cve_enrichment import extract_cvss_score
from scraper.sources.relevance import evaluate_relevance

_logger = logging.getLogger(__name__)

_CVE_PATTERN = re.compile(r"CVE-\d{4}-\d+", re.IGNORECASE)

# Red Hat deprecated the legacy RSS errata feeds in favor of the JSON
# Security Data API. We query it once per relevant package keyword and
# dedupe by CVE id.
_API_URL = "https://access.redhat.com/hydra/rest/securitydata/cve.json"
_PACKAGE_QUERIES = ("openshift", "kubernetes", "podman", "quay", "istio", "servicemesh")
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
    """True if a Hydra CVE entry looks relevant to this app's audience.

    The haystack is the description (falling back to the bare CVE id) plus
    every affected package name — never the summary. Matching itself lives
    in :func:`~scraper.sources.relevance.evaluate_relevance` so the keyword
    set stays shared with the content filter in ``rss.py``.
    """
    title = entry.get("bugzilla_description") or entry.get("CVE") or ""
    haystack = title.lower()
    packages = entry.get("affected_packages") or []
    for pkg in packages:
        haystack += f" {str(pkg).lower()}"
    return evaluate_relevance(haystack).passed


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

    # The LIST endpoint's flat cvss3_score. Shape handling lives in
    # cve_enrichment so there is exactly one extractor across the scraper.
    cvss_score = extract_cvss_score(entry)
    if cvss_score is not None:
        tags.append(f"cvss:{cvss_score:.1f}")

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
