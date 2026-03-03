from __future__ import annotations

import json
import re
import time

import httpx

from .base import ResolvedVideo
from ..local_resolver import LocalResolveError


class KuaishouExtractor:
    platform = "kuaishou"

    _short_pattern = re.compile(r"https?://v\.kuaishou\.com/[a-zA-Z0-9_\-]+/?", re.I)
    _long_pattern = re.compile(
        r"https?://(?:www\.|m\.)?kuaishou\.com/(?:short-video|video)/[a-zA-Z0-9_\-]+",
        re.I,
    )

    # 快手 CDN 主机名片段
    _CDN_HOSTS = ("kwimgs.com", "kwai.net", "kuaishou.com")

    def extract_url(self, text: str) -> str | None:
        for pattern in (self._short_pattern, self._long_pattern):
            match = pattern.search(text)
            if match:
                return match.group(0).strip().rstrip("。.,!;，！；")
        return None

    def can_handle_source(self, source_url: str) -> bool:
        return any(host in source_url for host in self._CDN_HOSTS)

    def resolve(self, text: str) -> ResolvedVideo:
        url = self.extract_url(text)
        if not url:
            raise LocalResolveError("No Kuaishou URL found in input")

        try:
            headers = self._http_headers()
            with httpx.Client(timeout=20, follow_redirects=True, headers=headers) as client:
                resp = client.get(url)
                resp.raise_for_status()
                html = resp.text
                webpage_url = str(resp.url)
        except LocalResolveError:
            raise
        except Exception as exc:
            raise LocalResolveError(f"Kuaishou resolve failed: {exc}") from exc

        video_id = self._extract_video_id_from_url(webpage_url)
        title, candidates = self._parse_html(html)

        if not candidates:
            raise LocalResolveError("No video link found in Kuaishou page")

        video_id = video_id or f"ks_unknown_{int(time.time())}"

        return ResolvedVideo(
            platform=self.platform,
            input_url=url,
            webpage_url=webpage_url,
            title=title,
            video_id=video_id,
            best_url=candidates[0],
            candidates=candidates,
        )

    def download_bytes(self, source_url: str) -> tuple[bytes, str]:
        headers = self._http_headers() | {
            "Accept": "*/*",
            "Range": "bytes=0-",
        }
        try:
            with httpx.Client(timeout=60, follow_redirects=True, headers=headers) as client:
                resp = client.get(source_url)
                if 200 <= resp.status_code < 300 and resp.content:
                    return resp.content, source_url
            raise LocalResolveError(
                f"Kuaishou download failed: status={resp.status_code}"
            )
        except LocalResolveError:
            raise
        except Exception as exc:
            raise LocalResolveError(f"Kuaishou download failed: {exc}") from exc

    # ------------------------------------------------------------------
    # 内部方法
    # ------------------------------------------------------------------

    @staticmethod
    def _http_headers() -> dict[str, str]:
        return {
            "User-Agent": (
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
                "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 "
                "Mobile/15E148 Safari/604.1"
            ),
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh-Hans;q=0.9",
            "Referer": "https://www.kuaishou.com/",
        }

    @staticmethod
    def _extract_video_id_from_url(url: str) -> str | None:
        m = re.search(r"/(?:short-video|video)/([a-zA-Z0-9_\-]+)", url)
        return m.group(1) if m else None

    def _parse_html(self, html: str) -> tuple[str | None, list[str]]:
        """三级回退解析快手 HTML 页面，返回 (title, candidate_urls)。"""
        # 策略 1: window.__APOLLO_STATE__
        title, candidates = self._parse_apollo_state(html)
        if candidates:
            return title, candidates

        # 策略 2: window.__INITIAL_STATE__
        title2, candidates2 = self._parse_initial_state(html)
        if candidates2:
            return title2 or title, candidates2

        # 策略 3: 原始 HTML 正则匹配 CDN URL
        candidates3 = self._parse_raw_html(html)
        return None, candidates3

    def _parse_apollo_state(self, html: str) -> tuple[str | None, list[str]]:
        m = re.search(
            r"window\.__APOLLO_STATE__\s*=\s*(\{.*?\})\s*(?:;|</script>)",
            html,
            re.S,
        )
        if not m:
            return None, []

        try:
            root = json.loads(m.group(1))
        except Exception:
            return None, []

        title: str | None = None
        candidates: list[str] = []

        for key, value in root.items():
            if not isinstance(value, dict):
                continue
            if not any(tag in key for tag in ("Photo", "Work", "Video")):
                continue
            video_url = value.get("videoUrl") or value.get("video_url")
            if isinstance(video_url, str) and video_url.startswith("http"):
                if not title:
                    title = value.get("caption") or value.get("title")
                candidates.append(video_url)

        return title, list(dict.fromkeys(candidates))

    def _parse_initial_state(self, html: str) -> tuple[str | None, list[str]]:
        m = re.search(
            r"window\.__INITIAL_STATE__\s*=\s*(\{.*?\})\s*(?:;|</script>)",
            html,
            re.S,
        )
        if not m:
            return None, []

        try:
            root = json.loads(m.group(1).replace("undefined", "null"))
        except Exception:
            return None, []

        candidates: list[str] = []
        title: str | None = None

        def walk(node: object) -> None:
            nonlocal title
            if isinstance(node, dict):
                for k, v in node.items():
                    if k in ("videoUrl", "video_url", "mp4Url") and isinstance(v, str) and v.startswith("http"):
                        candidates.append(v)
                    elif k in ("caption", "title") and isinstance(v, str) and not title:
                        title = v
                    else:
                        walk(v)
            elif isinstance(node, list):
                for item in node:
                    walk(item)

        walk(root)
        return title, list(dict.fromkeys(candidates))

    @staticmethod
    def _parse_raw_html(html: str) -> list[str]:
        patterns = [
            r'(https?:\\/\\/[^"\']+kwimgs\.com[^"\']*\.mp4[^"\']*)',
            r'(https?:\\/\\/[^"\']+kwai\.net[^"\']*\.mp4[^"\']*)',
            r'(https?://[^"\']+kwimgs\.com[^"\']*\.mp4[^"\']*)',
            r'(https?://[^"\']+kwai\.net[^"\']*\.mp4[^"\']*)',
        ]
        candidates: list[str] = []
        for p in patterns:
            for m in re.finditer(p, html, re.I):
                url = m.group(1).replace("\\/", "/")
                candidates.append(url)
        return list(dict.fromkeys(candidates))
