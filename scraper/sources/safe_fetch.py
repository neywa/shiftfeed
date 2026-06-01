"""
SSRF / DoS guard for fetching untrusted feed URLs.

Pro users supply arbitrary RSS feed URLs (``user_rss_sources.url``). The
scraper must not let those URLs reach internal services, cloud-metadata
endpoints, or local files, and must not hang or OOM on a hostile
response. :func:`fetch_feed_bytes` fetches feed bytes with:

  * a scheme allowlist (http/https only — no ``file://``/``ftp://``/``gopher://``),
  * DNS resolution + an IP guard that rejects loopback / link-local /
    private / reserved / non-global addresses (blocks ``127.0.0.1``,
    ``::1``, ``169.254.169.254`` cloud metadata, ``10/8``, ``192.168/16``,
    ``fc00::/7``, …),
  * manual redirect handling that re-runs the guard on every hop (so a
    public URL that 302s to an internal IP is blocked at the hop),
  * an explicit connect+read timeout, and
  * a hard response-size cap enforced while streaming.

feedparser is intentionally NOT given the URL — it would perform its own
unguarded network I/O (and would resolve ``file://``). Callers pass the
returned bytes to ``feedparser.parse(content)`` instead.
"""

from __future__ import annotations

import ipaddress
import socket
from urllib.parse import urljoin, urlsplit

import httpx

_ALLOWED_SCHEMES = frozenset({"http", "https"})
_MAX_BYTES = 5 * 1024 * 1024  # 5 MB — reject larger bodies before parsing
_MAX_REDIRECTS = 2
_TIMEOUT = httpx.Timeout(10.0)  # connect + read, applied to every hop
_USER_AGENT = "ShiftFeed/1.0 (+https://neywa.github.io/shiftfeed/)"


class FeedFetchError(Exception):
    """Raised when a URL fails the SSRF guard or exceeds the fetch limits."""


def _ip_is_blocked(ip: ipaddress.IPv4Address | ipaddress.IPv6Address) -> bool:
    """True for any address that must never be fetched from the scraper.

    ``is_private`` already covers RFC-1918 (``10/8``, ``172.16/12``,
    ``192.168/16``) and IPv6 unique-local (``fc00::/7``); the remaining
    flags catch loopback, link-local (incl. ``169.254.0.0/16`` metadata),
    reserved, multicast and unspecified ranges. ``not is_global`` is a
    belt-and-braces catch-all for anything not publicly routable."""
    return (
        ip.is_loopback
        or ip.is_link_local
        or ip.is_private
        or ip.is_reserved
        or ip.is_multicast
        or ip.is_unspecified
        or not ip.is_global
    )


def _guard_url(url: str) -> None:
    """Raise :class:`FeedFetchError` unless ``url`` is a safe public
    http(s) target. Validates the scheme and every resolved IP."""
    parts = urlsplit(url)
    if parts.scheme.lower() not in _ALLOWED_SCHEMES:
        raise FeedFetchError(f"blocked scheme: {parts.scheme!r}")

    host = parts.hostname
    if not host:
        raise FeedFetchError("missing host in URL")

    # A bare IP literal in the URL needs no DNS lookup — check it directly.
    try:
        literal = ipaddress.ip_address(host)
    except ValueError:
        literal = None
    if literal is not None:
        if _ip_is_blocked(literal):
            raise FeedFetchError(f"blocked IP literal: {host}")
        return

    # Hostname: resolve and reject if ANY resolved address is non-public
    # (a host with even one internal A/AAAA record is rejected outright).
    try:
        infos = socket.getaddrinfo(
            host, parts.port or 0, proto=socket.IPPROTO_TCP
        )
    except socket.gaierror as e:
        raise FeedFetchError(f"DNS resolution failed for {host}: {e}") from e
    if not infos:
        raise FeedFetchError(f"no addresses resolved for {host}")
    for info in infos:
        ip_str = info[4][0]
        if _ip_is_blocked(ipaddress.ip_address(ip_str)):
            raise FeedFetchError(f"blocked resolved IP {ip_str} for host {host}")


def _read_capped(response: httpx.Response) -> bytes:
    """Stream the body, aborting if it exceeds :data:`_MAX_BYTES`."""
    chunks: list[bytes] = []
    total = 0
    for chunk in response.iter_bytes():
        total += len(chunk)
        if total > _MAX_BYTES:
            raise FeedFetchError(
                f"response body exceeds {_MAX_BYTES}-byte cap"
            )
        chunks.append(chunk)
    return b"".join(chunks)


def fetch_feed_bytes(url: str) -> bytes:
    """Fetch ``url`` and return the response body bytes.

    The SSRF guard runs on the initial URL and on every redirect hop;
    an explicit timeout and a hard size cap bound the cost. Raises
    :class:`FeedFetchError` on any guard violation or limit breach
    (callers swallow per-feed, preserving the run's isolation invariant)."""
    current = url
    with httpx.Client(
        follow_redirects=False,  # we follow manually so the guard re-runs
        timeout=_TIMEOUT,
        headers={"User-Agent": _USER_AGENT},
    ) as client:
        for _ in range(_MAX_REDIRECTS + 1):
            _guard_url(current)
            with client.stream("GET", current) as response:
                if response.is_redirect:
                    location = response.headers.get("location")
                    if not location:
                        raise FeedFetchError("redirect without Location header")
                    current = urljoin(current, location)
                    continue
                response.raise_for_status()
                return _read_capped(response)
    raise FeedFetchError(f"too many redirects (> {_MAX_REDIRECTS})")
