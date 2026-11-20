"""Offline tests for Red Hat Product Life Cycle API parsing and persistence."""

import json
from types import SimpleNamespace

from scraper.sources import ocp_lifecycles
from scraper.sources.ocp_lifecycles import parse_ocp_lifecycles


def _payload() -> dict:
    return {"data": [{"name": "Red Hat OpenShift Container Platform", "versions": [
        {"name": "4.22", "phases": [
            {"name": "General availability", "end_date": "2026-06-09T00:00:00.000Z"},
            {"name": "Full support", "end_date": "2026-12-31T00:00:00.000Z"},
            {"name": "Maintenance support", "end_date": "2027-12-31T00:00:00.000Z"},
            {"name": "Extended update support", "end_date": "2028-06-30T00:00:00.000Z"},
            {"name": "Extended update support Term 2", "end_date": "2029-06-30T00:00:00.000Z"},
            {"name": "Extended update support Term 3", "end_date": "N/A"},
        ]},
        {"name": "4.21", "phases": [
            {"name": "General availability", "end_date": "2026-02-03T00:00:00.000Z"},
            {"name": "Full support", "end_date": "2026-09-09T00:00:00.000Z"},
            {"name": "Maintenance support", "end_date": "2027-08-03T00:00:00.000Z"},
        ]},
    ]}]}


def test_parse_uses_the_last_available_eus_term() -> None:
    lifecycles = {
        item.minor_version: item
        for item in parse_ocp_lifecycles(json.dumps(_payload()))
    }

    assert lifecycles["4.22"].is_eus is True
    assert lifecycles["4.22"].eus_end.isoformat() == "2029-06-30"
    assert lifecycles["4.21"].is_eus is False
    assert lifecycles["4.21"].eus_end is None


class _Query:
    def __init__(self, rows: list[dict], writes: list[dict]) -> None:
        self.rows, self.writes, self.action = rows, writes, ""

    def select(self, *_args):
        self.action = "select"
        return self

    def upsert(self, row, *, on_conflict):
        assert on_conflict == "minor_version"
        self.action = "upsert"
        self.writes.append(row)
        return self

    def execute(self):
        return SimpleNamespace(data=self.rows if self.action == "select" else [])


class _Client:
    def __init__(self) -> None:
        self.writes: list[dict] = []
        self.client = self

    def table(self, name):
        assert name == "ocp_versions"
        return _Query(
            [{"minor_version": "4.22", "latest_stable": "4.22.4"}],
            self.writes,
        )


def test_sync_only_enriches_existing_channels(monkeypatch) -> None:
    client = _Client()
    monkeypatch.setattr(
        ocp_lifecycles,
        "fetch_feed_bytes",
        lambda _url: json.dumps(_payload()).encode(),
    )

    assert ocp_lifecycles.fetch_ocp_lifecycles(client) == 1
    assert client.writes[0]["minor_version"] == "4.22"
    assert client.writes[0]["latest_stable"] == "4.22.4"
    assert client.writes[0]["eus_end"] == "2029-06-30"
