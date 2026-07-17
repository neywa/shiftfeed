import argparse
import sys
import time
from datetime import datetime, timezone

from scraper.digest import DigestGenerator
from scraper.digest_personal import run_personal_digests
from scraper.fcm import FCMSender
from scraper.models import Article
from scraper.notified_cache import NotifiedCache
from scraper.sources.alert_rule_matcher import article_matches_rule
from scraper.sources.alert_rules import fetch_active_rules
from scraper.sources.cve_enrichment import enrich_articles
from scraper.sources.cve_severity import (
    CVE_TOPICS,
    severity_word_for_article,
    topic_for_article,
)
from scraper.sources.cve_tagger import enrich_with_cve_tags
from scraper.sources.github_releases import fetch_github_releases
from scraper.sources.ocp_versions import fetch_ocp_version_updates
from scraper.sources.operator_lifecycles import fetch_operator_lifecycles
from scraper.sources.rss import fetch_all_rss
from scraper.sources.security import fetch_security_advisories
from scraper.sources.user_rss import (
    fetch_articles_for_source,
    fetch_user_sources,
    update_source_error,
)
from scraper.supabase_client import SupabaseClient


def _topic_label(topic: str) -> str:
    """'cve_high' -> 'High'. Display name for the batch push title."""
    return topic.removeprefix("cve_").capitalize()


def route_cve_articles(
    articles: list[Article],
) -> tuple[dict[str, list[Article]], list[Article]]:
    """Splits CVE articles into per-topic buckets plus an unroutable list.

    Pure — no I/O, no logging. The caller decides what to do with the
    unroutable ones (main() logs and skips them; the dry-run reports them).
    """
    routed: dict[str, list[Article]] = {topic: [] for topic in CVE_TOPICS}
    unroutable: list[Article] = []
    for article in articles:
        topic = topic_for_article(article)
        if topic is None:
            unroutable.append(article)
            continue
        routed[topic].append(article)
    return routed, unroutable


def push_cve_alerts(
    new_cves: list[Article],
    fcm: FCMSender,
    cache: NotifiedCache,
    dry_run: bool = False,
) -> tuple[dict[str, list[Article]], list[Article]]:
    """Routes each new CVE article to its severity topic and pushes.

    Per topic, mirrors the shape the single ``security`` topic used to have:
    one new CVE sends a detailed alert, several collapse into one batch. The
    busiest observed day (14 CVEs) becomes ~3 pushes rather than 14.

    Articles with no recognised severity are logged and skipped — never
    guessed into a bucket. They ARE still marked notified, so an article
    that will never be routable doesn't re-log on every hourly run.

    When ``dry_run`` is True this sends nothing and writes nothing (the
    ledger is left untouched), so it can be run against live data safely.
    """
    routed, unroutable = route_cve_articles(new_cves)

    for article in unroutable:
        print(
            f"[cve_routing] no recognised severity on {article.url} "
            f"— skipping push"
        )

    sent_any = False
    for topic in CVE_TOPICS:
        group = routed[topic]
        if not group:
            continue

        # Space real sends out, but only BETWEEN them — never after the
        # last, which would just stall the rest of the run.
        if sent_any and not dry_run:
            time.sleep(1)
        sent_any = True

        if len(group) == 1:
            article = group[0]
            cve_id = next(
                (t for t in article.tags if t.startswith("CVE-")), "CVE"
            )
            # Title carries the article's own severity word, not the bucket
            # name — a Red Hat CVE says IMPORTANT, an NVD one says HIGH.
            severity = severity_word_for_article(article) or "unknown"
            if dry_run:
                print(
                    f"[dry-run] WOULD SEND -> {topic}: {cve_id} "
                    f"({severity}) — {article.title[:60]}"
                )
            else:
                fcm.send_cve_alert(
                    topic=topic,
                    cve_id=cve_id,
                    title=article.title,
                    severity=severity,
                    url=article.url,
                )
        else:
            label = _topic_label(topic)
            first = group[0]
            body = first.title[:80] + f" and {len(group) - 1} more..."
            if dry_run:
                ids = ", ".join(
                    next((t for t in a.tags if t.startswith("CVE-")), "CVE")
                    for a in group[:5]
                )
                more = "" if len(group) <= 5 else f", +{len(group) - 5} more"
                print(
                    f"[dry-run] WOULD SEND -> {topic}: batch of "
                    f"{len(group)} ({ids}{more})"
                )
            else:
                fcm.send_to_topic(
                    topic=topic,
                    title=f"🔴 {len(group)} New {label} CVEs",
                    body=body,
                    data={"type": "cve_batch", "count": len(group)},
                )

    if not dry_run:
        # Every new CVE article is marked, including the unroutable ones.
        for article in new_cves:
            cache.mark_notified(article.url)

    return routed, unroutable


