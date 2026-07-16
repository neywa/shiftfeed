"""
One-time backfill: attach a CVSS score + severity to every cve-tagged
article that lacks one, and remove rejected CVEs.

Standalone entrypoint — deliberately NOT wired into the hourly job, which
has its own cheap ingest hook (``cve_enrichment.enrich_articles``). This
script exists to close the historical gap once.

    python -m scraper.backfill_cve_scores            # dry run (default)
    python -m scraper.backfill_cve_scores --commit   # actually write

Dry run is the default and prints exactly what would change, including the
full identity of every row it would delete, because deletes are the one
irreversible action here.

Ordering matters: scores are resolved from OTHER articles first (a plain
lookup, no network), and only unresolved ids hit the API.
"""

from __future__ import annotations

import argparse
from collections import Counter

from dotenv import load_dotenv

load_dotenv()

from scraper.sources.cve_enrichment import (  # noqa: E402
    CveScore,
    cve_ids_from_tags,
    decide,
    has_score,
    lookup_cve,
)
from scraper.supabase_client import SupabaseClient  # noqa: E402


def _fetch_cve_articles(client) -> list[dict]:
    rows, start = [], 0
    while True:
        page = (
            client.client.table("articles")
            .select("url,title,tags,source")
            .contains("tags", ["cve"])
            .range(start, start + 999)
            .execute()
            .data
            or []
        )
        rows += page
        if len(page) < 1000:
            break
        start += 1000
    return rows


