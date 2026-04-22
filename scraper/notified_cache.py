from scraper.supabase_client import SupabaseClient


class NotifiedCache:
    def __init__(self, supabase_client: SupabaseClient) -> None:
        self.client = supabase_client

    def is_notified(self, url: str) -> bool:
        try:
            result = (
                self.client.client.table("articles")
                .select("notified")
                .eq("url", url)
                .single()
                .execute()
            )
            return result.data.get("notified", False)
        except Exception:
            return False

    def mark_notified(self, url: str) -> None:
        try:
            (
                self.client.client.table("articles")
                .update({"notified": True})
                .eq("url", url)
                .execute()
            )
        except Exception as e:
            print(f"Failed to mark notified: {e}")
