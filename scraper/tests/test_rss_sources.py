"""Tests for the ARO source entry and the opt-in content filter.

Feed bytes are stubbed at :func:`scraper.sources.rss.fetch_feed_bytes` so
these stay offline and deterministic while still exercising the real
parse -> tag -> filter path.
"""

from __future__ import annotations

import pytest

from scraper.sources import rss

ARO_URL = (
    "https://azure.microsoft.com/en-us/blog/product/"
    "azure-red-hat-openshift/feed/"
)

# Shaped after the live ARO feed: RSS 2.0, HTML in <description>, RFC-822
# pubDate.
ARO_FEED = b"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Azure Red Hat OpenShift</title>
    <item>
      <title>Red Hat Summit 2026: Platform modernization on Azure</title>
      <link>https://azure.microsoft.com/en-us/blog/red-hat-summit-2026/</link>
      <description>&lt;p&gt;Microsoft and Red Hat show how Azure Red Hat
        OpenShift powers modernization.&lt;/p&gt;</description>
      <pubDate>Mon, 11 May 2026 19:00:00 GMT</pubDate>
    </item>
    <item>
      <title>A decade of open innovation</title>
      <link>https://azure.microsoft.com/en-us/blog/a-decade/</link>
      <description>&lt;p&gt;A decade-long partnership.&lt;/p&gt;</description>
      <pubDate>Tue, 02 Dec 2025 16:00:00 GMT</pubDate>
    </item>
  </channel>
</rss>
"""

# Atom, shaped after lwkd.info: a near-empty <summary> stub next to the real
# article in <content>. Judged on the summary alone, both entries would drop.
STUB_SUMMARY_FEED = b"""<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Stubby Weekly</title>
  <entry>
    <title>Week Ending July 05, 2026</title>
    <link href="https://example.com/week-27"/>
    <summary>Developer News</summary>
    <content type="html">&lt;h2&gt;Developer News&lt;/h2&gt;&lt;p&gt;Kubernetes
      v1.37 has reached its mid-cycle milestone with 86 tracked
      enhancements.&lt;/p&gt;</content>
    <published>2026-07-05T00:00:00Z</published>
  </entry>
  <entry>
    <title>Week Ending June 28, 2026</title>
    <link href="https://example.com/week-26"/>
    <summary>Developer News</summary>
    <content type="html">&lt;h2&gt;Developer News&lt;/h2&gt;&lt;p&gt;A roundup of
      unrelated desktop publishing tips.&lt;/p&gt;</content>
    <published>2026-06-28T00:00:00Z</published>
  </entry>
</feed>
"""

# An entry whose only keyword hit is inside a link URL, not the prose.
LINK_ONLY_FEED = b"""<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Linky</title>
  <entry>
    <title>A post about nothing</title>
    <link href="https://example.com/nothing"/>
    <summary>Stub</summary>
    <content type="html">&lt;p&gt;Read more at
      &lt;a href="https://kubernetes.io/docs"&gt;this link&lt;/a&gt;.&lt;/p&gt;</content>
    <published>2026-07-05T00:00:00Z</published>
  </entry>
</feed>
"""

# One off-topic entry, one relevant entry.
MIXED_FEED = b"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Some Broad Feed</title>
    <item>
      <title>Hello world</title>
      <link>https://example.com/hello</link>
      <description>My first blog post about nothing in particular.</description>
      <pubDate>Mon, 11 May 2026 19:00:00 GMT</pubDate>
    </item>
    <item>
      <title>OpenShift 4.16 is out</title>
      <link>https://example.com/ocp</link>
      <description>The new release ships upgrades.</description>
      <pubDate>Mon, 11 May 2026 19:00:00 GMT</pubDate>
    </item>
  </channel>
</rss>
"""


@pytest.fixture
def stub_feed(monkeypatch):
    """Returns a callable that pins the bytes fetch_feed_bytes will return."""

    def _install(payload: bytes):
        monkeypatch.setattr(
            rss, "fetch_feed_bytes", lambda url: payload
        )

    return _install


# ---------------------------------------------------------------------------
# Change 1 — the ARO source.
# ---------------------------------------------------------------------------


def _aro_entry() -> dict:
    matches = [s for s in rss.RSS_SOURCES if s["url"] == ARO_URL]
    assert len(matches) == 1, "expected exactly one ARO entry in RSS_SOURCES"
    return matches[0]


def test_aro_source_is_registered() -> None:
    entry = _aro_entry()
    assert entry["source"] == "Azure Red Hat OpenShift"
    # Narrow, all-relevant source: tagged like the Red Hat OpenShift
    # channel, NOT like the generic kubernetes/cncf feeds.
    assert entry["tags"] == ["blog", "openshift"]
    assert "kubernetes" not in entry["tags"]


