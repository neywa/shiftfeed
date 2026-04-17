import sys
from datetime import datetime, timezone

from scraper.sources.rss import fetch_all_rss
from scraper.supabase_client import SupabaseClient


def main() -> None:
    print(
        f"=== OpenShift News Scraper started === {datetime.now(timezone.utc).isoformat()}"
    )
    articles = fetch_all_rss()
    print(f"Fetched {len(articles)} articles total")
    client = SupabaseClient()
    for article in articles:
        client.upsert_article(article)
    print(f"=== Scraper finished === {datetime.now(timezone.utc).isoformat()}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(exc)
        sys.exit(1)
