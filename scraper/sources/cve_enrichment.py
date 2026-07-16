"""
Source-agnostic CVSS score + severity lookup for a CVE id.

Only :mod:`~scraper.sources.security` ever attached a score, and only for
CVEs it fetched itself from Red Hat's Hydra *list* endpoint. Everything
tagged by the regex path in :mod:`~scraper.sources.cve_tagger` (Istio
bulletins, Kubernetes blog posts, release notes) arrived unscored — and an
unscored article can never satisfy a Pro CVSS-threshold rule, because
``alert_rule_matcher`` excludes anything without a ``cvss:`` tag. This
module is the one place that turns a CVE id into a score, shared by the
backfill and by the ingest hook in ``main.py``.

Follows the :mod:`~scraper.sources.relevance` pattern: one module owning
the logic, imported by every consumer, docstring as the contract.

TWO HYDRA SCHEMAS
-----------------
The endpoints do NOT agree, and this is the bug that made enrichment
necessary in the first place:

  * LIST  (``cve.json?package=…``) — flat: ``{"cvss3_score": "7.8"}``
  * DETAIL(``cve/CVE-….json``)    — nested: ``{"cvss3": {"cvss3_base_score": "7.8"}}``

:func:`extract_cvss_score` handles both (and the NVD shape). It is a pure
shape reader: it returns whatever number it finds, ``0.0`` included. The
rejection guard deliberately lives one layer up, in :func:`lookup_cve`, so
that ``security.py``'s list-endpoint behaviour is byte-identical to what it
was before this module existed.

REJECTED CVEs
-------------
A withdrawn CVE must never receive a score. Hydra reports one as
``cvss3_base_score = "0.0"`` with no ``threat_severity``; NVD reports
``vulnStatus = "Rejected"`` with empty ``metrics``. ``float("0.0")`` is
``0.0`` — not ``None`` — so without an explicit guard a rejected CVE gets a
plausible-looking ``cvss:0.0`` tag that passes every "has a score" check
while failing every threshold: the article would be silently invisible to
alerts rather than absent. Never emit 0.0 as a score.

SEVERITY VOCABULARIES DO NOT MIX
--------------------------------
Red Hat says ``low/moderate/important/critical``; NVD says
``low/medium/high/critical``. They are different scales, not synonyms —
Red Hat's "Important" covers both NVD's HIGH and CRITICAL. Never map
between them. :attr:`CveScore.source` records which vocabulary the caller
received so downstream never has to guess.
"""

from __future__ import annotations

import json
import logging
import os
import re
import time
from dataclasses import dataclass
from typing import Any

import httpx

from scraper.sources.safe_fetch import fetch_feed_bytes

_logger = logging.getLogger(__name__)

_HYDRA_URL = "https://access.redhat.com/hydra/rest/securitydata/cve/{cve_id}.json"
_NVD_URL = "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId={cve_id}"

# Hydra tolerated 16 sequential calls with no throttling; this spacing is
# politeness, not a requirement.
_HYDRA_MIN_INTERVAL = 0.6

# NVD without a key is brutal: 11 requests then a hard 429 wall, with no
# Retry-After header to back off against. The documented public budget is
# 5 requests / 30s rolling; 6.5s spacing survived a 5/5 retry. With a key
# the budget is 50/30s.
_NVD_MIN_INTERVAL_NO_KEY = 6.5
_NVD_MIN_INTERVAL_WITH_KEY = 0.6

# NVD returns 503s and read-timeouts routinely (8 of 11 fallback lookups in
# the first backfill dry run failed this way). Retrying turns a misreported
# "unscorable" into a real answer. Hydra has been reliable, so 1 attempt.
_NVD_ATTEMPTS = 3
_HYDRA_ATTEMPTS = 2

CVE_TAG_RE = re.compile(r"^CVE-\d{4}-\d+$")
_REDHAT_CVE_PREFIX = "https://access.redhat.com/security/cve/"

_last_call: dict[str, float] = {}


