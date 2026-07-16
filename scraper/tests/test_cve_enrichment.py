"""Tests for the shared CVE score enrichment module.

All HTTP is stubbed at ``cve_enrichment.fetch_feed_bytes`` (the SSRF-guarded
fetcher every outbound call goes through), so these stay offline and
deterministic while exercising the real extract -> lookup -> decide path.

Throttling is neutralised per-test: the real module sleeps up to 6.5s
between NVD calls.
"""

from __future__ import annotations

import json

import httpx
import pytest

from scraper.sources import cve_enrichment
from scraper.sources.cve_enrichment import (
    CveScore,
    decide,
    extract_cvss_score,
    lookup_cve,
)

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def no_throttle(monkeypatch):
    """Skip the real sleeps and reset the module's rate-limit state."""
    monkeypatch.setattr(cve_enrichment.time, "sleep", lambda _s: None)
    cve_enrichment._last_call.clear()


@pytest.fixture(autouse=True)
def no_api_key(monkeypatch):
    monkeypatch.delenv("NVD_API_KEY", raising=False)


def _http_error(status: int) -> httpx.HTTPStatusError:
    request = httpx.Request("GET", "https://example.test")
    response = httpx.Response(status, request=request)
    return httpx.HTTPStatusError("boom", request=request, response=response)


@pytest.fixture
def stub_http(monkeypatch):
    """Pin responses by URL substring. Values: dict (JSON) or an Exception.

    Records every URL fetched so tests can assert which APIs were called.
    """
    calls: list[str] = []

    def _install(routes: dict):
        def _fetch(url, *, headers=None):
            calls.append(url)
            for needle, payload in routes.items():
                if needle in url:
                    if isinstance(payload, Exception):
                        raise payload
                    return json.dumps(payload).encode()
            raise _http_error(404)

        monkeypatch.setattr(cve_enrichment, "fetch_feed_bytes", _fetch)
        return calls

    return _install


def _hydra(score=None, severity=None):
    payload = {"name": "CVE-2026-1"}
    if score is not None:
        payload["cvss3"] = {
            "cvss3_base_score": score,
            "cvss3_scoring_vector": "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H",
            "status": "verified",
        }
    if severity is not None:
        payload["threat_severity"] = severity
    return payload


def _nvd(score=None, severity=None, status="Analyzed", metrics=None):
    cve: dict = {"id": "CVE-2026-1", "vulnStatus": status}
    if metrics is not None:
        cve["metrics"] = metrics
    elif score is not None:
        cve["metrics"] = {
            "cvssMetricV31": [
                {
                    "source": "nvd@nist.gov",
                    "type": "Primary",
                    "cvssData": {
                        "version": "3.1",
                        "baseScore": score,
                        "baseSeverity": severity,
                    },
                }
            ]
        }
    else:
        cve["metrics"] = {}
    return {"totalResults": 1, "vulnerabilities": [{"cve": cve}]}


# ---------------------------------------------------------------------------
# extract_cvss_score — shapes
# ---------------------------------------------------------------------------


def test_hydra_detail_shape_is_extracted() -> None:
    """THE break this whole change exists for.

    The Hydra DETAIL endpoint nests the score at cvss3.cvss3_base_score as a
    string. The original extractor knew four shapes, none of them this one,
    so it returned None for every detail payload — enrichment would have
    silently scored nothing.
    """
    assert extract_cvss_score({"cvss3": {"cvss3_base_score": "7.8"}}) == 7.8


@pytest.mark.parametrize(
    "payload,expected",
    [
        # The four shapes that predate this module — regression guards.
        ({"cvss3_score": "7.8"}, 7.8),  # Hydra LIST (what security.py uses)
        ({"cvssScore": 5.3}, 5.3),
        ({"cvss_score": "9.8"}, 9.8),
        ({"cvss3": {"score": "6.1"}}, 6.1),
        ({"cvss3": {"base_score": 4.4}}, 4.4),
        (
            {
                "metrics": {
                    "cvssMetricV31": [
                        {"type": "Primary", "cvssData": {"baseScore": 9.1}}
                    ]
                }
            },
            9.1,
        ),
        # Malformed / absent -> None, never a raise.
        ({}, None),
        ({"cvss3_score": ""}, None),
        ({"cvss3_score": "not-a-number"}, None),
        ({"cvss3": None}, None),
        ({"cvss3": {"cvss3_base_score": None}}, None),
        ({"metrics": {"cvssMetricV31": []}}, None),
    ],
)
def test_extract_cvss_score_shapes(payload, expected) -> None:
    assert extract_cvss_score(payload) == expected


