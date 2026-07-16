"""Tests for the OpenShift Operator Life Cycles fetcher.

The page bytes are stubbed at
:func:`scraper.sources.operator_lifecycles.fetch_feed_bytes` and Supabase is
faked, so these stay offline and deterministic while exercising the real
parse -> diff -> article path.

The fixture is a pruned capture of the live page; see its header comment for
what each retained operator is there to prove.
"""

from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

import pytest

from scraper.sources import operator_lifecycles
from scraper.sources.operator_lifecycles import (
    fetch_operator_lifecycles,
    parse_operators,
)
from scraper.sources.safe_fetch import FeedFetchError

FIXTURE = Path(__file__).parent / "fixtures" / "openshift_operators.html"

# What the fixture is expected to yield: {operator_key: version}.
FIXTURE_STATE = {
    "openshiftLogging-Agnostic::logging-for-red-hat-openshift": "6.5",
    "openshiftLogging-Agnostic::loki-operator": "6.5",
    "redHatAdvancedClusterManagementForKubernetes-Agnostic::klusterlet": "2.5",
    "redHatOpenshiftGitops-Agnostic": "1.21",
    "complianceOperator-Rolling": "1.9",
}


@pytest.fixture
def fixture_html() -> str:
    return FIXTURE.read_text(encoding="utf-8")


# ---------------------------------------------------------------------------
# Fakes
# ---------------------------------------------------------------------------


class _FakeQuery:
    def __init__(self, rows: list[dict], upserts: list[dict]) -> None:
        self._rows = rows
        self._upserts = upserts
        self._action: str | None = None

    def select(self, *_args, **_kwargs) -> "_FakeQuery":
        self._action = "select"
        return self

    def upsert(self, row: dict, on_conflict: str | None = None) -> "_FakeQuery":
        assert on_conflict == "operator_key"
        self._action = "upsert"
        self._upserts.append(row)
        return self

    def execute(self) -> SimpleNamespace:
        if self._action == "select":
            return SimpleNamespace(data=list(self._rows))
        return SimpleNamespace(data=[])


class _FakeInner:
    def __init__(self, rows: list[dict], upserts: list[dict]) -> None:
        self._rows = rows
        self.upserts = upserts

    def table(self, name: str) -> _FakeQuery:
        assert name == "operator_versions"
        return _FakeQuery(self._rows, self.upserts)


class FakeSupabase:
    """Stands in for SupabaseClient, recording every upsert."""

    def __init__(self, state: dict[str, str] | None = None) -> None:
        rows = [
            {"operator_key": k, "latest_version": v}
            for k, v in (state or {}).items()
        ]
        self.upserts: list[dict] = []
        self.client = _FakeInner(rows, self.upserts)

    @property
    def written(self) -> dict[str, str]:
        return {r["operator_key"]: r["latest_version"] for r in self.upserts}


@pytest.fixture
def stub_page(monkeypatch):
    """Returns a callable pinning the bytes fetch_feed_bytes will return."""

    def _install(payload: bytes | Exception):
        def _fetch(_url: str) -> bytes:
            if isinstance(payload, Exception):
                raise payload
            return payload

        monkeypatch.setattr(operator_lifecycles, "fetch_feed_bytes", _fetch)

    return _install


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------


def test_platform_aligned_operators_are_excluded(fixture_html) -> None:
    """Aligned operators track OCP and are ocp_versions.py's job.

    The fixture deliberately contains two of them, so this fails loudly if
    the tier filter ever regresses.
    """
    releases = parse_operators(fixture_html)

    assert releases, "fixture should yield operators"
    # Guards the assertions below from passing on a fixture that lost its
    # aligned section: both an aligned group and a simple aligned operator
    # must actually be present to be excluded.
    assert 'id="platform-aligned"' in fixture_html
    assert 'data-id="awsEfsCsiDriverOperator-Aligned"' in fixture_html
    assert 'data-id="openshiftDataFoundation-Aligned"' in fixture_html
    assert all("-Aligned" not in r.key for r in releases)
    assert all(r.tier in ("Platform Agnostic", "Rolling Stream") for r in releases)


def test_group_form_operator_is_extracted(fixture_html) -> None:
    """Loki lives in a per-operator table inside the OpenShift Logging group,
    named only by the table's aria-label."""
    loki = next(r for r in parse_operators(fixture_html) if r.name == "Loki operator")

    assert loki.version == "6.5"
    assert loki.tier == "Platform Agnostic"
    assert loki.ga_date == "01 Apr 2026"
    assert loki.ocp_versions == "4.19, 4.20, 4.21"
    assert loki.key == "openshiftLogging-Agnostic::loki-operator"


