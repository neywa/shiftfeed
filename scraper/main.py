import sys
from datetime import datetime, timezone

from scraper.sources.cve_tagger import enrich_with_cve_tags
from scraper.sources.github_releases import fetch_github_releases
from scraper.sources.rss import fetch_all_rss
from scraper.sources.security import fetch_security_advisories
from scraper.supabase_client import SupabaseClient


def main() -> None:
    print(
        f"=== OpenShift News Scraper started === {datetime.now(timezone.utc).isoformat()}"
    )

    rss_articles = [enrich_with_cve_tags(a) for a in fetch_all_rss()]
    github_articles = [
        enrich_with_cve_tags(a) for a in fetch_github_releases()
    ]
    security_articles = [
        enrich_with_cve_tags(a) for a in fetch_security_advisories()
    ]

    all_articles = rss_articles + github_articles + security_articles

    print(f"RSS articles: {len(rss_articles)}")
    print(f"GitHub release articles: {len(github_articles)}")
    print(f"Security advisory articles: {len(security_articles)}")
    cve_count = sum(1 for a in all_articles if "cve" in a.tags)
    print(f"Articles with CVE tags: {cve_count}")
    print(f"Total: {len(all_articles)}")

    client = SupabaseClient()
    for article in all_articles:
        client.upsert_article(article)

    for article in all_articles:
        for tag in article.tags:
            if tag.startswith("CVE-"):
                client.upsert_cve_alert(
                    cve_id=tag,
                    title=article.title,
                    article_url=article.url,
                )

    print(f"=== Scraper finished === {datetime.now(timezone.utc).isoformat()}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(exc)
        sys.exit(1)