def test_list_endpoint_entry_scores_as_before() -> None:
    """Regression: a real Hydra LIST entry, shaped as security.py sees it.

    security.py now imports this extractor; its behaviour must be identical
    to the private one it replaced.
    """
    entry = {
        "CVE": "CVE-2026-15809",
        "severity": "important",
        "cvss3_score": "7.8",
        "cvss3_scoring_vector": "CVSS:3.1/AV:L/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:H",
        "bugzilla_description": "a flaw",
    }
    assert extract_cvss_score(entry) == 7.8


def test_detail_shape_wins_over_a_stale_flat_key() -> None:
    """A payload carrying both must prefer the detail nesting."""
    payload = {"cvss3": {"cvss3_base_score": "7.8"}, "cvss3_score": "1.0"}
    assert extract_cvss_score(payload) == 7.8


# ---------------------------------------------------------------------------
# lookup_cve — the rejection guard
# ---------------------------------------------------------------------------


def test_rejected_cve_returns_rejected_not_a_zero_score(stub_http) -> None:
    """The silent-failure guard.

    Hydra reports a withdrawn CVE as "0.0" with no threat_severity.
    float("0.0") is 0.0, NOT None — so without this guard the CVE gets a
    plausible cvss:0.0 tag that satisfies every "has a score" check while
    failing every threshold. The article would be invisible to alerts
    rather than absent, which is worse than either.
    """
    stub_http({"hydra": _hydra(score="0.0", severity=None)})

    result = lookup_cve("CVE-2022-23529")

    assert result.rejected is True
    assert result.cvss_score is None
    assert result.scored is False


def test_a_rejected_cve_can_never_produce_a_cvss_tag() -> None:
    """Belt-and-braces on the guard, at the tag layer."""
    resolved = {"CVE-2022-23529": CveScore(rejected=True, source="hydra")}

    d = decide(
        "https://access.redhat.com/security/cve/CVE-2022-23529",
        ["cve", "security", "CVE-2022-23529"],
        resolved,
    )

    assert not any(t.startswith("cvss:") for t in d.tags)
    assert "cvss:0.0" not in d.tags


def test_nvd_rejected_status_is_rejected(stub_http) -> None:
    stub_http(
        {
            "hydra": _http_error(404),
            "nvd.nist.gov": _nvd(status="Rejected"),
        }
    )

    result = lookup_cve("CVE-2026-23766")

    assert result.rejected is True
    assert result.cvss_score is None
    assert result.source == "nvd"


# ---------------------------------------------------------------------------
# lookup_cve — source priority + vocabularies
# ---------------------------------------------------------------------------


def test_hydra_hit_makes_no_nvd_call(stub_http) -> None:
    calls = stub_http({"hydra": _hydra(score="7.5", severity="Important")})

    result = lookup_cve("CVE-2026-30922")

    assert result.cvss_score == 7.5
    assert result.source == "hydra"
    assert not any("nvd.nist.gov" in u for u in calls), "NVD must not be called"


def test_nvd_used_only_on_hydra_404(stub_http) -> None:
    calls = stub_http(
        {"hydra": _http_error(404), "nvd.nist.gov": _nvd(8.8, "HIGH")}
    )

    result = lookup_cve("CVE-2026-3288")

    assert result.cvss_score == 8.8
    assert result.source == "nvd"
    assert any("hydra" in u for u in calls), "Hydra must be tried first"
    assert any("nvd.nist.gov" in u for u in calls)


def test_hydra_severity_vocabulary_is_preserved(stub_http) -> None:
    """Red Hat says Important. It must stay `important` — never remapped to
    NVD's high/critical, which is a different scale entirely."""
    stub_http({"hydra": _hydra(score="9.1", severity="Important")})

    result = lookup_cve("CVE-2026-4599")

    assert result.severity == "important"
    assert result.source == "hydra"