def _report_dry_run(
    all_articles: list[Article],
    new_cves: list[Article],
    fcm: FCMSender,
    cache: NotifiedCache,
) -> None:
    """Prints the routing distribution without sending or writing anything.

    Reports TWO views, because either alone is misleading:

    1. Every cve-tagged article this run saw, ledger ignored. In steady
       state the ledger has already marked them all notified, so view 2 is
       empty and proves nothing about the mapping. This view is what shows
       the Red Hat words (`important`/`moderate`) actually being caught.
    2. The real would-send set after the notified filter. This is what an
       actual run would do right now — and an empty result here IS the
       idempotency proof.
    """
    all_cves = [a for a in all_articles if "cve" in a.tags]
    routed, unroutable = route_cve_articles(all_cves)

    print()
    print("=" * 60)
    print("DRY RUN — no Firebase calls, no ledger writes")
    print("=" * 60)
    print()
    print(f"View 1: routing across ALL {len(all_cves)} cve-tagged articles")
    print("        (notified ledger ignored — proves the mapping)")
    print()

    word_counts: dict[str, int] = {}
    for article in all_cves:
        word = severity_word_for_article(article)
        key = word or "<none>"
        word_counts[key] = word_counts.get(key, 0) + 1

    for topic in CVE_TOPICS:
        words = sorted(
            f"{w}={n}"
            for w, n in word_counts.items()
            if w != "<none>" and topic_for_word(w) == topic
        )
        detail = f"   [{', '.join(words)}]" if words else ""
        print(f"  {topic:<14} {len(routed[topic]):>4}{detail}")
    print(f"  {'<unroutable>':<14} {len(unroutable):>4}")
    print()

    if unroutable:
        print("  Unroutable articles (would be logged + skipped, not sent):")
        for article in unroutable[:10]:
            print(f"    - {article.url}")
        print()

    print(f"View 2: real would-send set — {len(new_cves)} un-notified CVE(s)")
    print()
    if not new_cves:
        print("  (nothing new — every cve-tagged article is already marked")
        print("   notified, so a real run would send zero pushes. This is")
        print("   the idempotency guarantee holding.)")
    else:
        push_cve_alerts(new_cves, fcm, cache, dry_run=True)
    print()
    print("=" * 60)


def topic_for_word(word: str) -> str | None:
    """Topic for a raw severity word — thin wrapper for the dry-run report."""
    from scraper.sources.cve_severity import SEVERITY_TOPICS

    return SEVERITY_TOPICS.get(word)


