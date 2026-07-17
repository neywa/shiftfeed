"""
Tests the CVE push stage: per-topic grouping, the single-vs-batch shape,
and the notified-ledger idempotency guarantee.
"""

from scraper.main import push_cve_alerts, route_cve_articles
from scraper.models import Article


def _article(tags: list[str], url: str) -> Article:
    return Article(
        title=f"Advisory {url}",
        url=url,
        source="test",
        tags=tags,
        summary=None,
        published_at=None,
    )


class FakeFCM:
    """Records sends instead of calling Firebase."""

    def __init__(self):
        self.single: list[dict] = []
        self.batches: list[dict] = []

    def send_cve_alert(self, topic, cve_id, title, severity, url):
        self.single.append(
            {"topic": topic, "cve_id": cve_id, "severity": severity}
        )

    def send_to_topic(self, topic, title, body, data=None):
        self.batches.append({"topic": topic, "title": title, "data": data})


class FakeCache:
    def __init__(self, notified: set[str] | None = None):
        self.notified = notified or set()
        self.marked: list[str] = []

    def is_notified(self, url: str) -> bool:
        return url in self.notified

    def mark_notified(self, url: str) -> None:
        self.marked.append(url)
        self.notified.add(url)


class TestRouting:
    def test_articles_group_by_severity_bucket(self):
        articles = [
            _article(["cve", "critical", "CVE-2026-1"], "u1"),
            _article(["cve", "important", "CVE-2026-2"], "u2"),
            _article(["cve", "high", "CVE-2026-3"], "u3"),
            _article(["cve", "moderate", "CVE-2026-4"], "u4"),
            _article(["cve", "medium", "CVE-2026-5"], "u5"),
            _article(["cve", "low", "CVE-2026-6"], "u6"),
        ]
        routed, unroutable = route_cve_articles(articles)

        assert len(routed["cve_critical"]) == 1
        # Both vocabularies land together — this is the whole point.
        assert len(routed["cve_high"]) == 2, "important + high share a bucket"
        assert len(routed["cve_medium"]) == 2, "moderate + medium share a bucket"
        assert len(routed["cve_low"]) == 1
        assert unroutable == []

    def test_single_cve_sends_detailed_alert_to_its_topic(self):
        fcm, cache = FakeFCM(), FakeCache()
        push_cve_alerts(
            [_article(["cve", "important", "CVE-2026-9"], "u1")], fcm, cache
        )
        assert fcm.batches == []
        assert fcm.single == [
            {
                "topic": "cve_high",
                "cve_id": "CVE-2026-9",
                # Source vocabulary preserved in the title.
                "severity": "important",
            }
        ]

    def test_multiple_in_one_bucket_collapse_into_one_batch(self):
        fcm, cache = FakeFCM(), FakeCache()
        push_cve_alerts(
            [
                _article(["cve", "important", "CVE-2026-1"], "u1"),
                _article(["cve", "high", "CVE-2026-2"], "u2"),
                _article(["cve", "important", "CVE-2026-3"], "u3"),
            ],
            fcm,
            cache,
        )
        assert fcm.single == []
        assert len(fcm.batches) == 1
        assert fcm.batches[0]["topic"] == "cve_high"
        assert "3 New High CVEs" in fcm.batches[0]["title"]

    def test_buckets_push_independently(self):
        # One critical (detailed) alongside two mediums (batched): each
        # bucket decides single-vs-batch on its OWN count, not the total.
        fcm, cache = FakeFCM(), FakeCache()
        push_cve_alerts(
            [
                _article(["cve", "critical", "CVE-2026-1"], "u1"),
                _article(["cve", "moderate", "CVE-2026-2"], "u2"),
                _article(["cve", "medium", "CVE-2026-3"], "u3"),
            ],
            fcm,
            cache,
        )
        assert [s["topic"] for s in fcm.single] == ["cve_critical"]
        assert [b["topic"] for b in fcm.batches] == ["cve_medium"]
        assert "2 New Medium CVEs" in fcm.batches[0]["title"]

    def test_empty_bucket_sends_nothing(self):
        fcm, cache = FakeFCM(), FakeCache()
        push_cve_alerts([_article(["cve", "low", "CVE-1"], "u1")], fcm, cache)
        topics = [s["topic"] for s in fcm.single] + [
            b["topic"] for b in fcm.batches
        ]
        assert topics == ["cve_low"], "only the populated bucket fires"


class TestIdempotency:
    """articles.notified is the ledger — an article pushes once, not hourly."""

    def test_new_articles_are_marked_notified(self):
        fcm, cache = FakeFCM(), FakeCache()
        push_cve_alerts(
            [_article(["cve", "critical", "CVE-2026-1"], "u1")], fcm, cache
        )
        assert cache.marked == ["u1"]

    def test_rerun_over_already_notified_articles_sends_nothing(self):
        # Mirrors main(): the caller filters on is_notified before pushing.
        articles = [
            _article(["cve", "critical", "CVE-2026-1"], "u1"),
            _article(["cve", "important", "CVE-2026-2"], "u2"),
        ]
        cache = FakeCache()

        first_fcm = FakeFCM()
        new = [a for a in articles if not cache.is_notified(a.url)]
        push_cve_alerts(new, first_fcm, cache)
        assert len(first_fcm.single) == 2

        # Second run: same articles re-served by RSS, ledger now populated.
        second_fcm = FakeFCM()
        new = [a for a in articles if not cache.is_notified(a.url)]
        assert new == [], "ledger must filter everything already pushed"
        push_cve_alerts(new, second_fcm, cache)
        assert second_fcm.single == []
        assert second_fcm.batches == []


class TestDryRun:
    """Dry run must be inert — no sends, no ledger writes."""

    def test_dry_run_sends_nothing_and_writes_nothing(self, capsys):
        fcm, cache = FakeFCM(), FakeCache()
        push_cve_alerts(
            [
                _article(["cve", "critical", "CVE-2026-1"], "u1"),
                _article(["cve", "important", "CVE-2026-2"], "u2"),
                _article(["cve", "important", "CVE-2026-3"], "u3"),
            ],
            fcm,
            cache,
            dry_run=True,
        )
        assert fcm.single == []
        assert fcm.batches == []
        assert cache.marked == [], "dry run must not touch the ledger"

        out = capsys.readouterr().out
        assert "WOULD SEND -> cve_critical" in out
        assert "WOULD SEND -> cve_high" in out

    def test_dry_run_still_reports_routing(self):
        fcm, cache = FakeFCM(), FakeCache()
        routed, unroutable = push_cve_alerts(
            [_article(["cve", "moderate", "CVE-2026-1"], "u1")],
            fcm,
            cache,
            dry_run=True,
        )
        assert len(routed["cve_medium"]) == 1