def test_simple_form_operators_are_extracted(fixture_html) -> None:
    releases = {r.name: r for r in parse_operators(fixture_html)}

    compliance = releases["compliance operator"]
    assert compliance.version == "1.9"
    assert compliance.tier == "Rolling Stream"
    assert compliance.ga_date == "16 Apr 2026"

    gitops = releases["Red Hat OpenShift GitOps"]
    assert gitops.version == "1.21"
    assert gitops.tier == "Platform Agnostic"
    assert gitops.ocp_versions == "4.18, 4.19, 4.20, 4.21, 4.22"


def test_prose_row_is_skipped_without_killing_the_run(fixture_html) -> None:
    """The Klusterlet table's top row is prose, not a version:
    "Previous operator releases without a tiered strategy". It must be
    skipped in favour of the first row that really carries a version, and
    the rest of the page must still parse."""
    releases = parse_operators(fixture_html)
    klusterlet = next(r for r in releases if r.name == "Klusterlet")

    assert klusterlet.version == "2.5"
    assert len(releases) == len(FIXTURE_STATE)


def test_unversioned_entries_are_skipped(fixture_html) -> None:
    """AWS Load Balancer Operator's version is literally "N/A" with no table,
    and Cluster Observability Operator is a name-only 1-cell entry."""
    names = {r.name for r in parse_operators(fixture_html)}

    # Present in the fixture, absent from the output.
    assert 'data-id="awsLoadBalancerOperator-Agnostic"' in fixture_html
    assert 'data-id="clusterObservabilityOperator-Rolling"' in fixture_html
    assert "AWS Load Balancer Operator" not in names
    assert "Cluster Observability Operator" not in names


def test_operator_keys_are_unique(fixture_html) -> None:
    """State is keyed on `key`; a collision would silently merge operators."""
    releases = parse_operators(fixture_html)

    assert len({r.key for r in releases}) == len(releases)


def test_missing_sections_parse_to_nothing() -> None:
    assert parse_operators("<html><body><h1>Nothing here</h1></body></html>") == []


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("1.21", "1.21"),
        ("2.x", "2.x"),
        ("0.140.x", "0.140.x"),
        ("0.1 Tech Preview", "0.1"),
        ("5.8 (For Tracing, service mesh and kiali)", "5.8"),
        ("N/A", None),
        ("-", None),
        ("", None),
        (None, None),
        ("Previous operator releases without a tiered strategy", None),
    ],
)
def test_clean_version(raw, expected) -> None:
    assert operator_lifecycles._clean_version(raw) == expected


# ---------------------------------------------------------------------------
# New-GA detection
# ---------------------------------------------------------------------------


def test_version_bump_emits_exactly_one_article(fixture_html, stub_page) -> None:
    stub_page(fixture_html.encode())
    state = dict(FIXTURE_STATE)
    state["redHatOpenshiftGitops-Agnostic"] = "1.20"
    client = FakeSupabase(state)

    articles = fetch_operator_lifecycles(client)

    assert len(articles) == 1
    assert articles[0].title == (
        "Red Hat OpenShift GitOps 1.21 is now generally available"
    )
    # Only the changed operator is written back.
    assert client.written == {"redHatOpenshiftGitops-Agnostic": "1.21"}


def test_unchanged_page_emits_nothing(fixture_html, stub_page) -> None:
    """The hourly job hits an unchanged page nearly every run — it must be
    a complete no-op, including no state churn."""
    stub_page(fixture_html.encode())
    client = FakeSupabase(FIXTURE_STATE)

    articles = fetch_operator_lifecycles(client)

    assert articles == []
    assert client.upserts == []


def test_support_date_change_alone_emits_nothing(fixture_html, stub_page) -> None:
    """The page churns on support-end dates constantly. Only the version is
    compared, so a date-only edit must stay invisible."""
    changed = fixture_html.replace("31 Oct 2026", "30 Nov 2026").replace(
        "24 Jun 2026", "25 Jun 2026"
    )
    assert changed != fixture_html, "fixture should contain the dates being moved"
    stub_page(changed.encode())
    client = FakeSupabase(FIXTURE_STATE)

    articles = fetch_operator_lifecycles(client)

    assert articles == []
    assert client.upserts == []