@dataclass(frozen=True)
class CveScore:
    """The outcome of a CVE lookup. ``rejected`` and a score are mutually
    exclusive: a withdrawn CVE never carries one.

    ``lookup_failed`` distinguishes "the API broke" from "the API says
    there is nothing". They must never be conflated: NVD returns 503s and
    read timeouts routinely, and treating one as 'this CVE has no score'
    both under-reports the backfill and would mask a rejected CVE as merely
    unscorable. A failed lookup is retryable; an empty answer is not.
    """

    cvss_score: float | None = None
    severity: str | None = None
    source: str | None = None  # "hydra" | "nvd" | "join" | "cache" | None
    rejected: bool = False
    lookup_failed: bool = False

    @property
    def scored(self) -> bool:
        return self.cvss_score is not None


def _throttle(host: str, min_interval: float) -> None:
    last = _last_call.get(host)
    if last is not None:
        wait = min_interval - (time.monotonic() - last)
        if wait > 0:
            time.sleep(wait)
    _last_call[host] = time.monotonic()


def _nvd_api_key() -> str | None:
    """Optional, like GITHUB_TOKEN — absent just means slower, not broken."""
    key = os.environ.get("NVD_API_KEY")
    return key or None


def extract_cvss_score(payload: dict[str, Any]) -> float | None:
    """Return a CVSS base score from any known payload shape, or None.

    Never raises. Pure shape reader — see the module docstring on why the
    rejection/0.0 guard is NOT here.

    Shapes, in priority order:
      1. ``cvss3.cvss3_base_score``      — Hydra DETAIL (string)
      2. ``cvss3_score`` / ``cvssScore`` / ``cvss_score`` — Hydra LIST + legacy
      3. ``cvss3.score`` / ``cvss3.base_score``          — older variants
      4. ``metrics.cvssMetricV31[0].cvssData.baseScore`` — NVD
    """
    try:
        candidates: list[Any] = []

        cvss3 = payload.get("cvss3")
        if isinstance(cvss3, dict):
            # Hydra's DETAIL endpoint. Must be tried first: a detail payload
            # has no flat key at all, and this was the shape the original
            # extractor missed entirely.
            candidates.append(cvss3.get("cvss3_base_score"))

        candidates.append(payload.get("cvss3_score"))
        candidates.append(payload.get("cvssScore"))
        candidates.append(payload.get("cvss_score"))

        if isinstance(cvss3, dict):
            candidates.append(cvss3.get("score"))
            candidates.append(cvss3.get("base_score"))

        metrics = payload.get("metrics")
        if isinstance(metrics, dict):
            entry = _preferred_nvd_metric(metrics.get("cvssMetricV31"))
            if entry is not None:
                data = entry.get("cvssData")
                if isinstance(data, dict):
                    candidates.append(data.get("baseScore"))

        for raw in candidates:
            if raw is None or raw == "":
                continue
            try:
                return round(float(raw), 1)
            except (TypeError, ValueError):
                continue
    except Exception:
        return None
    return None


def _preferred_nvd_metric(entries: Any) -> dict[str, Any] | None:
    """Pick one cvssMetricV31 entry, preferring NVD's own Primary analysis.

    v4.0 is deliberately never consulted: across the sampled CVEs it
    appeared on 2 of 16, always as a Secondary (snyk) entry, and it
    disagrees with v3.1 (7.5 vs 7.7, 9.1 vs 9.3). Mixing versions would
    make scores incomparable between articles.
    """
    if not isinstance(entries, list) or not entries:
        return None
    for entry in entries:
        if isinstance(entry, dict) and entry.get("type") == "Primary":
            return entry
    first = entries[0]
    return first if isinstance(first, dict) else None