def test_nvd_severity_vocabulary_is_preserved(stub_http) -> None:
    """NVD says HIGH. It must stay `high` — not translated to `important`."""
    stub_http({"hydra": _http_error(404), "nvd.nist.gov": _nvd(8.8, "HIGH")})

    result = lookup_cve("CVE-2026-3288")

    assert result.severity == "high"
    assert result.source == "nvd"


def test_v40_is_ignored_when_v31_present(stub_http) -> None:
    """v4.0 appeared on 2/16 sampled CVEs, always Secondary/snyk, and
    disagrees with v3.1 (9.1 vs 9.3). Mixing versions makes scores
    incomparable, so v3.1 is the only source."""
    metrics = {
        "cvssMetricV31": [
            {"type": "Primary", "cvssData": {"baseScore": 9.1, "baseSeverity": "CRITICAL"}}
        ],
        "cvssMetricV40": [
            {
                "source": "report@snyk.io",
                "type": "Secondary",
                "cvssData": {"baseScore": 9.3, "baseSeverity": "CRITICAL"},
            }
        ],
    }
    stub_http({"hydra": _http_error(404), "nvd.nist.gov": _nvd(metrics=metrics)})

    assert lookup_cve("CVE-2026-4599").cvss_score == 9.1


def test_primary_metric_preferred_over_secondary(stub_http) -> None:
    metrics = {
        "cvssMetricV31": [
            {
                "source": "report@snyk.io",
                "type": "Secondary",
                "cvssData": {"baseScore": 4.0, "baseSeverity": "MEDIUM"},
            },
            {
                "source": "nvd@nist.gov",
                "type": "Primary",
                "cvssData": {"baseScore": 7.5, "baseSeverity": "HIGH"},
            },
        ]
    }
    stub_http({"hydra": _http_error(404), "nvd.nist.gov": _nvd(metrics=metrics)})

    result = lookup_cve("CVE-2026-1")

    assert result.cvss_score == 7.5
    assert result.severity == "high"


def test_unknown_everywhere_returns_empty_score(stub_http) -> None:
    stub_http({"hydra": _http_error(404), "nvd.nist.gov": _http_error(404)})

    result = lookup_cve("CVE-1999-0001")

    assert result.rejected is False
    assert result.cvss_score is None
    assert result.source is None
    assert result.lookup_failed is False, "a 404 is a definitive answer"


def test_a_broken_nvd_is_not_reported_as_unscorable(stub_http) -> None:
    """The bug the first dry run exposed.

    NVD 503s and times out constantly — 8 of 11 fallback lookups failed that
    way on the first real run. Treating that as "this CVE has no score"
    under-reports the backfill AND masked a genuinely rejected CVE
    (CVE-2026-23766) as merely unscorable, which in turn hid a pending
    delete. A failed lookup is retryable; an empty answer is not.
    """
    stub_http({"hydra": _http_error(404), "nvd.nist.gov": _http_error(503)})

    result = lookup_cve("CVE-2026-23766")

    assert result.lookup_failed is True
    assert result.rejected is False
    assert result.cvss_score is None


def test_nvd_transient_failure_is_retried(stub_http, monkeypatch) -> None:
    """A 503 must be retried before being believed."""
    attempts = {"n": 0}

    def _fetch(url, *, headers=None):
        if "hydra" in url:
            raise _http_error(404)
        attempts["n"] += 1
        if attempts["n"] < 3:
            raise _http_error(503)
        return json.dumps(_nvd(8.8, "HIGH")).encode()

    monkeypatch.setattr(cve_enrichment, "fetch_feed_bytes", _fetch)

    result = lookup_cve("CVE-2026-3288")

    assert attempts["n"] == 3, "should have retried through the 503s"
    assert result.cvss_score == 8.8
    assert result.lookup_failed is False


def test_a_404_is_never_retried(stub_http, monkeypatch) -> None:
    """A definitive answer must not burn NVD's tiny rate budget."""
    attempts = {"n": 0}

    def _fetch(url, *, headers=None):
        attempts["n"] += 1
        raise _http_error(404)

    monkeypatch.setattr(cve_enrichment, "fetch_feed_bytes", _fetch)

    lookup_cve("CVE-1999-0001")

    assert attempts["n"] == 2, "one Hydra call + one NVD call, no retries"


