"""
Detects Red Hat GA releases of OpenShift layered products (operators).

Unlike :mod:`~scraper.sources.github_releases` (a release-event feed) or
:mod:`~scraper.sources.ocp_versions` (Cincinnati channel files), the
authoritative record for layered-product GAs is a support-policy *page* —
it carries no release events, only current state. So this module scrapes
the page and detects new GAs by diffing each operator's version against a
persisted ``{operator_key: latest_version}`` record, the same way
``ocp_versions.py`` diffs stable channels.

Only the **version** is compared. The page churns constantly on
support-end dates; a date-only edit must emit nothing.

These articles are **deliberately push-silent**: they are tagged
``layered-release``, not ``release``, so they never satisfy the topic-push
condition at ``main.py:142`` (``"release" in a.tags``). The intent is to
hold pushes until we've seen the real GA volume across ~60 operators. See
``_tags_for``. (Caveat: a Pro user's *custom alert rule* with empty
categories matches every new article regardless of tag, so it can still
push these per-token — that path is intentionally untouched.)

Supabase table setup (run once in the Supabase SQL editor):

    create table if not exists operator_versions (
      id uuid primary key default gen_random_uuid(),
      operator_key text not null unique,
      operator_name text not null,
      tier text not null,
      latest_version text not null,
      updated_at timestamptz default now()
    );

    alter table operator_versions enable row level security;
    create policy "Public read access" on operator_versions
      for select using (true);

``operator_key`` is the accordion ``data-id`` (e.g.
``redHatOpenshiftGitops-Agnostic``), NOT the operator name: several
operators appear in more than one tier (Red Hat Connectivity Link is both
Agnostic and Rolling), and a name-keyed state would cross-contaminate
them.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from datetime import datetime, timezone

from bs4 import BeautifulSoup

from scraper.models import Article
from scraper.sources.safe_fetch import fetch_feed_bytes

_logger = logging.getLogger(__name__)

PAGE_URL = "https://access.redhat.com/support/policy/updates/openshift_operators"
_SOURCE = "Red Hat Operator Life Cycles"

# The stable structural landmarks on the page: one <h1 id="..."> per
# lifecycle tier, each followed by exactly one PatternFly accordion.
# "platform-aligned" is deliberately absent — those operators track the
# OCP release train and are already covered by ocp_versions.py.
_TIERS: dict[str, str] = {
    "platform-agnostic": "Platform Agnostic",
    "rolling-stream": "Rolling Stream",
}

# A version must start with a numeric token. This is what rejects the
# real-world junk on the page ("N/A", "-", and the Klusterlet table's
# prose row "Previous operator releases without a tiered strategy") while
# keeping the legitimate oddities ("2.x", "0.140.x", "0.1 Tech Preview",
# "5.8 (For Tracing, service mesh and kiali)" -> "5.8").
_VERSION_RE = re.compile(r"^(\d+(?:\.[0-9A-Za-z]+)*)")

_ARIA_SUFFIX_RE = re.compile(r"\s*version table\s*$", re.IGNORECASE)

# Cosmetic short tags for well-known products, keyed by the auto-derived
# slug. The operator *list* is always discovered from the page — this map
# only adds a friendlier alias, so an operator missing from it still gets
# a working slug tag.
_TAG_ALIASES: dict[str, str] = {
    "red-hat-openshift-gitops": "gitops",
    "red-hat-openshift-pipelines": "pipelines",
    "red-hat-openshift-service-mesh": "service-mesh",
    "red-hat-openshift-serverless": "serverless",
    "red-hat-openshift-dev-spaces": "dev-spaces",
    "red-hat-openshift-ai-self-managed": "openshift-ai",
    "red-hat-openshift-virtualization": "virtualization",
    "red-hat-advanced-cluster-security-for-kubernetes": "acs",
    "red-hat-advanced-cluster-management-for-kubernetes": "acm",
    "red-hat-developer-hub": "developer-hub",
    "logging-for-red-hat-openshift": "logging",
    "loki-operator": "loki",
    "compliance-operator": "compliance",
    "custom-metrics-autoscaler": "autoscaler",
    "cert-manager-operator-for-red-hat-openshift": "cert-manager",
    "red-hat-build-of-keycloak": "keycloak",
    "red-hat-build-of-opentelemetry": "opentelemetry",
    "migration-toolkit-for-virtualization": "mtv",
    "migration-toolkit-for-containers": "mtc",
}


@dataclass
class OperatorRelease:
    """One operator's current release as stated by the Life Cycles page."""

    key: str
    name: str
    tier: str
    version: str
    ga_date: str | None = None
    ocp_versions: str | None = None


def _slugify(name: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower())
    return slug.strip("-")