def _get_json(
    url: str, headers: dict[str, str] | None = None, attempts: int = 1
) -> tuple[Any | None, bool]:
    """GET + parse JSON through the SSRF-guarded fetcher.

    Returns ``(payload, failed)``:
      * ``(payload, False)`` — success
      * ``(None, False)``    — a definitive 404: the API says it has no such id
      * ``(None, True)``     — transient failure (5xx, 429, timeout, bad JSON)

    The distinction matters — see :class:`CveScore.lookup_failed`. Retries
    apply only to transient failures; a 404 is answered immediately.
    """
    last_error = None
    for attempt in range(1, attempts + 1):
        try:
            raw = fetch_feed_bytes(url, headers=headers)
            return json.loads(raw), False
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 404:
                return None, False  # definitive: not a failure
            last_error = f"HTTP {e.response.status_code}"
        except Exception as e:
            last_error = f"{type(e).__name__}: {e}"
        if attempt < attempts:
            backoff = 2.0 * attempt
            _logger.info(
                "%s for %s — retry %s/%s in %.0fs",
                last_error, url, attempt, attempts - 1, backoff,
            )
            time.sleep(backoff)
    _logger.warning("giving up on %s after %s attempt(s): %s",
                    url, attempts, last_error)
    return None, True


def _lookup_hydra(cve_id: str) -> CveScore | None:
    """Red Hat's own record. None means 'not in Hydra' — try NVD."""
    _throttle("hydra", _HYDRA_MIN_INTERVAL)
    payload, failed = _get_json(
        _HYDRA_URL.format(cve_id=cve_id), attempts=_HYDRA_ATTEMPTS
    )
    if failed:
        return CveScore(lookup_failed=True, source="hydra")
    if not isinstance(payload, dict):
        return None

    severity_raw = payload.get("threat_severity")
    severity = str(severity_raw).lower() if severity_raw else None
    score = extract_cvss_score(payload)

    # THE GUARD. Hydra marks a withdrawn CVE as 0.0 with no severity.
    # Returning that as a score would tag cvss:0.0 — see module docstring.
    if score == 0.0 and severity is None:
        return CveScore(rejected=True, source="hydra")

    if score is None and severity is None:
        # Hydra knows the id but has neither score nor rating (often a
        # rejected CVE it never assessed). NVD is authoritative on that.
        return None

    return CveScore(cvss_score=score, severity=severity, source="hydra")


def _lookup_nvd(cve_id: str) -> CveScore | None:
    key = _nvd_api_key()
    _throttle(
        "nvd",
        _NVD_MIN_INTERVAL_WITH_KEY if key else _NVD_MIN_INTERVAL_NO_KEY,
    )
    payload, failed = _get_json(
        _NVD_URL.format(cve_id=cve_id),
        headers={"apiKey": key} if key else None,
        attempts=_NVD_ATTEMPTS,
    )
    if failed:
        # NVD 503s and times out routinely. Say so, rather than letting the
        # caller record "this CVE has no score".
        return CveScore(lookup_failed=True, source="nvd")
    if not isinstance(payload, dict):
        return None

    vulns = payload.get("vulnerabilities")
    if not isinstance(vulns, list) or not vulns:
        return None
    cve = vulns[0].get("cve")
    if not isinstance(cve, dict):
        return None

    if str(cve.get("vulnStatus", "")).lower() == "rejected":
        return CveScore(rejected=True, source="nvd")

    metrics = cve.get("metrics")
    if not isinstance(metrics, dict):
        return None
    entry = _preferred_nvd_metric(metrics.get("cvssMetricV31"))
    if entry is None:
        return None

    data = entry.get("cvssData") or {}
    score = extract_cvss_score({"metrics": metrics})
    severity_raw = data.get("baseSeverity") or entry.get("baseSeverity")
    # NVD's vocabulary, kept as NVD's — never translated to Red Hat's.
    severity = str(severity_raw).lower() if severity_raw else None
    if score is None and severity is None:
        return None
    return CveScore(cvss_score=score, severity=severity, source="nvd")


