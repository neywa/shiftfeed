import os
from datetime import date

import anthropic

from scraper.supabase_client import SupabaseClient


class DigestGenerator:
    def __init__(self, supabase: SupabaseClient):
        self.supabase = supabase
        self.client = anthropic.Anthropic(
            api_key=os.environ.get("ANTHROPIC_API_KEY")
        )

    def _fetch_todays_articles(self) -> list[dict]:
        try:
            today = date.today().isoformat()
            result = (
                self.supabase.client.table("articles")
                .select("title, url, source, tags, summary")
                .gte("created_at", today)
                .order("created_at", desc=True)
                .limit(20)
                .execute()
            )
            return result.data or []
        except Exception as e:
            print(f"Failed to fetch articles for digest: {e}")
            return []

    def _already_generated_today(self) -> bool:
        try:
            today = date.today().isoformat()
            result = (
                self.supabase.client.table("digests")
                .select("id")
                .eq("digest_date", today)
                .execute()
            )
            return len(result.data) > 0
        except Exception:
            return False

    def _generate_with_claude(self, articles: list[dict]) -> str:
        articles_text = "\n\n".join(
            [
                f"Title: {a['title']}\n"
                f"Source: {a['source']}\n"
                f"Tags: {', '.join(a.get('tags', []))}\n"
                f"Summary: {a.get('summary', 'N/A')[:200]}"
                for a in articles
            ]
        )

        message = self.client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=600,
            messages=[
                {
                    "role": "user",
                    "content": f"""You are ShiftFeed, an AI briefing assistant
for the OpenShift and Kubernetes community.

Based on these articles from today, write a concise daily briefing
for SREs and DevOps engineers. Use this exact format:

🔴 ShiftFeed Daily Briefing — [Day, Date]

**Top Stories**
- [2-3 sentence summary of the most important story]
- [2-3 sentence summary of second story]
- [2-3 sentence summary of third story]

**Security Watch**
[If any CVEs: mention them with severity. If none: write "No critical advisories today."]

**Releases**
[If any releases: list them briefly. If none: write "No new releases today."]

**Community Buzz**
[One sentence about interesting community discussion if any]

Keep it sharp, technical, and under 400 words.
Write for senior engineers who value brevity.

Today's articles:
{articles_text}""",
                }
            ],
        )
        return message.content[0].text

    def _save_digest(self, summary: str, articles: list[dict]) -> None:
        try:
            today = date.today().isoformat()
            top_articles = [
                {
                    "title": a["title"],
                    "url": a["url"],
                    "source": a["source"],
                }
                for a in articles[:5]
            ]
            self.supabase.client.table("digests").upsert(
                {
                    "digest_date": today,
                    "summary": summary,
                    "top_articles": top_articles,
                },
                on_conflict="digest_date",
            ).execute()
            print(f"Digest saved for {today}")
        except Exception as e:
            print(f"Failed to save digest: {e}")

    def generate(self) -> str | None:
        if self._already_generated_today():
            print("Digest already generated today, skipping.")
            return None

        articles = self._fetch_todays_articles()
        if not articles:
            print("No articles found for today, skipping digest.")
            return None

        print(f"Generating digest from {len(articles)} articles...")
        summary = self._generate_with_claude(articles)
        self._save_digest(summary, articles)
        print("Digest generated successfully.")
        return summary
