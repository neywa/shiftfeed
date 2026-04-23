from __future__ import annotations

import logging
import os
import re
from datetime import datetime
from typing import Any

import httpx

from scraper.models import Article

_logger = logging.getLogger(__name__)

GITHUB_REPOS: list[dict[str, Any]] = [
    {
        "repo": "operator-framework/operator-sdk",
        "source": "GitHub Releases",
        "tags": ["release", "operators", "sdk"],
    },
    {
        "repo": "openshift/rosa",
        "source": "GitHub Releases",
        "tags": ["release", "rosa", "cloud"],
    },
    {
        "repo": "argoproj/argo-cd",
        "source": "GitHub Releases",
        "tags": ["release", "gitops", "argocd"],
    },
    {
        "repo": "tektoncd/pipeline",
        "source": "GitHub Releases",
        "tags": ["release", "tekton", "cicd"],
    },
    {
        "repo": "istio/istio",
        "source": "GitHub Releases",
        "tags": ["release", "istio", "servicemesh"],
    },
]


def _strip_markdown(body: str) -> str:
    text = re.sub(r"^#+\s*", "", body, flags=re.MULTILINE)
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)
    text = text.replace("`", "")
    return text.strip()


def _repo_short_name(repo: str) -> str:
    return repo.split("/", 1)[1].upper()


def _parse_published_at(raw: str | None) -> datetime | None:
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None


def _headers() -> dict[str, str]:
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def _article_from_release(
    release: dict[str, Any],
    repo: str,
    source: str,
    tags: list[str],
) -> Article | None:
    if release.get("draft") or release.get("prerelease"):
        return None

    tag_name = release.get("tag_name")
    html_url = release.get("html_url")
    if not tag_name or not html_url:
        return None

    repo_name = _repo_short_name(repo)
    title = f"{repo_name} {tag_name} released"

    body = release.get("body")
    if body:
        summary = _strip_markdown(str(body))
        if len(summary) > 300:
            summary = summary[:300].rstrip() + "..."
    else:
        summary = f"New release {tag_name} of {repo_name}"

    combined_tags = list(dict.fromkeys([*tags, "release"]))

    return Article(
        title=title,
        url=str(html_url),
        source=source,
        tags=combined_tags,
        summary=summary,
        published_at=_parse_published_at(release.get("published_at")),
    )


def fetch_github_releases() -> list[Article]:
    articles: list[Article] = []
    headers = _headers()

    for config in GITHUB_REPOS:
        repo = config["repo"]
        source = config["source"]
        tags = config["tags"]
        url = f"https://api.github.com/repos/{repo}/releases?per_page=5"
        _logger.info("Fetching releases: %s", repo)

        try:
            response = httpx.get(
                url, headers=headers, timeout=10.0, follow_redirects=True
            )
            response.raise_for_status()
            releases = response.json()
        except Exception:
            _logger.exception("Failed to fetch releases for %s", repo)
            continue

        if not isinstance(releases, list):
            _logger.warning(
                "Unexpected releases payload for %s: %r", repo, releases
            )
            continue

        for release in releases:
            try:
                article = _article_from_release(release, repo, source, tags)
                if article is not None:
                    articles.append(article)
            except Exception:
                _logger.exception(
                    "Failed to process release for %s: %r",
                    repo,
                    release.get("tag_name"),
                )

    return articles