def _score_map_from_articles(scored: list[dict]) -> dict[str, CveScore]:
    """Build {cve_id: CveScore} from articles that already carry a score.

    Only articles naming EXACTLY ONE CVE id are used. With two ids and one
    ``cvss:`` tag there is no way to know which CVE the score belongs to,
    and guessing would silently mis-attribute it. (Today every scored
    article has exactly one id, so nothing is lost by being strict.)
    """
    out: dict[str, CveScore] = {}
    for a in scored:
        ids = cve_ids_from_tags(a["tags"])
        if len(ids) != 1:
            continue
        tag = next((t for t in a["tags"] if t.startswith("cvss:")), None)
        if not tag:
            continue
        try:
            score = float(tag.split(":", 1)[1])
        except ValueError:
            continue
        severity = next(
            (
                t
                for t in a["tags"]
                if t in ("critical", "important", "moderate", "low")
            ),
            None,
        )
        out[ids[0]] = CveScore(
            cvss_score=score, severity=severity, source="join"
        )
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--commit",
        action="store_true",
        help="Actually write. Without it, nothing is modified.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Only resolve the first N CVE ids via API (for a quick probe).",
    )
    args = parser.parse_args()
    mode = "COMMIT" if args.commit else "DRY RUN"
    print(f"=== CVE score backfill [{mode}] ===\n")

    client = SupabaseClient()
    rows = _fetch_cve_articles(client)
    scored = [a for a in rows if has_score(a["tags"])]
    unscored = [a for a in rows if not has_score(a["tags"])]
    print(f"cve-tagged articles: {len(rows)}  scored: {len(scored)}  "
          f"unscored: {len(unscored)}")
    if not unscored:
        print("Nothing to do.")
        return

    # --- Stage 1: resolve from other articles (free) ---
    join_map = _score_map_from_articles(scored)
    needed = sorted({c for a in unscored for c in cve_ids_from_tags(a["tags"])})
    from_join = {c: join_map[c] for c in needed if c in join_map}
    to_fetch = [c for c in needed if c not in from_join]
    print(f"distinct unscored CVE ids: {len(needed)}")
    print(f"  resolved by join (no API call): {len(from_join)}")
    print(f"  needing an API call           : {len(to_fetch)}")

    if args.limit is not None:
        to_fetch = to_fetch[: args.limit]
        print(f"  --limit: only fetching {len(to_fetch)}")

    # --- Stage 2: API lookups ---
    resolved: dict[str, CveScore] = dict(from_join)
    print(f"\nresolving {len(to_fetch)} CVE id(s) — Hydra first, NVD on 404...")
    for i, cve_id in enumerate(to_fetch, 1):
        score = lookup_cve(cve_id)
        resolved[cve_id] = score
        if score.rejected:
            state = "REJECTED"
        elif score.scored:
            state = f"{score.cvss_score} {score.severity or '-'}"
        elif score.lookup_failed:
            state = "LOOKUP FAILED (retryable)"
        else:
            state = "no score published"
        print(f"  [{i:3}/{len(to_fetch)}] {cve_id:18} {str(score.source or '-'):6} {state}")

    # --- Stage 3: decide per article ---
    counts: Counter = Counter()
    by_source: Counter = Counter()
    deletes, detags, scores, unscorable, failed = [], [], [], [], []
    strip_only = 0
    for a in unscored:
        d = decide(a["url"], a["tags"], resolved)
        counts[d.action] += 1
        if d.action == "drop":
            deletes.append((a, d))
        elif d.action == "detag":
            detags.append((a, d))
        elif d.action == "score":
            scores.append((a, d))
            by_source[resolved[d.scored_cve].source] += 1
            if d.rejected_cves:
                # Scored AND had a rejected id stripped — counted under
                # SCORE, so surface it separately or the strip is invisible.
                strip_only += 1
        else:
            ids = cve_ids_from_tags(a["tags"])
            if any(resolved.get(c, CveScore()).lookup_failed for c in ids):
                failed.append((a, d))
            else:
                unscorable.append((a, d))

    print("\n" + "=" * 62)
    print("RESULT")
    print("=" * 62)
    print(f"  would SCORE            : {len(scores)}")
    for src, n in by_source.most_common():
        print(f"      via {src:8}       : {n}")
    print(f"  would DETAG (rejected) : {len(detags)}")
    print(f"  would DELETE (rejected CVE record): {len(deletes)}")
    print(f"  (also stripping a rejected id while scoring: {strip_only})")
    print(f"  LOOKUP FAILED (retryable, NOT unscorable): {len(failed)}")
    print(f"  genuinely unscorable   : {len(unscorable)}")

    if deletes:
        print("\n--- EXACT DELETE TARGETS (articles rows) ---")
        for a, d in deletes:
            print(f"  url    : {a['url']}")
            print(f"  title  : {a['title']}")
            print(f"  source : {a['source']}")
            print(f"  tags   : {a['tags']}")
            print(f"  reason : rejected {list(d.rejected_cves)}")
            print()
    if detags:
        print("--- DETAG TARGETS (article kept, rejected ids stripped) ---")
        for a, d in detags[:20]:
            print(f"  {a['url']}")
            print(f"     {a['tags']}  ->  {d.tags}")
    if failed:
        print("\n--- LOOKUP FAILED (API error, not a missing score) ---")
        print("    Re-run to retry these; they are NOT unscorable.")
        for a, _ in failed[:20]:
            print(f"  {cve_ids_from_tags(a['tags'])}  {a['url'][:70]}")
    if unscorable:
        print("\n--- GENUINELY UNSCORABLE (API answered, no score) ---")
        for a, _ in unscorable[:20]:
            print(f"  {cve_ids_from_tags(a['tags'])}  {a['url'][:70]}")

    if not args.commit:
        print("\nDRY RUN — nothing was written. Re-run with --commit to apply.")
        return

    # --- Stage 4: writes ---
    print("\nCommitting...")
    for a, d in scores:
        client.client.table("articles").update({"tags": d.tags}).eq(
            "url", a["url"]
        ).execute()
        client.upsert_cve_alert(
            cve_id=d.scored_cve,
            title=a["title"],
            article_url=a["url"],
            cvss=d.cvss_score,
            severity=d.severity,
        )
    for a, d in detags:
        client.client.table("articles").update({"tags": d.tags}).eq(
            "url", a["url"]
        ).execute()
        for cve_id in d.rejected_cves:
            client.client.table("cve_alerts").delete().eq(
                "cve_id", cve_id
            ).execute()
    for a, d in deletes:
        print(f"  DELETE {a['url']}")
        client.client.table("articles").delete().eq("url", a["url"]).execute()
        for cve_id in d.rejected_cves:
            client.client.table("cve_alerts").delete().eq(
                "cve_id", cve_id
            ).execute()
    print(
        f"Done. scored={len(scores)} detagged={len(detags)} "
        f"deleted={len(deletes)}"
    )


if __name__ == "__main__":
    main()