def _clean_version(raw: str | None) -> str | None:
    """Return the leading version token of ``raw``, or None if it isn't one."""
    if not raw:
        return None
    match = _VERSION_RE.match(raw.strip())
    return match.group(1) if match else None


def _cell_texts(element) -> list[str]:
    """Text of each direct-child <span> of an accordion toggle's grid."""
    grid = element.find("span", class_="button-grid")
    if grid is None:
        return []
    return [
        span.get_text(" ", strip=True)
        for span in grid.find_all("span", recursive=False)
    ]


def _table_rows(table) -> list[dict[str, str]]:
    """Return each tbody row as {column header: cell text}.

    Columns are mapped by header position; rows with fewer cells than
    headers are still returned (zip stops at the shorter side) so a
    malformed row fails the version check rather than raising here.
    """
    headers = [
        th.get_text(" ", strip=True) for th in table.find_all("th")
    ]
    body = table.find("tbody")
    if body is None or not headers:
        return []
    rows: list[dict[str, str]] = []
    for tr in body.find_all("tr"):
        cells = [
            td.get_text(" ", strip=True) for td in tr.find_all("td")
        ]
        rows.append(dict(zip(headers, cells)))
    return rows


def _first_release_row(table) -> dict[str, str] | None:
    """The current release: the first tbody row with a valid Version."""
    for row in _table_rows(table):
        if _clean_version(row.get("Version")) is not None:
            return row
    return None


def _release_from_row(
    key: str, name: str, tier: str, row: dict[str, str]
) -> OperatorRelease | None:
    version = _clean_version(row.get("Version"))
    if version is None:
        return None
    return OperatorRelease(
        key=key,
        name=name,
        tier=tier,
        version=version,
        ga_date=row.get("General availability") or None,
        ocp_versions=row.get("OpenShift Version") or None,
    )


def _parse_group(
    data_id: str, tier: str, content
) -> list[OperatorRelease]:
    """Parse a '[Expand for Operator list]' group's per-operator tables.

    Each sub-operator is named by its table's aria-label, e.g.
    ``aria-label="Loki operator version table"``.
    """
    releases: list[OperatorRelease] = []
    for table in content.find_all("table"):
        try:
            aria = table.get("aria-label") or ""
            name = _ARIA_SUFFIX_RE.sub("", aria).strip()
            if not name:
                _logger.warning(
                    "Operator table without an aria-label name in %s", data_id
                )
                continue
            row = _first_release_row(table)
            if row is None:
                _logger.warning(
                    "No valid release row for %r in %s", name, data_id
                )
                continue
            release = _release_from_row(
                f"{data_id}::{_slugify(name)}", name, tier, row
            )
            if release is not None:
                releases.append(release)
        except Exception:
            _logger.exception(
                "Failed to parse a grouped operator table in %s", data_id
            )
    return releases


def _parse_simple(
    data_id: str, tier: str, name: str, version: str, content
) -> OperatorRelease:
    """A 4-cell toggle. The detail table (when present) adds GA date and
    supported OCP versions; the toggle's own "Latest version" column stays
    authoritative for the version itself."""
    release = OperatorRelease(key=data_id, name=name, tier=tier, version=version)
    if content is None:
        return release

    table = content.find("table")
    if table is None:
        return release

    rows = _table_rows(table)
    match = next(
        (r for r in rows if _clean_version(r.get("Version")) == version),
        None,
    )
    if match is None:
        match = _first_release_row(table)
    if match is not None:
        release.ga_date = match.get("General availability") or None
        release.ocp_versions = match.get("OpenShift Version") or None
    return release


def parse_operators(html: str) -> list[OperatorRelease]:
    """Extract the current release of every tracked operator on the page.

    Platform Aligned operators are never looked at. Returns ``[]`` if the
    target sections can't be located at all — callers must treat that as a
    clean abort and leave state untouched.
    """
    soup = BeautifulSoup(html, "html.parser")
    releases: list[OperatorRelease] = []

    for tier_id, tier_name in _TIERS.items():
        heading = soup.find("h1", id=tier_id)
        if heading is None:
            _logger.error("Tier section %r not found on the page", tier_id)
            return []
        accordion = heading.find_next("div", class_="pf-v5-c-accordion")
        if accordion is None:
            _logger.error("No accordion under tier section %r", tier_id)
            return []

        for toggle in accordion.find_all("button", class_="accordion-item"):
            data_id = toggle.get("data-id")
            try:
                cells = _cell_texts(toggle)
                if not data_id or not cells or not cells[0]:
                    _logger.warning(
                        "Skipping unrecognised toggle in %r (data-id=%r)",
                        tier_id,
                        data_id,
                    )
                    continue

                name = cells[0]
                content = accordion.find("div", id=data_id)
                version = (
                    _clean_version(cells[1]) if len(cells) > 1 else None
                )

                if version is not None:
                    releases.append(
                        _parse_simple(data_id, tier_name, name, version, content)
                    )
                    continue

                # No version on the toggle: either a group of operators, or
                # an entry the page simply doesn't version (name-only rows,
                # "N/A"). The group tables are the only thing worth reading.
                if content is not None:
                    grouped = _parse_group(data_id, tier_name, content)
                    if grouped:
                        releases.extend(grouped)
                        continue

                _logger.debug(
                    "No trackable version for %r (%s)", name, data_id
                )
            except Exception:
                _logger.exception(
                    "Failed to parse operator toggle %r in %r", data_id, tier_id
                )

    return releases


