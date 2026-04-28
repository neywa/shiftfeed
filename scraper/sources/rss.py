from __future__ import annotations

import calendar
import logging
import time
from datetime import datetime, timezone
from typing import TypedDict

import feedparser
from bs4 import BeautifulSoup

from scraper.models import Article

_logger = logging.getLogger(__name__)


class RSSSource(TypedDict):
    url: str
    source: str
    tags: list[str]


RSS_SOURCES: list[RSSSource] = [
    {
        "url": "https://www.redhat.com/en/rss/blog/channel/red-hat-openshift",
        "source": "Red Hat Blog",
        "tags": ["blog", "openshift"],
    },
    {
        "url": "https://developers.redhat.com/blog/feed",
        "source": "Red Hat Developer",
        "tags": ["blog", "developer"],
    },
    {
        "url": "https://kubernetes.io/feed.xml",
        "source": "Kubernetes Blog",
        "tags": ["blog", "kubernetes"],
    },
    {
        "url": "https://www.cncf.io/feed/",
        "source": "CNCF Blog",
        "tags": ["blog", "cncf", "kubernetes"],
    },
    {
        "url": "https://hnrss.org/newest?q=openshift",
        "source": "Hacker News",
        "tags": ["community", "hackernews"],
    },
    {
        "url": "https://hnrss.org/newest?q=kubernetes+openshift",
        "source": "Hacker News",
        "tags": ["community", "hackernews", "kubernetes"],
    },
    {
        "url": "https://hackernoon.com/tagged/kubernetes/feed",
        "source": "HackerNoon",
        "tags": ["blog", "kubernetes", "hackernoon"],
    },
    {
        "url": "https://hackernoon.com/tagged/devops/feed",
        "source": "HackerNoon",
        "tags": ["blog", "devops", "hackernoon"],
    },
    {
        "url": "https://istio.io/feed.xml",
        "source": "Istio Blog",
        "tags": ["blog", "istio", "servicemesh"],
    },
]


def _struct_time_to_utc_aware(st: time.struct_time | None) -> datetime | None:
    if st is None:
        return None
    ts = calendar.timegm(st)
    return datetime.fromtimestamp(ts, tz=timezone.utc)


def _html_to_plain_text(html: str) -> str | None:
    text = BeautifulSoup(html, "html.parser").get_text(separator=" ", strip=True)
    return text if text else None


def fetch_rss_articles(url: str, source: str, tags: list[str]) -> list[Article]:
    articles: list[Article] = []
    try:
        feed = feedparser.parse(url)
    except Exception:
        _logger.exception("Failed to fetch or parse RSS feed: %s", url)
        return articles

    for entry in feed.entries:
        try:
            title = getattr(entry, "title", None)
            link = getattr(entry, "link", None)
            if not title or not link:
                continue

            raw_summary = getattr(entry, "summary", None) or getattr(
                entry, "description", None
            )
            if raw_summary:
                summary = _html_to_plain_text(str(raw_summary))
            else:
                summary = None

            published_parsed = getattr(entry, "published_parsed", None) or getattr(
                entry, "updated_parsed", None
            )
            published_at = _struct_time_to_utc_aware(published_parsed)

            articles.append(
                Article(
                    title=str(title).strip(),
                    url=str(link).strip(),
                    source=source,
                    tags=list(tags),
                    summary=summary,
                    published_at=published_at,
                )
            )
        except Exception:
            _logger.exception("Failed to process RSS entry from %s", url)

    return articles


def fetch_all_rss() -> list[Article]:
    out: list[Article] = []
    for src in RSS_SOURCES:
        _logger.info("Fetching: %s", src["source"])
        out.extend(
            fetch_rss_articles(src["url"], src["source"], src["tags"]),
        )
    return out


def fetch_single_feed(feed_config: dict) -> list[Article]:
    """Fetches and parses a single RSS/Atom feed described by ``feed_config``.

    ``feed_config`` must have keys ``url``, ``source`` and ``tags`` — the
    same shape as entries in :data:`RSS_SOURCES`. Returns an empty list
    on any fetch/parse failure (the underlying :func:`fetch_rss_articles`
    already swallows and logs per-entry errors)."""
    try:
        return fetch_rss_articles(
            feed_config["url"],
            feed_config["source"],
            list(feed_config.get("tags", [])),
        )
    except Exception:
        _logger.exception(
            "Failed to fetch single feed: %s",
            feed_config.get("url"),
        )
        return []
