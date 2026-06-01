"""
Generates and delivers personalised AI briefings for Pro users who have
scheduled digest delivery configured.

Runs as a sub-stage of the main scraper after the standard digest stage.
Each user gets a digest filtered to their chosen categories, generated
via Claude Haiku, and delivered to their device tokens via FCM.

Personal digests are NOT stored in the shared ``digests`` table — they
are ephemeral push-only. The on-demand DigestScreen in the app still
reads from ``digests`` (the shared daily digest).
"""

from datetime import date

from scraper.digest import DigestGenerator
from scraper.fcm import FCMSender
from scraper.sources.digest_prefs import UserDigestPref, fetch_due_prefs
from scraper.supabase_client import SupabaseClient


def run_personal_digests(supabase: SupabaseClient, fcm: FCMSender) -> None:
    """Entry point — call once from main.py after the standard digest stage.

    Failures per user are caught and logged so a single misconfigured
    timezone or stale token can't crash the rest of the run (CLAUDE.md
    invariant)."""
    try:
        due = fetch_due_prefs(supabase.client)
    except Exception as e:
        print(f"[PersonalDigest] failed to fetch prefs: {e}")
        return

    if not due:
        return

    print(f"[PersonalDigest] {len(due)} user(s) due for delivery")
    for pref in due:
        try:
            _deliver_for_user(supabase, fcm, pref)
        except Exception as e:
            print(f"[PersonalDigest] Failed for user {pref.user_id}: {e}")


def _deliver_for_user(
    supabase: SupabaseClient,
    fcm: FCMSender,
    pref: UserDigestPref,
) -> None:
    """Generates and sends a personalised digest for one user."""
    generator = DigestGenerator(supabase)
    digest_text = generator.generate_filtered(
        categories=pref.categories or None,  # None ⇒ all
        target_date=date.today(),
        # Scope custom-feed visibility to this recipient: their own feeds
        # are eligible, no one else's leaks into their briefing.
        owner_id=pref.user_id,
    )

    if not digest_text:
        print(f"[PersonalDigest] No content for user {pref.user_id}, skipping")
        return

    title = "Your ShiftFeed Briefing"
    body = digest_text[:120]

    for token in pref.fcm_tokens:
        success = fcm.send_to_token(token=token, title=title, body=body)
        if not success:
            fcm.prune_stale_token(supabase.client, token)
