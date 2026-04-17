import logging
import os

from dotenv import load_dotenv

load_dotenv()

from supabase import Client, create_client

from models import Article

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
