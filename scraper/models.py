from dataclasses import dataclass
from datetime import datetime


@dataclass
class Article:
    title: str
    url: str
    source: str
    tags: list[str]
    summary: str | None
    published_at: datetime | None

    def to_dict(self) -> dict[str, object]:
        return {
            "title": self.title,
            "url": self.url,
            "source": self.source,
            "tags": self.tags,
            "summary": self.summary,
            "published_at": (
                self.published_at.isoformat() if self.published_at is not None else None
            ),
        }
