"""
Source-agnostic keyword relevance filter.

Most fetchers assert relevance *statically* — an article is "OpenShift"
because of the feed it came from (see the hardcoded per-entry ``tags`` in
:data:`scraper.sources.rss.RSS_SOURCES`), never because of its content.
That only works for narrow, all-relevant feeds; a broad feed would flood
the firehose with off-topic posts.

This module holds the keyword-matching core so any fetcher can filter on
content instead. :data:`RELEVANCE_KEYWORDS` is the single source of truth
— ``security.py`` matches Red Hat Hydra CVE payloads against the same set.

Matching is substring-based and case-insensitive, e.g. ``container``
matches ``openshift-container-platform``. That deliberately over-matches
on prose (``ocpus`` contains ``ocp``): a false positive only ever *keeps*
an article, which is the safe direction for a drop-filter.
"""

from __future__ import annotations

from dataclasses import dataclass

# The one source of truth. Wider than security.py's 6-package query set —
# it must never reject a CVE the query already fetched.
RELEVANCE_KEYWORDS: tuple[str, ...] = (
    "openshift",
    "ocp",
    "kubernetes",
    "container",
    "podman",
    "quay",
    "istio",
    "servicemesh",
    "envoy",
    "kiali",
)


@dataclass(frozen=True)
class RelevanceResult:
    """Outcome of a relevance check.

    ``matched`` lists every keyword found, in :data:`RELEVANCE_KEYWORDS`
    order, so callers can promote them to tags. Nothing does that yet.
    """

    passed: bool
    matched: list[str]


def evaluate_relevance(
    text: str,
    keywords: tuple[str, ...] = RELEVANCE_KEYWORDS,
) -> RelevanceResult:
    """Checks ``text`` against ``keywords``. Never raises.

    ``text`` is whatever the caller considers the article's searchable
    body — typically title + summary. Passing means at least one keyword
    appears somewhere in it.
    """
    haystack = (text or "").lower()
    matched = [keyword for keyword in keywords if keyword in haystack]
    return RelevanceResult(passed=bool(matched), matched=matched)