def lookup_cve(cve_id: str) -> CveScore:
    """Resolve one CVE id to a score + severity. Never raises.

    Hydra first: it covered 15 of 16 sampled ids, is unthrottled, and
    speaks the same severity vocabulary the article tags already use. NVD
    is the fallback for ids Red Hat doesn't track (404).
    """
    hydra = _lookup_hydra(cve_id)
    if hydra is not None and (hydra.rejected or hydra.scored or hydra.severity):
        return hydra
    # A Hydra transport failure must NOT be read as "not in Hydra" — falling
    # through to NVD would be fine, but silently reporting no-score would not.
    hydra_failed = hydra is not None and hydra.lookup_failed

    nvd = _lookup_nvd(cve_id)
    if nvd is not None:
        if nvd.lookup_failed and hydra_failed:
            return CveScore(lookup_failed=True)
        return nvd

    return CveScore(lookup_failed=hydra_failed)


# ---------------------------------------------------------------------------
# Article-level helpers — shared by the backfill and the ingest hook so the
# two can never drift on what "scored", "detag" or "drop" mean.
# ---------------------------------------------------------------------------


def cve_ids_from_tags(tags: list[str]) -> list[str]:
    return [t for t in tags if CVE_TAG_RE.match(t)]


def has_score(tags: list[str]) -> bool:
    return any(t.startswith("cvss:") for t in tags)


def is_cve_record(url: str, tags: list[str]) -> bool:
    """True when the article IS a CVE (a Red Hat CVE page naming exactly one).

    Only these may be deleted outright when rejected. Everything else —
    Istio bulletins, release notes, blog posts — merely *mentions* CVEs and
    is worth keeping on its own merits.
    """
    return url.startswith(_REDHAT_CVE_PREFIX) and len(cve_ids_from_tags(tags)) == 1


@dataclass(frozen=True)
class ArticleDecision:
    """What enrichment concluded about one article.

    ``action`` is one of:
      ``skip``       — already scored, or nothing resolvable; leave alone
      ``score``      — add cvss + severity tags
      ``detag``      — strip rejected CVE ids (and ``cve`` if none remain)
      ``drop``       — the article IS a rejected CVE; remove it
    """

    action: str
    tags: list[str]
    cvss_score: float | None = None
    severity: str | None = None
    scored_cve: str | None = None
    rejected_cves: tuple[str, ...] = ()


def decide(
    url: str, tags: list[str], resolved: dict[str, CveScore]
) -> ArticleDecision:
    """Decide what to do with one cve-tagged article.

    ``resolved`` maps CVE id -> CveScore for (at least) this article's ids.
    Unknown ids are treated as unresolved, never as rejected.
    """
    ids = cve_ids_from_tags(tags)
    if not ids or has_score(tags):
        return ArticleDecision(action="skip", tags=list(tags))

    rejected = [c for c in ids if resolved.get(c, CveScore()).rejected]
    live = [c for c in ids if c not in rejected]

    if rejected and not live and is_cve_record(url, ids):
        return ArticleDecision(
            action="drop", tags=list(tags), rejected_cves=tuple(rejected)
        )

    new_tags = list(tags)
    if rejected:
        new_tags = [t for t in new_tags if t not in rejected]
        if not live:
            # No CVE ids left, so the article is no longer about a CVE.
            # `cve` is only ever added by cve_tagger/security.py, so it is
            # safe to strip. `security` is NOT: RSS_SOURCES assigns it to
            # whole feeds (Sysdig, Aqua), and removing it would destroy a
            # source-assigned tag that has nothing to do with this CVE.
            new_tags = [t for t in new_tags if t != "cve"]

    # Highest score wins, and exactly ONE cvss: tag is emitted.
    # alert_rule_matcher iterates a *set* of tags keeping the last cvss: it
    # sees, so two tags would make the winning score vary between runs.
    best_cve, best = None, None
    for cve_id in live:
        s = resolved.get(cve_id)
        if s is None or not s.scored:
            continue
        if best is None or s.cvss_score > best.cvss_score:
            best_cve, best = cve_id, s

    if best is None:
        action = "detag" if rejected else "skip"
        return ArticleDecision(
            action=action, tags=new_tags, rejected_cves=tuple(rejected)
        )

    new_tags.append(f"cvss:{best.cvss_score:.1f}")
    if best.severity and best.severity not in new_tags:
        new_tags.append(best.severity)

    return ArticleDecision(
        action="score",
        tags=list(dict.fromkeys(new_tags)),
        cvss_score=best.cvss_score,
        severity=best.severity,
        scored_cve=best_cve,
        rejected_cves=tuple(rejected),
    )


