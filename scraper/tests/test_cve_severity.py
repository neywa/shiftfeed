"""
Tests for per-severity CVE notification routing.

The failure mode these exist for is SILENT and expensive. Severity lives in
``articles.tags`` in two vocabularies that are never merged (Red Hat:
low/moderate/important/critical; NVD: low/medium/high/critical). Someone
"simplifying" SEVERITY_TOPICS by dropping `important`/`moderate` as apparent
synonyms produces code that compiles, passes any test that only checks
`high` -> cve_high, and silently stops notifying for 92% of real CVEs — the
Red Hat words carry ~15x the traffic of the NVD ones.

So: every accepted word is pinned individually, and the Red Hat pair is
pinned with an explicit reason.
"""

import re
from pathlib import Path

from scraper.models import Article
from scraper.sources.cve_severity import (
    CVE_TOPICS,
    SEVERITY_TOPICS,
    severity_word_for_article,
    topic_for_article,
)

# The Dart half of the paired contract.
_DART_SEVERITY = (
    Path(__file__).resolve().parents[2]
    / "app"
    / "lib"
    / "models"
    / "cve_severity.dart"
)


def _article(tags: list[str], url: str = "https://example.com/a") -> Article:
    return Article(
        title="Some CVE advisory",
        url=url,
        source="test",
        tags=tags,
        summary=None,
        published_at=None,
    )


class TestSeverityMapping:
    """Every raw tag -> topic, pinned one by one."""

    def test_critical_routes_to_cve_critical(self):
        assert topic_for_article(_article(["cve", "critical"])) == "cve_critical"

    def test_important_routes_to_cve_high(self):
        # THE TRAP. Red Hat's "important" IS High — it is not a synonym for
        # some other bucket and it is not droppable. 194 of 331 live
        # cve-tagged articles carry this word; routing it anywhere but
        # cve_high silently disables notifications for the majority of real
        # traffic while everything still appears to work.
        assert topic_for_article(_article(["cve", "important"])) == "cve_high", (
            "Red Hat's 'important' must route to cve_high — it is the "
            "largest real bucket (194/331 articles)"
        )

    def test_high_routes_to_cve_high(self):
        # NVD's own word. Both vocabularies must land in the same bucket.
        assert topic_for_article(_article(["cve", "high"])) == "cve_high"

    def test_moderate_routes_to_cve_medium(self):
        # The second half of the trap: Red Hat's "moderate" (111/331 live
        # articles) vs NVD's "medium" (2/331).
        assert topic_for_article(_article(["cve", "moderate"])) == "cve_medium", (
            "Red Hat's 'moderate' must route to cve_medium — dropping it "
            "silently loses 111/331 articles"
        )

    def test_medium_routes_to_cve_medium(self):
        assert topic_for_article(_article(["cve", "medium"])) == "cve_medium"

    def test_low_routes_to_cve_low(self):
        assert topic_for_article(_article(["cve", "low"])) == "cve_low"

    def test_both_vocabularies_are_present(self):
        # A structural guard against a "cleanup" that keeps one scale only.
        red_hat = {"critical", "important", "moderate", "low"}
        nvd = {"critical", "high", "medium", "low"}
        assert red_hat <= set(SEVERITY_TOPICS), "Red Hat vocabulary incomplete"
        assert nvd <= set(SEVERITY_TOPICS), "NVD vocabulary incomplete"

    def test_every_mapped_topic_is_a_known_cve_topic(self):
        assert set(SEVERITY_TOPICS.values()) == set(CVE_TOPICS)

    def test_matching_is_case_insensitive(self):
        assert topic_for_article(_article(["CVE", "IMPORTANT"])) == "cve_high"


