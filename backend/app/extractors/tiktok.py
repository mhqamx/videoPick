from __future__ import annotations

import html as html_lib
import json
import re
import time
from urllib.parse import urlparse

from .base import BaseExtractor, ResolvedVideo, resolve_client
from ..local_resolver import LocalResolveError


class TikTokExtractor(BaseExtractor):
    platform = "tiktok"
    _CDN_HOSTS = (
        "tiktokcdn.com",
        "tiktokcdn-us.com",
        "tiktokv.com",
        "byteoversea.com",
        "ibytedtos.com",
        "muscdn.com",
    )
    _default_referer = "https://www.tiktok.com/"

    _short_pattern = re.compile(r"https?://(?:vm|vt)\.tiktok\.com/[a-zA-Z0-9]+/?", re.I)
    _share_pattern = re.compile(r"https?://(?:www\.)?tiktok\.com/t/[a-zA-Z0-9]+/?", re.I)
    _long_pattern = re.compile(
        r"https?://(?:www\.|m\.)?tiktok\.com/(?:@[\w.\-]+/video/\d+|v/\d+|embed/v2/\d+)",
        re.I,
    )
    _generic_pattern = re.compile(r"https?://[^\s]+")
    _video_id_pattern = re.compile(r"/(?:video|v|embed/v2)/(\d+)")

    def extract_url(self, text: str) -> str | None:
        for pattern in (self._short_pattern, self._share_pattern, self._long_pattern):
            match = pattern.search(text)
            if match:
                return match.group(0).strip().rstrip("。.,!;，！；")

        # 泛匹配仅在包含 tiktok 域名时生效
        match = self._generic_pattern.search(text)
        if match:
            candidate = match.group(0).strip().rstrip("。.,!;，！；")
            if "tiktok.com" in candidate.lower():
                return candidate
        return None

    def can_handle_source(self, source_url: str) -> bool:
        try:
            host = (urlparse(source_url).hostname or "").lower()
        except Exception:
            return False
        return any(host == d or host.endswith("." + d) or host.endswith("-" + d) for d in self._CDN_HOSTS)

    def resolve(self, text: str) -> ResolvedVideo:
        url = self.extract_url(text)
        if not url:
            raise LocalResolveError("No TikTok URL found in input")

        try:
            headers = self.default_http_headers(self._default_referer) | {
                "Accept-Language": "en-US,en;q=0.9,zh-CN;q=0.8",
            }
            resp = resolve_client.get(url, headers=headers)
            resp.raise_for_status()
            html = resp.text
            webpage_url = str(resp.url)
        except LocalResolveError:
            raise
        except Exception as exc:
            raise LocalResolveError(f"TikTok resolve failed: {exc}") from exc

        video_id = self._extract_video_id_from_url(webpage_url) or f"tt_unknown_{int(time.time())}"
        title, candidates = self._parse_html(html)

        if not candidates:
            raise LocalResolveError("No video link found in TikTok page")

        return ResolvedVideo(
            platform=self.platform,
            input_url=url,
            webpage_url=webpage_url,
            title=title,
            video_id=video_id,
            best_url=candidates[0],
            candidates=candidates,
        )

    # ------------------------------------------------------------------
    # 内部方法
    # ------------------------------------------------------------------

    def _extract_video_id_from_url(self, url: str) -> str | None:
        m = self._video_id_pattern.search(url)
        return m.group(1) if m else None

    def _parse_html(self, html: str) -> tuple[str | None, list[str]]:
        # 策略 1: __UNIVERSAL_DATA_FOR_REHYDRATION__
        title, candidates = self._parse_json_script(html, "__UNIVERSAL_DATA_FOR_REHYDRATION__")
        if candidates:
            return title, candidates

        # 策略 2: SIGI_STATE
        title2, candidates2 = self._parse_json_script(html, "SIGI_STATE")
        if candidates2:
            return title2 or title, candidates2

        # 策略 3: __NEXT_DATA__
        title3, candidates3 = self._parse_json_script(html, "__NEXT_DATA__")
        if candidates3:
            return title3 or title2 or title, candidates3

        # 策略 4: 原始 HTML 正则兜底
        candidates4 = self._parse_raw_html(html)
        return title3 or title2 or title, candidates4

    def _parse_json_script(self, html: str, script_id: str) -> tuple[str | None, list[str]]:
        root = self._extract_json_by_script_id(html, script_id)
        if root is None and script_id == "SIGI_STATE":
            root = self._extract_json_from_assignment(html)
        if not isinstance(root, (dict, list)):
            return None, []
        return self._collect_from_root(root)

    @staticmethod
    def _extract_json_by_script_id(html: str, script_id: str) -> dict | list | None:
        m = re.search(
            rf'<script[^>]*id="{re.escape(script_id)}"[^>]*>(.*?)</script>',
            html,
            re.S | re.I,
        )
        if not m:
            return None
        raw = m.group(1).strip()
        if not raw:
            return None
        try:
            return json.loads(raw)
        except Exception:
            return None

    @staticmethod
    def _extract_json_from_assignment(html: str) -> dict | list | None:
        patterns = [
            r"window\['SIGI_STATE'\]\s*=\s*(\{.*?\})\s*;",
            r"window\.SIGI_STATE\s*=\s*(\{.*?\})\s*;",
        ]
        for p in patterns:
            m = re.search(p, html, re.S)
            if not m:
                continue
            raw = m.group(1).replace("undefined", "null")
            try:
                return json.loads(raw)
            except Exception:
                continue
        return None

    def _collect_from_root(self, root: dict | list) -> tuple[str | None, list[str]]:
        title: str | None = None
        candidates: list[str] = []

        def walk(node: object) -> None:
            nonlocal title
            if isinstance(node, dict):
                for k, v in node.items():
                    if k in ("desc", "title", "seoTitle") and isinstance(v, str) and v.strip() and not title:
                        title = v.strip()
                    elif isinstance(v, str) and self._is_video_url_key(k):
                        normalized = self._normalize_candidate(v)
                        if normalized:
                            candidates.append(normalized)
                    else:
                        walk(v)
            elif isinstance(node, list):
                for item in node:
                    walk(item)

        walk(root)
        return title, list(dict.fromkeys(candidates))

    @staticmethod
    def _is_video_url_key(key: str) -> bool:
        return key in {
            "downloadAddr",
            "playAddr",
            "playApi",
            "url",
            "src",
        }

    def _normalize_candidate(self, value: str) -> str | None:
        if not value or not isinstance(value, str):
            return None
        url = value.strip()
        if not url.startswith("http"):
            return None

        # 兼容 JSON/HTML 中的转义字符
        url = (
            url.replace("\\u002F", "/")
            .replace("\\u0026", "&")
            .replace("\\/", "/")
            .replace("&amp;", "&")
        )
        url = html_lib.unescape(url)

        try:
            host = (urlparse(url).hostname or "").lower()
        except Exception:
            return None
        if not host:
            return None

        if any(host == d or host.endswith("." + d) or host.endswith("-" + d) for d in self._CDN_HOSTS):
            return url
        if url.endswith(".mp4") and ("tiktok" in host or "byte" in host):
            return url
        return None

    def _parse_raw_html(self, html: str) -> list[str]:
        patterns = [
            r'(https?:\\/\\/[^"\']+(?:tiktokcdn(?:-us)?\.com|tiktokv\.com|byteoversea\.com|ibytedtos\.com|muscdn\.com)[^"\']*)',
            r'(https?://[^"\']+(?:tiktokcdn(?:-us)?\.com|tiktokv\.com|byteoversea\.com|ibytedtos\.com|muscdn\.com)[^"\']*)',
            r'(https?:\\/\\/[^"\']+\.mp4[^"\']*)',
            r'(https?://[^"\']+\.mp4[^"\']*)',
        ]
        candidates: list[str] = []
        for p in patterns:
            for m in re.finditer(p, html, re.I):
                normalized = self._normalize_candidate(m.group(1))
                if normalized:
                    candidates.append(normalized)
        return list(dict.fromkeys(candidates))