def test_new_operator_emits_an_article(fixture_html, stub_page) -> None:
    """An operator absent from state is a GA we've never seen."""
    state = {
        k: v for k, v in FIXTURE_STATE.items() if k != "complianceOperator-Rolling"
    }
    stub_page(fixture_html.encode())
    client = FakeSupabase(state)

    articles = fetch_operator_lifecycles(client)

    assert [a.title for a in articles] == [
        "compliance operator 1.9 is now generally available"
    ]


def test_seed_only_primes_state_without_articles(fixture_html, stub_page) -> None:
    """First run: ~60 operators would otherwise flood the feed and fire one
    batch release push."""
    stub_page(fixture_html.encode())
    client = FakeSupabase({})

    articles = fetch_operator_lifecycles(client, seed_only=True)

    assert articles == []
    assert client.written == FIXTURE_STATE


def test_fetch_failure_preserves_state(stub_page) -> None:
    stub_page(FeedFetchError("blocked scheme: 'file'"))
    client = FakeSupabase(FIXTURE_STATE)

    articles = fetch_operator_lifecycles(client)

    assert articles == []
    assert client.upserts == []


def test_missing_sections_abort_cleanly(stub_page) -> None:
    """A page reshuffle must not wipe state or emit garbage."""
    stub_page(b"<html><body><h1>Some other page entirely</h1></body></html>")
    client = FakeSupabase(FIXTURE_STATE)

    articles = fetch_operator_lifecycles(client)

    assert articles == []
    assert client.upserts == []


# ---------------------------------------------------------------------------
# Article shape
# ---------------------------------------------------------------------------


def test_article_shape(fixture_html, stub_page) -> None:
    stub_page(fixture_html.encode())
    state = dict(FIXTURE_STATE)
    state["redHatOpenshiftGitops-Agnostic"] = "1.20"
    article = fetch_operator_lifecycles(FakeSupabase(state))[0]

    assert article.source == "Red Hat Operator Life Cycles"
    assert article.tags == [
        "layered-release",
        "openshift",
        "layered-product",
        "red-hat-openshift-gitops",
        "gitops",
    ]
    assert article.url.startswith(operator_lifecycles.PAGE_URL + "#")
    assert "Platform Agnostic tier" in article.summary
    assert "24 Jun 2026" in article.summary
    assert "4.18, 4.19, 4.20, 4.21, 4.22" in article.summary
    # Curated row — user-RSS ownership is not involved.
    assert article.submitted_by is None
    assert article.published_at is not None
    assert article.published_at.tzinfo is not None


def test_article_url_is_unique_per_operator_and_version(
    fixture_html, stub_page
) -> None:
    """articles.url is the global unique key. A URL that didn't vary with the
    version would overwrite the previous GA in place — the row keeps
    notified=true, so no push would ever fire again.
    """
    stub_page(fixture_html.encode())
    client = FakeSupabase({})

    articles = fetch_operator_lifecycles(client)

    urls = [a.url for a in articles]
    assert len(set(urls)) == len(urls)

    gitops_121 = next(
        a for a in articles if a.title.startswith("Red Hat OpenShift GitOps")
    ).url
    bumped = fetch_operator_lifecycles(
        FakeSupabase({**FIXTURE_STATE, "redHatOpenshiftGitops-Agnostic": "1.20"})
    )
    assert bumped[0].url == gitops_121  # same version -> same URL (idempotent)
    assert "1-21" in gitops_121


# ---------------------------------------------------------------------------
# Push silence
#
# Layered-product GAs are deliberately push-silent until we've seen the real
# GA volume. The tests below are the tripwire for that decision: they must
# fail loudly if someone re-adds the "release" tag or wires "layered-release"
# into an FCM path.
# ---------------------------------------------------------------------------


def _push_eligible(articles: list) -> list:
    """Replicates the topic-push condition at scraper/main.py:142 verbatim.

        new_releases = [
            a
            for a in all_articles
            if "release" in a.tags and not cache.is_notified(a.url)
        ]

    ``new_releases`` is the sole input to both release sends —
    ``fcm.send_release_alert()`` (single) and the ``releases`` topic batch.
    The cache half is omitted: every article here is new by construction, so
    this is the strictly more permissive form of the filter. If an article
    isn't eligible under this, it cannot be eligible under main.py's.
    """
    return [a for a in articles if "release" in a.tags]


@pytest.fixture
def layered_articles(fixture_html, stub_page) -> list:
    """Every operator in the fixture, emitted as a fresh GA."""
    stub_page(fixture_html.encode())
    articles = fetch_operator_lifecycles(FakeSupabase({}))
    assert articles, "fixture should emit articles against empty state"
    return articles