class TestUnmappedSeverity:
    """Unmapped/missing severity must be visible, never guessed."""

    def test_article_with_no_severity_tag_is_unroutable(self):
        # 2 of 331 live articles are in this state.
        assert topic_for_article(_article(["cve", "security"])) is None

    def test_article_with_unknown_severity_word_is_unroutable(self):
        assert topic_for_article(_article(["cve", "catastrophic"])) is None

    def test_unroutable_article_is_logged_and_skipped_not_dropped(self, capsys):
        from scraper.main import push_cve_alerts

        sent: list[str] = []

        class FakeFCM:
            def send_cve_alert(self, **kw):
                sent.append(kw["topic"])

            def send_to_topic(self, **kw):
                sent.append(kw["topic"])

        class FakeCache:
            def __init__(self):
                self.marked = []

            def mark_notified(self, url):
                self.marked.append(url)

        cache = FakeCache()
        article = _article(["cve"], url="https://example.com/no-severity")
        routed, unroutable = push_cve_alerts([article], FakeFCM(), cache)

        assert unroutable == [article]
        assert sent == [], "must not guess a bucket for unknown severity"
        out = capsys.readouterr().out
        assert "no recognised severity" in out
        assert "https://example.com/no-severity" in out, "must name the article"
        # Still marked, so it doesn't re-log every hourly run forever.
        assert cache.marked == ["https://example.com/no-severity"]


class TestWorstSeverityWins:
    """Mirrors Dart's CveSeverity.fromTags taking the max, not the first."""

    def test_multi_severity_article_takes_the_worst(self):
        article = _article(["cve", "low", "critical", "moderate"])
        assert topic_for_article(article) == "cve_critical"

    def test_worst_is_independent_of_tag_order(self):
        assert topic_for_article(_article(["critical", "low"])) == "cve_critical"
        assert topic_for_article(_article(["low", "critical"])) == "cve_critical"

    def test_cross_vocabulary_worst(self):
        # Red Hat 'moderate' vs NVD 'high' -> high wins.
        assert topic_for_article(_article(["moderate", "high"])) == "cve_high"

    def test_severity_word_preserves_source_vocabulary(self):
        # The push title says IMPORTANT for a Red Hat CVE, not HIGH.
        assert severity_word_for_article(_article(["important"])) == "important"


class TestDartContract:
    """Pins the Python map against the Dart display mapping.

    app/ and scraper/ never import from each other, so the two mappings are
    separate literals. This parses the Dart source and fails if either side
    is edited alone — the same trick nav_tabs_test.dart uses to pin tab
    order against source text.
    """

    def _parse_dart_from_word(self) -> dict[str, str]:
        src = _DART_SEVERITY.read_text()
        body = src.split("static CveSeverity? fromWord(")[1].split(
            "static CveSeverity? fromTags("
        )[0]

        mapping: dict[str, str] = {}
        pending: list[str] = []
        for line in body.splitlines():
            line = line.strip()
            case_match = re.match(r"^case '([a-z]+)':$", line)
            if case_match:
                pending.append(case_match.group(1))
                continue
            ret_match = re.match(r"^return CveSeverity\.([a-z]+);$", line)
            if ret_match and pending:
                for word in pending:
                    mapping[word] = ret_match.group(1)
                pending = []
        return mapping

    def test_dart_source_is_parseable(self):
        # If this fails the parser is stale, not the mapping — fix the parser
        # rather than deleting the test, or the contract stops being checked.
        parsed = self._parse_dart_from_word()
        assert parsed, f"could not parse fromWord() from {_DART_SEVERITY}"
        assert len(parsed) == 6, f"expected 6 words, parsed {parsed}"

    def test_python_and_dart_agree_word_for_word(self):
        parsed = self._parse_dart_from_word()
        # Dart buckets are enum names (critical/high/medium/low); ours are
        # topics (cve_critical/...). Compare on the shared bucket name.
        dart_buckets = {word: bucket for word, bucket in parsed.items()}
        python_buckets = {
            word: topic.removeprefix("cve_")
            for word, topic in SEVERITY_TOPICS.items()
        }
        assert python_buckets == dart_buckets, (
            "SEVERITY_TOPICS and CveSeverity.fromWord have drifted. These "
            "are a paired contract: the CVE screen's 'High' filter and the "
            "cve_high notification topic must describe the same CVEs. "
            f"python={python_buckets} dart={dart_buckets}"
        )