def test_nvd_api_key_is_sent_as_a_header_when_present(monkeypatch) -> None:
    """Optional, like GITHUB_TOKEN. Its presence must reach the fetcher as
    the apiKey header — that is the whole reason fetch_feed_bytes grew a
    headers param."""
    monkeypatch.setenv("NVD_API_KEY", "secret-key")
    seen = {}

    def _fetch(url, *, headers=None):
        seen[url] = headers
        if "hydra" in url:
            raise _http_error(404)
        return json.dumps(_nvd(7.5, "HIGH")).encode()

    monkeypatch.setattr(cve_enrichment, "fetch_feed_bytes", _fetch)
    monkeypatch.setattr(cve_enrichment.time, "sleep", lambda _s: None)

    lookup_cve("CVE-2026-1")

    nvd_headers = next(h for u, h in seen.items() if "nvd.nist.gov" in u)
    assert nvd_headers == {"apiKey": "secret-key"}
    hydra_headers = next(h for u, h in seen.items() if "hydra" in u)
    assert hydra_headers is None


# ---------------------------------------------------------------------------
# decide — article-level rules
# ---------------------------------------------------------------------------


def test_multi_cve_article_gets_exactly_one_cvss_tag_at_the_max() -> None:
    """73 of 153 unscored articles name 2-3 CVEs.

    Exactly one cvss: tag is non-negotiable: alert_rule_matcher iterates a
    SET of tags and keeps the last cvss: it sees with no break, so two tags
    would make the winning score vary between runs.
    """
    resolved = {
        "CVE-2026-0001": CveScore(5.0, "moderate", "hydra"),
        "CVE-2026-0002": CveScore(9.1, "important", "hydra"),
        "CVE-2026-0003": CveScore(7.5, "important", "hydra"),
    }
    tags = ["cve", "security", "CVE-2026-0001", "CVE-2026-0002", "CVE-2026-0003"]

    d = decide("https://istio.io/latest/news/releases/announcing-1.18.2/", tags, resolved)

    assert d.action == "score"
    cvss_tags = [t for t in d.tags if t.startswith("cvss:")]
    assert cvss_tags == ["cvss:9.1"], "exactly one tag, carrying the max"
    assert d.scored_cve == "CVE-2026-0002"
    assert "important" in d.tags


def test_rejected_cve_record_is_dropped() -> None:
    """A Red Hat CVE page naming exactly one, rejected id: the article IS
    the withdrawn CVE, so there is nothing left to keep."""
    resolved = {"CVE-2022-23529": CveScore(rejected=True)}

    d = decide(
        "https://access.redhat.com/security/cve/CVE-2022-23529",
        ["security", "advisory", "cve", "CVE-2022-23529"],
        resolved,
    )

    assert d.action == "drop"


def test_rejected_mention_is_detagged_not_dropped() -> None:
    """The real case from live data: CVE-2022-23529 is rejected, but it sits
    on a Red Hat Developer blog post alongside two valid CVEs. Deleting the
    row would destroy a good article and two live CVE associations.
    """
    resolved = {
        "CVE-2023-39500": CveScore(7.5, "important", "hydra"),
        "CVE-2022-23529": CveScore(rejected=True),
        "CVE-2022-24999": CveScore(7.5, "important", "hydra"),
    }
    tags = ["blog", "cve", "security", "CVE-2023-39500", "CVE-2022-23529", "CVE-2022-24999"]

    d = decide(
        "https://developers.redhat.com/articles/2026/07/07/dependency-analytics",
        tags,
        resolved,
    )

    assert d.action == "score"
    assert "CVE-2022-23529" not in d.tags, "the rejected id is stripped"
    assert "CVE-2023-39500" in d.tags, "live ids survive"
    assert "CVE-2022-24999" in d.tags
    assert "cvss:7.5" in d.tags


def test_detag_keeps_source_assigned_security_tag() -> None:
    """`security` is assigned to whole feeds by RSS_SOURCES (Sysdig, Aqua),
    so it must survive de-tagging — it is not evidence of a CVE. `cve` is
    only ever added by cve_tagger/security.py, so that one is safe to strip.
    """
    resolved = {"CVE-2022-23529": CveScore(rejected=True)}
    tags = ["blog", "security", "cve", "CVE-2022-23529"]

    d = decide("https://webflow.sysdig.com/some-post", tags, resolved)

    assert d.action == "detag"
    assert "security" in d.tags, "source-assigned tag must not be destroyed"
    assert "cve" not in d.tags
    assert "CVE-2022-23529" not in d.tags
    assert "blog" in d.tags


