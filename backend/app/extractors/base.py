from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Protocol

import httpx

from ..local_resolver import LocalResolveError

logger = logging.getLogger(__name__)


@dataclass
class ResolvedVideo:
    platform: str
    input_url: str
    webpage_url: str | None
    title: str | None
    video_id: str
    best_url: str
    candidates: list[str]
    media_type: str = "video"  # "video" | "image"
    image_urls: list[str] | None = None

    def __post_init__(self):
        if self.image_urls is None:
            self.image_urls = []


class VideoExtractor(Protocol):
    platform: str

    def extract_url(self, text: str) -> str | None:
        ...

    def can_handle_source(self, source_url: str) -> bool:
        ...

    def resolve(self, text: str, client_cookies: dict[str, str] | None = None) -> ResolvedVideo:
        ...

    def download_bytes(self, source_url: str) -> tuple[bytes, str]:
        ...


# ---------------------------------------------------------------------------
# 共享 HTTP Client（模块级单例，进程退出时自动关闭）
# ---------------------------------------------------------------------------

resolve_client = httpx.Client(
    timeout=20,
    follow_redirects=True,
    limits=httpx.Limits(max_connections=20, max_keepalive_connections=5),
)

download_client = httpx.Client(
    timeout=120,
    follow_redirects=True,
    limits=httpx.Limits(max_connections=10),
)


def close_shared_clients() -> None:
    """在 FastAPI shutdown 事件中调用。"""
    resolve_client.close()
    download_client.close()


# ---------------------------------------------------------------------------
# BaseExtractor — 提供公共方法，子类可覆盖
# ---------------------------------------------------------------------------

_MOBILE_USER_AGENT = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 "
    "Mobile/15E148 Safari/604.1"
)


class BaseExtractor:
    platform: str = ""
    _CDN_HOSTS: tuple[str, ...] = ()
    _default_referer: str = ""

    @staticmethod
    def default_http_headers(referer: str) -> dict[str, str]:
        return {
            "User-Agent": _MOBILE_USER_AGENT,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh-Hans;q=0.9",
            "Referer": referer,
        }

    def can_handle_source(self, source_url: str) -> bool:
        return any(host in source_url for host in self._CDN_HOSTS)

    def download_bytes(self, source_url: str) -> tuple[bytes, str]:
        """通用下载实现，子类可覆盖。"""
        headers = self.default_http_headers(self._default_referer) | {
            "Accept": "*/*",
            "Range": "bytes=0-",
        }
        try:
            resp = download_client.get(source_url, headers=headers)
            if 200 <= resp.status_code < 300 and resp.content:
                return resp.content, source_url
            raise LocalResolveError(
                f"{self.platform} download failed: status={resp.status_code}"
            )
        except LocalResolveError:
            raise
        except Exception as exc:
            raise LocalResolveError(f"{self.platform} download failed: {exc}") from exc
