from __future__ import annotations

import re

from scraper.models import Article

_CVE_PATTERN = re.compile(r"CVE-\d{4}-\d+", re.IGNORECASE)


def enrich_with_cve_tags(article: Article) -> Article:
    text = (article.title or "") + " " + (article.summary or "")
    found_cves = _CVE_PATTERN.findall(text)
    if not found_cves:
        return article

    new_tags = list(article.tags)
    if "cve" not in new_tags:
        new_tags.append("cve")
    if "security" not in new_tags:
        new_tags.append("security")
    for cve in found_cves[:3]:
        cve_upper = cve.upper()
        if cve_upper not in new_tags:
            new_tags.append(cve_upper)

    return Article(
        title=article.title,
        url=article.url,
        source=article.source,
        tags=new_tags,
        summary=article.summary,
        published_at=article.published_at,
    )