def main(dry_run_push: bool = False) -> None:
    print(
        f"=== OpenShift News Scraper started === {datetime.now(timezone.utc).isoformat()}"
    )

    client = SupabaseClient()

    rss_articles = [enrich_with_cve_tags(a) for a in fetch_all_rss()]
    github_articles = [
        enrich_with_cve_tags(a) for a in fetch_github_releases()
    ]
    security_articles = [
        enrich_with_cve_tags(a) for a in fetch_security_advisories()
    ]
    try:
        result = (
            client.client.table("ocp_versions").select("id").limit(1).execute()
        )
        is_first_run = len(result.data) == 0
    except Exception:
        is_first_run = False

    ocp_articles = [
        enrich_with_cve_tags(a)
        for a in fetch_ocp_version_updates(client, seed_only=is_first_run)
    ]
    if is_first_run:
        print("OCP versions: seeded table, no articles generated")

    try:
        result = (
            client.client.table("operator_versions")
            .select("id")
            .limit(1)
            .execute()
        )
        operators_first_run = len(result.data) == 0
    except Exception:
        operators_first_run = False

    operator_articles = [
        enrich_with_cve_tags(a)
        for a in fetch_operator_lifecycles(
            client, seed_only=operators_first_run
        )
    ]
    if operators_first_run:
        print("Operator life cycles: seeded table, no articles generated")

    all_articles = (
        rss_articles
        + github_articles
        + security_articles
        + ocp_articles
        + operator_articles
    )

    # User custom RSS sources (Phase 6 — Pro users)
    user_sources = fetch_user_sources(client.client)
    user_articles_total = 0
    for user_source in user_sources:
        user_articles = [
            enrich_with_cve_tags(a)
            for a in fetch_articles_for_source(user_source)
        ]
        if user_articles:
            update_source_error(client.client, user_source.source_id, None)
            all_articles.extend(user_articles)
            user_articles_total += len(user_articles)
        else:
            update_source_error(
                client.client,
                user_source.source_id,
                "No articles fetched — check the feed URL",
            )

    print(f"RSS articles: {len(rss_articles)}")
    print(f"GitHub release articles: {len(github_articles)}")
    print(f"Security advisory articles: {len(security_articles)}")
    print(f"OCP version update articles: {len(ocp_articles)}")
    print(f"Operator lifecycle articles: {len(operator_articles)}")
    print(
        f"User RSS articles: {user_articles_total} "
        f"(from {len(user_sources)} user feed(s))"
    )
    tagged_cve_count = sum(1 for a in all_articles if "cve" in a.tags)
    print(f"Articles with CVE tags: {tagged_cve_count}")
    print(f"Total: {len(all_articles)}")

    # Score any cve-tagged article the regex path minted without one (Istio
    # bulletins, blog mentions), and drop rejected CVE records — BEFORE the
    # upsert, so an unscored or withdrawn CVE never reaches the feed. Reads
    # cve_alerts as a cache first, so a steady-state run makes ~0 API calls.
    all_articles, dropped = enrich_articles(all_articles, client)
    if dropped:
        print(f"Dropped {len(dropped)} rejected CVE record(s)")

    for article in all_articles:
        client.upsert_article(article)

    for article in all_articles:
        cvss = next(
            (t for t in article.tags if t.startswith("cvss:")), None
        )
        cvss_value = float(cvss.split(":", 1)[1]) if cvss else None
        severity = next(
            (
                t
                for t in article.tags
                if t in ("critical", "important", "moderate", "low", "high", "medium")
            ),
            None,
        )
        for tag in article.tags:
            if tag.startswith("CVE-"):
                client.upsert_cve_alert(
                    cve_id=tag,
                    title=article.title,
                    article_url=article.url,
                    cvss=cvss_value,
                    severity=severity,
                )

    fcm = FCMSender()
    cache = NotifiedCache(client)

    # Snapshot of all newly-arrived articles for this run, taken BEFORE
    # mark_notified runs below so custom alert rules can match anything
    # new — not just CVE/release tagged items.
    new_articles = [a for a in all_articles if not cache.is_notified(a.url)]

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

    if dry_run_push:
        _report_dry_run(all_articles, new_cves, fcm, cache)
        return

    push_cve_alerts(new_cves, fcm, cache)

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

    # --- Custom alert rules (Pro users) ---
    try:
        rules = fetch_active_rules(client.client)
    except Exception as e:
        print(f"[alert_rules] failed to fetch rules: {e}")
        rules = []

    if rules and new_articles:
        custom_pushes = 0
        for article in new_articles:
            try:
                for rule in rules:
                    if not article_matches_rule(article, rule):
                        continue
                    body = (article.summary or "")[:120]
                    for token in rule.fcm_tokens:
                        success = fcm.send_to_token(
                            token=token,
                            title=f"[{rule.name}] {article.title}",
                            body=body,
                            data={
                                "url": article.url,
                                "rule_id": rule.rule_id,
                            },
                        )
                        if success:
                            custom_pushes += 1
                        else:
                            fcm.prune_stale_token(client.client, token)
            except Exception as e:
                print(
                    f"[alert_rules] error matching article {article.url}: {e}"
                )
        print(
            f"Custom rule pushes: {custom_pushes} "
            f"({len(rules)} rules x {len(new_articles)} new articles)"
        )

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

    # Stage 5: Personalised digests (Pro users with scheduled delivery)
    run_personal_digests(client, fcm)

    print(f"=== Scraper finished === {datetime.now(timezone.utc).isoformat()}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(prog="scraper.main")
    parser.add_argument(
        "--dry-run-push",
        action="store_true",
        help=(
            "Fetch and upsert as normal, then report what the CVE push "
            "stage WOULD send (topic + CVE id + severity) without calling "
            "Firebase or touching the notified ledger. Skips the release, "
            "alert-rule and digest stages."
        ),
    )
    args = parser.parse_args()
    try:
        main(dry_run_push=args.dry_run_push)
    except Exception as exc:
        print(exc)
        sys.exit(1)
