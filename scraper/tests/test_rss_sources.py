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


def test_no_current_source_enables_the_filter() -> None:
    """The mechanism ships switched off; enabling feeds is a follow-up."""
    enabled = [
        s["source"] for s in rss.RSS_SOURCES if s.get("content_filter", False)
    ]
    assert enabled == []


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