def _ocp_release_article():
    """The Article that ocp_versions.py emits for a stable promotion.

    Mirrors scraper/sources/ocp_versions.py:210-231. Hand-built rather than
    imported because that fetcher's shape is what we're pinning as *still
    push-eligible* — this is the control for the layered assertions.
    """
    from scraper.models import Article

    return Article(
        title="OpenShift 4.20.5 is now stable",
        url="https://github.com/openshift/cincinnati-graph-data/blob/master/channels/stable-4.20.yaml",
        source="OCP Versions",
        tags=["release", "openshift", "ocp-4.20", "stable-channel", "update"],
        summary="OpenShift 4.20 stable channel updated from 4.20.4 to 4.20.5.",
        published_at=None,
    )


def test_layered_ga_carries_layered_release_not_release(layered_articles) -> None:
    for article in layered_articles:
        assert "layered-release" in article.tags
        assert "release" not in article.tags
        # The rest of the tag set is unchanged.
        assert "openshift" in article.tags
        assert "layered-product" in article.tags


def test_layered_articles_are_not_push_eligible(layered_articles) -> None:
    """The thing we actually care about: no layered GA can reach a topic push.

    Pins the condition itself rather than restating the tag, so wiring
    "layered-release" into main.py:142 would fail here too.
    """
    assert _push_eligible(layered_articles) == []


def test_ocp_releases_are_still_push_eligible() -> None:
    """Control for the test above.

    Without this, test_layered_articles_are_not_push_eligible would pass
    trivially if _push_eligible were mistyped into something that matches
    nothing at all.
    """
    assert _push_eligible([_ocp_release_article()]) == [_ocp_release_article()]


def test_ocp_and_layered_articles_in_one_run(layered_articles) -> None:
    """main.py filters one combined list. Only the OCP release survives."""
    ocp = _ocp_release_article()

    eligible = _push_eligible([*layered_articles, ocp])

    assert eligible == [ocp]


def test_layered_release_is_not_wired_to_any_fcm_path() -> None:
    """Tripwire: "layered-release" must stay confined to the fetcher that
    emits it and the digest category map. If it shows up in main.py or
    fcm.py, someone has wired a push to it."""
    scraper_root = Path(__file__).resolve().parents[1]
    mentions = {
        path.relative_to(scraper_root).as_posix()
        for path in scraper_root.rglob("*.py")
        if "layered-release" in path.read_text(encoding="utf-8")
    }

    assert mentions == {
        "sources/operator_lifecycles.py",
        "digest.py",
        "tests/test_operator_lifecycles.py",
    }


def test_releases_category_rule_does_not_match_layered_ga(
    layered_articles,
) -> None:
    """alert_rule_matcher maps the "releases" category to the "release" tag,
    so a releases-category rule stops matching layered GAs — the intended
    per-token push reduction."""
    from scraper.sources.alert_rule_matcher import article_matches_rule
    from scraper.sources.alert_rules import AlertRule

    rule = AlertRule(
        rule_id="r1",
        user_id="u1",
        name="Releases",
        categories=["releases"],
        cvss_minimum=None,
        keywords=[],
        fcm_tokens=["tok"],
    )

    assert not any(article_matches_rule(a, rule) for a in layered_articles)


def test_catchall_rule_still_matches_layered_ga(layered_articles) -> None:
    """Documents the ACCEPTED residual push path, so it stays a known
    behaviour rather than a surprise.

    main.py:185-206 walks every new article against each Pro user's rules
    with no tag pre-filter, and an empty `categories` means "match all". A
    user's catch-all rule therefore still pushes layered GAs per-token. That
    was a deliberate call: they asked to be notified about everything, and
    every other source behaves this way. The push-silence guarantee is
    scoped to TOPIC pushes.
    """
    from scraper.sources.alert_rule_matcher import article_matches_rule
    from scraper.sources.alert_rules import AlertRule

    rule = AlertRule(
        rule_id="r1",
        user_id="u1",
        name="Everything",
        categories=[],
        cvss_minimum=None,
        keywords=[],
        fcm_tokens=["tok"],
    )

    assert all(article_matches_rule(a, rule) for a in layered_articles)


def test_releases_digest_category_includes_layered_gas() -> None:
    """A releases-filtered personal digest must still contain layered GAs —
    digests are content, not pushes."""
    from scraper.digest import DigestGenerator

    assert DigestGenerator._CATEGORY_TAG_MAP["releases"] == {
        "release",
        "layered-release",
    }