def test_aro_feed_parses_into_tagged_articles(stub_feed) -> None:
    stub_feed(ARO_FEED)
    entry = _aro_entry()

    articles = rss.fetch_rss_articles(
        entry["url"], entry["source"], entry["tags"]
    )

    assert len(articles) == 2
    first = articles[0]
    assert first.title == (
        "Red Hat Summit 2026: Platform modernization on Azure"
    )
    assert first.url == "https://azure.microsoft.com/en-us/blog/red-hat-summit-2026/"
    assert first.source == "Azure Red Hat OpenShift"
    assert first.tags == ["blog", "openshift"]
    # HTML stripped by _html_to_plain_text.
    assert "<p>" not in first.summary
    assert first.summary.startswith("Microsoft and Red Hat")
    # Dates land tz-aware UTC.
    assert first.published_at is not None
    assert first.published_at.tzinfo is not None
    assert first.published_at.year == 2026
    # Curated rows stay global — user-RSS ownership is not involved here.
    assert first.submitted_by is None


# ---------------------------------------------------------------------------
# Change 2 — the opt-in content filter.
# ---------------------------------------------------------------------------


def test_content_filter_drops_offtopic_entries(stub_feed) -> None:
    stub_feed(MIXED_FEED)

    articles = rss.fetch_rss_articles(
        "https://example.com/feed", "Broad Feed", ["blog"], content_filter=True
    )

    assert [a.title for a in articles] == ["OpenShift 4.16 is out"]


def test_content_filter_off_keeps_everything(stub_feed) -> None:
    stub_feed(MIXED_FEED)

    articles = rss.fetch_rss_articles(
        "https://example.com/feed", "Broad Feed", ["blog"], content_filter=False
    )

    assert [a.title for a in articles] == ["Hello world", "OpenShift 4.16 is out"]


def test_content_filter_defaults_off(stub_feed) -> None:
    """Omitting the arg must behave exactly like content_filter=False."""
    stub_feed(MIXED_FEED)

    articles = rss.fetch_rss_articles(
        "https://example.com/feed", "Broad Feed", ["blog"]
    )

    assert len(articles) == 2


# The only sources meant to self-filter. Broad feeds whose output is mostly
# outside this app's scope; everything else is trusted wholesale because the
# feed itself is narrow.
FILTERED_SOURCES = {
    "Sysdig",
    "Aqua Security",
    "Last Week in Kubernetes Development",
}


def test_exactly_the_expected_sources_enable_the_filter() -> None:
    """Tripwire: fires if a source gains or loses the flag unintentionally.

    Filtering a narrow source is silently lossy — it would drop real
    articles — so the set is pinned in both directions rather than merely
    asserting the intended three are present.
    """
    enabled = {
        s["source"] for s in rss.RSS_SOURCES if s.get("content_filter", False)
    }
    assert enabled == FILTERED_SOURCES


def test_unfiltered_sources_do_not_set_the_flag() -> None:
    """Every other source must leave the flag absent or explicitly False."""
    for s in rss.RSS_SOURCES:
        if s["source"] in FILTERED_SOURCES:
            continue
        assert not s.get("content_filter", False), s["source"]


def test_filter_reads_content_when_summary_is_a_stub(stub_feed) -> None:
    """Regression for lwkd.info: a stub <summary> must not cost the article.

    Judged on <summary> alone both entries read as "Developer News" and drop;
    the relevant one only survives because <content> is part of the haystack.
    """
    stub_feed(STUB_SUMMARY_FEED)

    articles = rss.fetch_rss_articles(
        "https://example.com/feed", "Stubby", ["blog"], content_filter=True
    )

    assert [a.title for a in articles] == ["Week Ending July 05, 2026"]


def test_stub_summary_entries_still_drop_when_content_is_offtopic(
    stub_feed,
) -> None:
    """Guards the test above from passing because the filter went permissive."""
    stub_feed(STUB_SUMMARY_FEED)

    articles = rss.fetch_rss_articles(
        "https://example.com/feed", "Stubby", ["blog"], content_filter=True
    )

    assert "Week Ending June 28, 2026" not in [a.title for a in articles]


def test_stored_summary_is_not_replaced_by_content(stub_feed) -> None:
    """<content> feeds the filter only — it must not leak into the row.

    Changing the stored summary is a separate, deliberate decision; this
    pins the current contract so it can't drift silently.
    """
    stub_feed(STUB_SUMMARY_FEED)

    articles = rss.fetch_rss_articles(
        "https://example.com/feed", "Stubby", ["blog"], content_filter=True
    )

    assert articles[0].summary == "Developer News"


def test_keyword_inside_a_link_url_does_not_pass(stub_feed) -> None:
    """HTML is stripped before matching, so hrefs can't score keyword hits."""
    stub_feed(LINK_ONLY_FEED)

    articles = rss.fetch_rss_articles(
        "https://example.com/feed", "Linky", ["blog"], content_filter=True
    )

    assert articles == []


def test_fetch_single_feed_defaults_to_unfiltered(stub_feed) -> None:
    """User RSS (Pro custom feeds) must not silently drop entries."""
    stub_feed(MIXED_FEED)

    articles = rss.fetch_single_feed(
        {
            "url": "https://example.com/feed",
            "source": "User Feed",
            "tags": ["custom_feed"],
        }
    )

    assert len(articles) == 2


def test_fetch_single_feed_honours_the_filter(stub_feed) -> None:
    stub_feed(MIXED_FEED)

    articles = rss.fetch_single_feed(
        {
            "url": "https://example.com/feed",
            "source": "User Feed",
            "tags": ["custom_feed"],
            "content_filter": True,
        }
    )

    assert [a.title for a in articles] == ["OpenShift 4.16 is out"]
