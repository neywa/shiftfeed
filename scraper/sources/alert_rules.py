"""
Fetches enabled alert rules and associated device tokens from Supabase.
Used by the notify stage to dispatch custom per-user push notifications.
"""

from dataclasses import dataclass
from typing import Optional

from supabase import Client


@dataclass
class AlertRule:
    rule_id: str
    user_id: str
    name: str
    categories: list[str]   # [] means all categories
    cvss_minimum: Optional[float]
    keywords: list[str]     # [] means no keyword filter
    fcm_tokens: list[str]   # device tokens for this user


def fetch_active_rules(supabase: Client) -> list[AlertRule]:
    """
    Returns all enabled alert rules joined with their owner's device tokens.
    Rules without any registered device tokens are excluded.
    """
    rules_resp = (
        supabase.table("user_alert_rules")
        .select("id, user_id, name, categories, cvss_minimum, keywords")
        .eq("enabled", True)
        .execute()
    )

    if not rules_resp.data:
        return []

    user_ids = list({r["user_id"] for r in rules_resp.data})

    tokens_resp = (
        supabase.table("user_device_tokens")
        .select("user_id, fcm_token")
        .in_("user_id", user_ids)
        .execute()
    )

    token_map: dict[str, list[str]] = {}
    for row in (tokens_resp.data or []):
        token_map.setdefault(row["user_id"], []).append(row["fcm_token"])

    result: list[AlertRule] = []
    for r in rules_resp.data:
        tokens = token_map.get(r["user_id"], [])
        if not tokens:
            continue
        result.append(
            AlertRule(
                rule_id=r["id"],
                user_id=r["user_id"],
                name=r["name"],
                categories=r["categories"] or [],
                cvss_minimum=r.get("cvss_minimum"),
                keywords=[k.lower() for k in (r["keywords"] or [])],
                fcm_tokens=tokens,
            )
        )
    return result
