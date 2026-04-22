import sys
import time
from datetime import datetime, timezone

from scraper.digest import DigestGenerator
from scraper.fcm import FCMSender
from scraper.notified_cache import NotifiedCache
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
    tagged_cve_count = sum(1 for a in all_articles if "cve" in a.tags)
    print(f"Articles with CVE tags: {tagged_cve_count}")
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

    fcm = FCMSender()
    cache = NotifiedCache(client)

    new_cves = [
        a
        for a in all_articles
        if "cve" in a.tags and not cache.is_notified(a.url)
    ]
    new_releases = [
        a
        for a in all_articles
        if "release" in a.tags and not cache.is_notified(a.url)
    ]

    cve_count = len(new_cves)
    release_count = len(new_releases)

    if cve_count == 1:
        article = new_cves[0]
        severity = next(
            (
                t
                for t in article.tags
                if t in ("critical", "important", "moderate")
            ),
            None,
        )
        cve_id = next(
            (t for t in article.tags if t.startswith("CVE-")),
            "CVE",
        )
        fcm.send_cve_alert(
            cve_id=cve_id,
            title=article.title,
            severity=severity or "unknown",
            url=article.url,
        )
    elif cve_count > 1:
        first = new_cves[0]
        body = first.title[:80] + f" and {cve_count - 1} more..."
        fcm.send_to_topic(
            topic="security",
            title=f"🔴 {cve_count} New Security Advisories",
            body=body,
            data={"type": "cve_batch", "count": cve_count},
        )

    for article in new_cves:
        cache.mark_notified(article.url)

    if cve_count > 0 and release_count > 0:
        time.sleep(1)

    if release_count == 1:
        article = new_releases[0]
        fcm.send_release_alert(
            title=article.title,
            url=article.url,
        )
    elif release_count > 1:
        first = new_releases[0]
        fcm.send_to_topic(
            topic="releases",
            title=f"🚀 {release_count} New Releases",
            body=first.title[:100],
            data={"type": "release_batch", "count": release_count},
        )

    for article in new_releases:
        cache.mark_notified(article.url)

    print(f"Notified: {cve_count} CVEs, {release_count} releases")

    print("Generating AI daily digest...")
    digest_gen = DigestGenerator(client)
    digest = digest_gen.generate()
    if digest:
        print("=== TODAY'S DIGEST ===")
        print(digest)
        print("=== END DIGEST ===")
        fcm.send_to_topic(
            topic="all",
            title="🔴 ShiftFeed Daily Briefing",
            body="Your OpenShift intelligence digest is ready. Tap to read.",
            data={"type": "digest"},
        )

    print(f"=== Scraper finished === {datetime.now(timezone.utc).isoformat()}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(exc)
        sys.exit(1)