def _load_known_versions(supabase_client) -> dict[str, str]:
    """Return {operator_key: latest_version} from the operator_versions table."""
    try:
        result = (
            supabase_client.client.table("operator_versions")
            .select("operator_key, latest_version")
            .execute()
        )
        return {
            row["operator_key"]: row["latest_version"]
            for row in (result.data or [])
        }
    except Exception as e:
        print(f"Failed to load known operator versions: {e}")
        return {}


def _save_version(supabase_client, release: OperatorRelease) -> None:
    try:
        supabase_client.client.table("operator_versions").upsert(
            {
                "operator_key": release.key,
                "operator_name": release.name,
                "tier": release.tier,
                "latest_version": release.version,
                "updated_at": datetime.now(timezone.utc).isoformat(),
            },
            on_conflict="operator_key",
        ).execute()
    except Exception as e:
        print(f"Failed to save operator version {release.key}: {e}")


def _tags_for(release: OperatorRelease) -> list[str]:
    slug = _slugify(release.name)
    # "layered-release", NOT "release": the bare "release" tag is the
    # topic-push trigger at main.py:142. Layered-product GAs are
    # deliberately push-silent until we've seen real volume, so they carry
    # a distinct tag that no FCM path keys on. Don't "fix" this back.
    tags = ["layered-release", "openshift", "layered-product", slug]
    alias = _TAG_ALIASES.get(slug)
    if alias:
        tags.append(alias)
    return list(dict.fromkeys(tags))


def _article_from_release(release: OperatorRelease) -> Article:
    # articles.url is the global unique key, so it must vary per operator
    # AND per version: a shared page URL would collapse every operator into
    # one row, and a version-less anchor would overwrite the previous GA in
    # place (keeping notified=true, so no push would ever fire again). The
    # fragment is never sent to the server — the link still opens the page.
    slug_version = _slugify(release.version)
    url = f"{PAGE_URL}#{release.key}-{slug_version}"

    summary = (
        f"{release.name} {release.version} is now generally available "
        f"({release.tier} tier)."
    )
    if release.ga_date:
        summary += f" General availability: {release.ga_date}."
    if release.ocp_versions:
        summary += f" Supported OpenShift versions: {release.ocp_versions}."

    return Article(
        title=f"{release.name} {release.version} is now generally available",
        url=url,
        source=_SOURCE,
        tags=_tags_for(release),
        summary=summary,
        # Not the GA date: it can be months in the past, which would sink
        # the article below the feed fold and drop it from the same-day
        # digest query. The real GA date is in the summary. Matches
        # ocp_versions.py.
        published_at=datetime.now(timezone.utc),
    )


def fetch_operator_lifecycles(
    supabase_client, seed_only: bool = False
) -> list[Article]:
    """Return Article objects for newly-GA'd OpenShift layered products.

    When ``seed_only`` is True the operator_versions table is primed with
    the page's current state and no articles are returned — used on first
    run so ~60 operators don't land in the feed at once.
    """
    if seed_only:
        print("Seeding operator_versions table...")
    else:
        print("Fetching OpenShift operator life cycles...")

    try:
        html = fetch_feed_bytes(PAGE_URL).decode("utf-8", errors="replace")
    except Exception as e:
        print(f"Failed to fetch the Operator Life Cycles page: {e}")
        return []

    releases = parse_operators(html)
    if not releases:
        print("No operators parsed — aborting without touching state.")
        return []

    print(f"Parsed {len(releases)} tracked operators")

    known = {} if seed_only else _load_known_versions(supabase_client)
    new_articles: list[Article] = []

    for release in releases:
        try:
            if seed_only:
                _save_version(supabase_client, release)
                continue

            previous = known.get(release.key)
            if previous == release.version:
                continue

            _save_version(supabase_client, release)
            new_articles.append(_article_from_release(release))
            print(
                f"  → NEW GA: {release.name} "
                f"{previous or '(new operator)'} → {release.version}"
            )
        except Exception:
            _logger.exception(
                "Failed to process operator release %r", release.key
            )

    print(f"Operator life cycles: {len(new_articles)} new articles")
    return new_articles
