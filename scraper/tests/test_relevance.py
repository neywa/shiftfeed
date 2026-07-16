"""Tests for the shared relevance filter and security.py's use of it."""

from __future__ import annotations

from typing import Any

import pytest

from scraper.sources.relevance import (
    RELEVANCE_KEYWORDS,
    evaluate_relevance,
)
from scraper.sources.security import _is_relevant

# ---------------------------------------------------------------------------
# Regression guard for the security.py refactor.
#
# Verbatim copy of _is_relevant + its keyword tuple as they existed before
# the shared-core extraction. The point is to compare the refactored code
# against the ORIGINAL CODE rather than against hand-written expectations —
# hand-written ones can encode the same mistake twice.
# ---------------------------------------------------------------------------

_LEGACY_KEYWORDS = (
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


def _legacy_is_relevant(entry: dict[str, Any]) -> bool:
    title = entry.get("bugzilla_description") or entry.get("CVE") or ""
    haystack = title.lower()
    packages = entry.get("affected_packages") or []
    for pkg in packages:
        haystack += f" {str(pkg).lower()}"
    return any(keyword in haystack for keyword in _LEGACY_KEYWORDS)


# Hydra-shaped entries covering every branch of the haystack construction.
_CVE_CORPUS: list[dict[str, Any]] = [
    # Match via the description.
    {"CVE": "CVE-2024-1", "bugzilla_description": "flaw in OpenShift router"},
    {"CVE": "CVE-2024-2", "bugzilla_description": "kubernetes apiserver bug"},
    # Match via affected_packages only — description is off-topic.
    {
        "CVE": "CVE-2024-3",
        "bugzilla_description": "buffer overflow in libfoo",
        "affected_packages": ["openshift-container-platform-4.15"],
    },
    {
        "CVE": "CVE-2024-4",
        "bugzilla_description": "memory leak",
        "affected_packages": ["podman-4.9.4-1.el9", "unrelated-lib"],
    },
    # No match anywhere — must be rejected.
    {
        "CVE": "CVE-2024-5",
        "bugzilla_description": "flaw in the firefox pdf viewer",
        "affected_packages": ["firefox-128.0"],
    },
    {"CVE": "CVE-2024-6", "bugzilla_description": "glibc printf issue"},
    # Description missing/empty -> falls back to the bare CVE id, which
    # contains no keyword, so these reject.
    {"CVE": "CVE-2024-7"},
    {"CVE": "CVE-2024-8", "bugzilla_description": ""},
    {"CVE": "CVE-2024-9", "bugzilla_description": None},
    # Fallback still reachable via packages when description is absent.
    {"CVE": "CVE-2024-10", "affected_packages": ["quay-3.11"]},
    # Case-insensitivity.
    {"CVE": "CVE-2024-11", "bugzilla_description": "ISTIO sidecar CVE"},
    {"CVE": "CVE-2024-12", "affected_packages": ["OpenShift-GitOps"]},
    # Substring quirks the legacy code accepts — parity must be preserved,
    # not silently "fixed".
    {"CVE": "CVE-2024-13", "bugzilla_description": "containerd runtime flaw"},
    {"CVE": "CVE-2024-14", "bugzilla_description": "the ocpus benchmark"},
    # Empty / degenerate shapes.
    {},
    {"affected_packages": []},
    {"affected_packages": None},
    {"CVE": "", "bugzilla_description": ""},
    # Non-string package entries (legacy str()-coerces them).
    {"CVE": "CVE-2024-15", "affected_packages": [123, None]},
    {"CVE": "CVE-2024-16", "affected_packages": [{"name": "istio"}]},
]


@pytest.mark.parametrize("entry", _CVE_CORPUS)
def test_security_relevance_unchanged(entry: dict[str, Any]) -> None:
    """Refactored _is_relevant matches the pre-refactor implementation."""
    assert _is_relevant(entry) == _legacy_is_relevant(entry), entry


def test_security_corpus_covers_both_outcomes() -> None:
    """Guards the parity test above from passing vacuously."""
    results = [_legacy_is_relevant(e) for e in _CVE_CORPUS]
    assert any(results), "corpus has no relevant entries"
    assert not all(results), "corpus has no irrelevant entries"


def test_keyword_set_not_narrowed() -> None:
    """The shared set must stay the wider net vs the 6-package query set."""
    assert set(RELEVANCE_KEYWORDS) == set(_LEGACY_KEYWORDS)


# ---------------------------------------------------------------------------
# The shared core itself.
# ---------------------------------------------------------------------------


def test_evaluate_relevance_passes_and_reports_matches() -> None:
    result = evaluate_relevance("OpenShift 4.16 ships a new Istio version")
    assert result.passed
    assert result.matched == ["openshift", "istio"]


def test_evaluate_relevance_drops_offtopic() -> None:
    result = evaluate_relevance("Hello world: my first blog post")
    assert not result.passed
    assert result.matched == []


def test_evaluate_relevance_is_case_insensitive() -> None:
    assert evaluate_relevance("KUBERNETES v1.31").passed


def test_evaluate_relevance_handles_empty_text() -> None:
    for text in ("", None):
        result = evaluate_relevance(text)  # type: ignore[arg-type]
        assert not result.passed
        assert result.matched == []


def test_matched_order_follows_keyword_set() -> None:
    """Callers promoting matches to tags get a stable, deterministic order."""
    result = evaluate_relevance("kiali envoy istio openshift")
    assert result.matched == ["openshift", "istio", "envoy", "kiali"]