def load_cached_scores(
    supabase_client, cve_ids: list[str]
) -> dict[str, CveScore]:
    """Read already-resolved scores out of ``cve_alerts``.

    This is what keeps the ingest hook cheap. RSS re-serves the same
    articles every hour, so without a cache the hook would re-fetch every
    unscored CVE article on every run — hundreds of calls a day, forever.
    With it, only CVE ids never seen before cost a request.

    Degrades to an empty cache (i.e. correct but slower) if the ``cvss``
    column has not been added yet, so this is safe to deploy before the
    ALTER runs.
    """
    if not cve_ids:
        return {}
    try:
        rows = (
            supabase_client.client.table("cve_alerts")
            .select("cve_id,cvss,severity")
            .in_("cve_id", cve_ids)
            .execute()
            .data
            or []
        )
    except Exception as e:
        _logger.warning(
            "cve_alerts score cache unavailable (has the cvss column been "
            "added?): %s",
            e,
        )
        return {}

    cache: dict[str, CveScore] = {}
    for row in rows:
        if row.get("cvss") is None:
            continue
        cache[row["cve_id"]] = CveScore(
            cvss_score=float(row["cvss"]),
            severity=row.get("severity"),
            source="cache",
        )
    return cache


def resolve_ids(
    cve_ids: list[str], cache: dict[str, CveScore] | None = None
) -> dict[str, CveScore]:
    """Resolve every id, consulting ``cache`` before making any API call."""
    cache = cache or {}
    out: dict[str, CveScore] = {}
    for cve_id in cve_ids:
        hit = cache.get(cve_id)
        out[cve_id] = hit if hit is not None else lookup_cve(cve_id)
    return out


def enrich_articles(articles: list, supabase_client) -> tuple[list, list]:
    """Ingest hook: score new cve-tagged articles before they are upserted.

    Returns ``(keep, dropped)``. ``keep`` carries enriched tags and is what
    the caller should upsert; ``dropped`` are rejected CVE records that must
    never reach the feed.

    Best-effort by design — any failure leaves the article untouched rather
    than breaking the run, matching the per-entry isolation invariant the
    fetchers follow.
    """
    from scraper.models import Article  # local import: avoids a cycle

    targets = [
        a
        for a in articles
        if "cve" in a.tags and not has_score(a.tags) and cve_ids_from_tags(a.tags)
    ]
    if not targets:
        return list(articles), []

    needed = sorted({c for a in targets for c in cve_ids_from_tags(a.tags)})
    cache = load_cached_scores(supabase_client, needed)
    misses = [c for c in needed if c not in cache]
    print(
        f"[cve_enrichment] {len(targets)} unscored article(s), "
        f"{len(needed)} CVE id(s): {len(cache)} cached, {len(misses)} to fetch"
    )
    resolved = resolve_ids(needed, cache)

    keep, dropped = [], []
    decisions = {}
    for article in targets:
        try:
            decisions[article.url] = decide(article.url, article.tags, resolved)
        except Exception:
            _logger.exception("Failed to enrich %s", article.url)

    for article in articles:
        d = decisions.get(article.url)
        if d is None or d.action == "skip":
            keep.append(article)
            continue
        if d.action == "drop":
            print(f"[cve_enrichment] DROP rejected CVE record: {article.url}")
            dropped.append(article)
            continue
        keep.append(
            Article(
                title=article.title,
                url=article.url,
                source=article.source,
                tags=d.tags,
                summary=article.summary,
                published_at=article.published_at,
                # Carried over: a None submitted_by is what the articles RLS
                # policy treats as "visible to everyone" (see cve_tagger).
                submitted_by=article.submitted_by,
            )
        )
    return keep, dropped
