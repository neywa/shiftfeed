"""
Fetches enabled custom RSS sources from ``user_rss_sources`` and ingests
them through the same parsing pipeline as the global RSS fetcher.

Each user's feeds are fetched independently — a failure on one user's
feed never affects other users or the global feed run, in line with the
"per-entry failures swallowed and logged" invariant in CLAUDE.md.
"""

from dataclasses import dataclass

from supabase import Client

from scraper.models import Article
from scraper.sources import rss as global_rss


@dataclass
class UserSource:
    source_id: str
    user_id: str
    url: str
    label: str


def fetch_user_sources(supabase: Client) -> list[UserSource]:
    """Returns every enabled custom RSS source across all Pro users.

    The scraper iterates this list to know which feeds to fetch this run.
    Disabled sources and rows for users without device tokens are simply
    skipped (we still fetch for users without tokens — they'll see the
    articles in the feed; only push delivery requires a token)."""
    try:
        resp = (
            supabase.table("user_rss_sources")
            .select("id, user_id, url, label")
            .eq("enabled", True)
            .execute()
        )
    except Exception as e:
        print(f"[UserRSS] Failed to load user sources: {e}")
        return []

    return [
        UserSource(
            source_id=r["id"],
            user_id=r["user_id"],
            url=r["url"],
            label=r["label"],
        )
        for r in (resp.data or [])
    ]


def fetch_articles_for_source(source: UserSource) -> list[Article]:
    """Fetches and parses a single user RSS source.

    Returns a list of :class:`Article` instances tagged with
    ``custom_feed`` and stamped with ``submitted_by=source.user_id`` so
    the row inserts only into the owning user's view of the feed.
    Returns an empty list on any error — never raises."""
    try:
        feed_config = {
            "url": source.url,
            "source": source.label,
            "tags": ["custom_feed"],
        }
        articles = global_rss.fetch_single_feed(feed_config)
        result: list[Article] = []
        for article in articles:
            result.append(
                Article(
                    title=article.title,
                    url=article.url,
                    source=article.source,
                    tags=list(article.tags),
                    summary=article.summary,
                    published_at=article.published_at,
                    submitted_by=source.user_id,
                )
            )
        return result
    except Exception as e:
        print(
            f"[UserRSS] Failed to fetch {source.url} "
            f"for user {source.user_id}: {e}"
        )
        return []


def update_source_error(
    supabase: Client,
    source_id: str,
    error: str | None,
) -> None:
    """Records (or clears) the last fetch error on a ``user_rss_sources``
    row. Pass ``error=None`` to clear a previous error after a healthy
    fetch. Never raises."""
    try:
        (
            supabase.table("user_rss_sources")
            .update({"last_error": error})
            .eq("id", source_id)
            .execute()
        )
    except Exception as e:
        print(f"[UserRSS] Failed to update error for {source_id}: {e}")
