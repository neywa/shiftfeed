"""
Routes a CVE-tagged article to its per-severity FCM topic.

**This is one half of a paired contract.** The other half is
``app/lib/models/cve_severity.dart`` (``CveSeverity.fromWord`` /
``fromTags``), which collapses the same two vocabularies for display on the
CVE screen. The two MUST agree: a user filters the CVE screen to "High" and
subscribes to High notifications expecting the same set of CVEs.
``tests/test_cve_severity.py`` parses the Dart source and fails if either
side is edited alone. Change both together.

Why the map is not six inline string comparisons
------------------------------------------------
Severity arrives in ``articles.tags`` in TWO vocabularies that the scraper
deliberately never merges (see CLAUDE.md, "Tag conventions"): Red Hat's
Hydra API says ``low/moderate/important/critical``, NVD says
``low/medium/high/critical``. ``cve_enrichment.py`` records which source won
rather than mapping between them, so both land in the same column.

The consequence is a silent-failure trap. Routing ``cve_high`` on the
literal ``high`` tag looks correct and is catastrophically wrong: measured
against the live table (331 CVE-tagged articles), Red Hat's ``important``
accounts for 194 of them and NVD's ``high`` for 11 — a ~15:1 split. Dropping
the Red Hat words would silently discard 305 of 331 articles (92%) while the
system continued to look healthy: notifications would still fire, tests
asserting "a high CVE routes to cve_high" would still pass, and only the
Red Hat-sourced majority would vanish.

So the mapping is an explicit table, keyed by every raw word we accept, with
the vocabulary each word comes from named in a comment.
"""

from scraper.models import Article

# Raw severity word (either vocabulary) -> FCM topic.
#
# DO NOT "simplify" this by dropping what look like synonyms. `important`
# and `moderate` are Red Hat's words and carry the overwhelming majority of
# real traffic; `high` and `medium` are NVD's. Removing either pair silently
# stops notifications for that source. See the module docstring.
SEVERITY_TOPICS: dict[str, str] = {
    "critical": "cve_critical",   # both vocabularies
    "important": "cve_high",      # Red Hat — Red Hat's "important" IS High
    "high": "cve_high",           # NVD
    "moderate": "cve_medium",     # Red Hat
    "medium": "cve_medium",       # NVD
    "low": "cve_low",             # both vocabularies
}

# Severity ordering, mirroring `CveSeverity.rank` in cve_severity.dart.
# Used to pick the worst severity on a multi-CVE article.
SEVERITY_RANK: dict[str, int] = {
    "cve_critical": 4,
    "cve_high": 3,
    "cve_medium": 2,
    "cve_low": 1,
}

# Every topic this module can route to, worst first. The client subscribes to
# these same strings (`kCveTopics` in notification_service.dart).
CVE_TOPICS: list[str] = ["cve_critical", "cve_high", "cve_medium", "cve_low"]


def severity_word_for_article(article: Article) -> str | None:
    """The worst recognised severity word on the article, or None.

    Takes the max rather than the first match, mirroring Dart's
    ``CveSeverity.fromTags``: a multi-CVE article can carry more than one
    severity word, and the scraper already stamps such articles with the
    *max* CVSS score — taking the max here keeps the notification and the
    score describing the same CVE.
    """
    worst_word: str | None = None
    worst_rank = 0
    for tag in article.tags or []:
        topic = SEVERITY_TOPICS.get(tag.lower().strip())
        if topic is None:
            continue
        rank = SEVERITY_RANK[topic]
        if rank > worst_rank:
            worst_rank = rank
            worst_word = tag.lower().strip()
    return worst_word


def topic_for_article(article: Article) -> str | None:
    """The FCM topic this article should push to, or None if unroutable.

    None means "no recognised severity word in tags" — either the article
    carries no severity at all (2 of 331 live articles) or it carries a word
    outside both vocabularies. The caller MUST log and skip rather than
    guessing a bucket: a wrong guess either wakes people for a low, or
    silently swallows a critical.
    """
    word = severity_word_for_article(article)
    return SEVERITY_TOPICS[word] if word else None