def test_already_scored_article_is_skipped() -> None:
    """Idempotency at the decision layer: no rework, and no API call is even
    considered for these."""
    tags = ["cve", "security", "CVE-2026-0001", "cvss:7.5", "important"]

    d = decide("https://example.test/a", tags, {})

    assert d.action == "skip"
    assert d.tags == tags


def test_unresolvable_cve_leaves_the_article_untouched() -> None:
    resolved = {"CVE-2026-0001": CveScore()}

    d = decide("https://example.test/a", ["cve", "CVE-2026-0001"], resolved)

    assert d.action == "skip"
    assert not any(t.startswith("cvss:") for t in d.tags)


def test_unknown_id_is_not_treated_as_rejected() -> None:
    """A missing entry in `resolved` means 'we don't know', which must never
    be conflated with 'withdrawn' — that would delete real articles."""
    d = decide(
        "https://access.redhat.com/security/cve/CVE-2026-1",
        ["cve", "CVE-2026-1"],
        {},
    )

    assert d.action == "skip"


def test_is_cve_record_requires_a_single_cve_and_a_redhat_url() -> None:
    from scraper.sources.cve_enrichment import is_cve_record

    assert is_cve_record(
        "https://access.redhat.com/security/cve/CVE-2026-1", ["cve", "CVE-2026-1"]
    )
    # Two ids on a CVE page: not unambiguously "this article IS that CVE".
    assert not is_cve_record(
        "https://access.redhat.com/security/cve/CVE-2026-1",
        ["cve", "CVE-2026-1", "CVE-2026-2"],
    )
    assert not is_cve_record("https://istio.io/news/x", ["cve", "CVE-2026-1"])


# ---------------------------------------------------------------------------
# Cache / batching
# ---------------------------------------------------------------------------


class _FakeCveAlertsTable:
    def __init__(self, rows, calls):
        self._rows = rows
        self._calls = calls

    def select(self, *_a, **_k):
        return self

    def in_(self, _col, ids):
        self._calls.append(list(ids))
        self._rows = [r for r in self._rows if r["cve_id"] in ids]
        return self

    def execute(self):
        from types import SimpleNamespace

        return SimpleNamespace(data=self._rows)


class FakeClient:
    def __init__(self, rows=(), broken=False):
        self._rows = list(rows)
        self.select_calls: list[list[str]] = []
        self._broken = broken
        self.client = self

    def table(self, name):
        assert name == "cve_alerts"
        if self._broken:
            raise Exception('column "cvss" does not exist')
        return _FakeCveAlertsTable(list(self._rows), self.select_calls)


def test_cached_scores_prevent_api_calls(monkeypatch) -> None:
    """The forward hook's whole cost story: RSS re-serves the same articles
    every hour, so without this cache the hook would re-fetch every unscored
    CVE article on every run."""
    from scraper.sources.cve_enrichment import load_cached_scores, resolve_ids

    client = FakeClient(
        rows=[{"cve_id": "CVE-1", "cvss": 7.5, "severity": "important"}]
    )
    cache = load_cached_scores(client, ["CVE-1"])
    assert cache["CVE-1"].cvss_score == 7.5

    def _boom(_cve_id):
        raise AssertionError("lookup_cve must not be called for a cache hit")

    monkeypatch.setattr(cve_enrichment, "lookup_cve", _boom)
    resolved = resolve_ids(["CVE-1"], cache)
    assert resolved["CVE-1"].cvss_score == 7.5


def test_cache_degrades_gracefully_before_the_ddl_runs() -> None:
    """The cvss column may not exist yet — that must mean 'slower', not
    'crashed', so this can be deployed ahead of the ALTER."""
    from scraper.sources.cve_enrichment import load_cached_scores

    assert load_cached_scores(FakeClient(broken=True), ["CVE-1"]) == {}


def test_cache_ignores_rows_with_a_null_cvss() -> None:
    """Every pre-existing cve_alerts row has cvss NULL; those must not be
    mistaken for a resolved score."""
    from scraper.sources.cve_enrichment import load_cached_scores

    client = FakeClient(rows=[{"cve_id": "CVE-1", "cvss": None, "severity": None}])

    assert load_cached_scores(client, ["CVE-1"]) == {}
