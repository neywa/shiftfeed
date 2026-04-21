import logging
import os

from dotenv import load_dotenv

load_dotenv()

from supabase import Client, create_client

from scraper.models import Article

_logger = logging.getLogger(__name__)


class SupabaseClient:
    def __init__(self) -> None:
        url = os.environ["SUPABASE_URL"]
        key = os.environ["SUPABASE_SECRET_KEY"]
        self._client: Client = create_client(url, key)

    def upsert_article(self, article: Article) -> None:
        try:
            row = article.to_dict()
            (
                self._client.table("articles")
                .upsert(row, on_conflict="url")
                .execute()
            )
            print(f"Saved: {article.title}")
        except Exception:
            _logger.exception("Failed to upsert article")

    def upsert_cve_alert(
        self, cve_id: str, title: str, article_url: str
    ) -> None:
        try:
            (
                self._client.table("cve_alerts")
                .upsert(
                    {
                        "cve_id": cve_id,
                        "title": title,
                        "article_url": article_url,
                    },
                    on_conflict="cve_id",
                )
                .execute()
            )
            print(f"CVE Alert: {cve_id}")
        except Exception:
            _logger.exception("Failed to upsert CVE alert %s", cve_id)
