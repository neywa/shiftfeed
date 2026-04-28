"""
Matches a scraped Article against an AlertRule.
Pure functions — no I/O.
"""

from scraper.models import Article
from scraper.sources.alert_rules import AlertRule


def article_matches_rule(article: Article, rule: AlertRule) -> bool:
    """
    Returns True if the article satisfies all conditions of the rule.

    Category check:
      - Empty rule.categories means all categories match.
      - Otherwise the article must have at least one tag that matches
        a rule category (case-insensitive).
        Category name mapping:
          'security' -> article tag 'security' or 'cve'
          'releases' -> article tag 'release'
          'ocp'      -> article tag 'ocp'

    CVSS check (only when rule.cvss_minimum is set):
      - Article must have a tag matching CVE-* pattern AND
        the article's cvss score must be >= rule.cvss_minimum.
      - Article CVSS is parsed from tags: look for a tag like 'cvss:8.5'.
        If no cvss tag exists, the CVSS check fails (article excluded).

    Keyword check (only when rule.keywords is non-empty):
      - At least one keyword must appear in article.title.lower()
        or article.summary.lower().
    """
    article_tags = {t.lower() for t in (article.tags or [])}

    if rule.categories:
        category_tag_map = {
            "security": {"security", "cve"},
            "releases": {"release"},
            "ocp": {"ocp"},
        }
        matched_category = False
        for cat in rule.categories:
            cat_tags = category_tag_map.get(cat.lower(), {cat.lower()})
            if article_tags & cat_tags:
                matched_category = True
                break
        if not matched_category:
            return False

    if rule.cvss_minimum is not None:
        cvss_score: float | None = None
        for tag in article_tags:
            if tag.startswith("cvss:"):
                try:
                    cvss_score = float(tag.split(":", 1)[1])
                except ValueError:
                    pass
        if cvss_score is None or cvss_score < rule.cvss_minimum:
            return False

    if rule.keywords:
        haystack = (
            (article.title or "").lower() + " " + (article.summary or "").lower()
        )
        if not any(kw in haystack for kw in rule.keywords):
            return False

    return True
