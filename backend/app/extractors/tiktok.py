from __future__ import annotations

import html as html_lib
import json
import logging
import re
import time
from urllib.parse import urlparse

from .base import BaseExtractor, ResolvedVideo, resolve_client
from ..local_resolver import LocalResolveError

logger = logging.getLogger(__name__)


class TikTokExtractor(BaseExtractor):
    platform = "tiktok"
    _CDN_HOSTS = (
        "tiktokcdn.com",
        "tiktokcdn-us.com",
        "tiktokv.com",
        "byteoversea.com",
        "ibytedtos.com",
        "muscdn.com",
        "tiktok.com",
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

    _DESKTOP_UA = (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    )

    def extract_url(self, text: str) -> str | None:
        for pattern in (self._short_pattern, self._share_pattern, self._long_pattern):
            match = pattern.search(text)
            if match:
                return match.group(0).strip().rstrip("。.,!;，！；")

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
        return any(
            host == d or host.endswith("." + d) or host.endswith("-" + d)
            for d in self._CDN_HOSTS
        )

    def resolve(self, text: str) -> ResolvedVideo:
        url = self.extract_url(text)
        if not url:
            raise LocalResolveError("No TikTok URL found in input")

        # Step 1: 解析短链获取 video_id
        video_id = self._resolve_video_id(url)
        if not video_id:
            raise LocalResolveError("Could not extract TikTok video ID")

        # Step 2: 通过 embed 页面获取带有效 token 的视频 URL
        title, candidates = self._resolve_via_embed(video_id)

        # Step 3: 若 embed 失败，回退到主页面解析
        if not candidates:
            logger.info("Embed page failed, falling back to main page for %s", video_id)
            title2, candidates = self._resolve_via_main_page(url)
            title = title or title2

        if not candidates:
            raise LocalResolveError("No video link found in TikTok page")

        return ResolvedVideo(
            platform=self.platform,
            input_url=url,
            webpage_url=f"https://www.tiktok.com/embed/v2/{video_id}",
            title=title,
            video_id=video_id,
            best_url=candidates[0],
            candidates=candidates,
        )

    # ------------------------------------------------------------------
    # Step 1: 获取 video_id
    # ------------------------------------------------------------------

    def _resolve_video_id(self, url: str) -> str | None:
        """从 URL 中提取 video_id，短链需先跟随重定向。"""
        vid = self._extract_video_id_from_url(url)
        if vid:
            return vid

        # 短链 → 跟随重定向获取长链
        try:
            headers = self.default_http_headers(self._default_referer)
            resp = resolve_client.get(url, headers=headers)
            return self._extract_video_id_from_url(str(resp.url))
        except Exception as exc:
            logger.warning("Failed to resolve short URL %s: %s", url, exc)
            return None

    def _extract_video_id_from_url(self, url: str) -> str | None:
        m = self._video_id_pattern.search(url)
        return m.group(1) if m else None

    # ------------------------------------------------------------------
    # Step 2: embed 页面解析（首选，URL 带有效 token）
    # ------------------------------------------------------------------

    def _resolve_via_embed(self, video_id: str) -> tuple[str | None, list[str]]:
        """通过 /embed/v2/{id} 获取视频 URL，此页面返回的 URL 带有效下载 token。"""
        embed_url = f"https://www.tiktok.com/embed/v2/{video_id}"
        try:
            resp = resolve_client.get(embed_url, headers={
                "User-Agent": self._DESKTOP_UA,
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                "Accept-Language": "en-US,en;q=0.9",
            })
            resp.raise_for_status()
        except Exception as exc:
            logger.warning("Embed page fetch failed for %s: %s", video_id, exc)
            return None, []

        return self._parse_embed_html(resp.text, video_id)

    def _parse_embed_html(self, html: str, video_id: str) -> tuple[str | None, list[str]]:
        """从 embed 页面的 __FRONTITY_CONNECT_STATE__ 中提取视频 URL。"""
        root = self._extract_json_by_script_id(html, "__FRONTITY_CONNECT_STATE__")
        if not isinstance(root, dict):
            return None, []

        source_data = root.get("source", {}).get("data", {})
        # embed 数据的 key 是 /embed/v2/{video_id}
        embed_data = source_data.get(f"/embed/v2/{video_id}", {})
        video_data = embed_data.get("videoData", {})
        item = video_data.get("itemInfos", {})

        title = item.get("text") or None
        video_obj = item.get("video", {})
        urls = video_obj.get("urls", [])

        candidates = [u for u in urls if isinstance(u, str) and u.startswith("http")]
        return title, candidates

    # ------------------------------------------------------------------
    # Step 3: 主页面解析（回退）
    # ------------------------------------------------------------------

    def _resolve_via_main_page(self, url: str) -> tuple[str | None, list[str]]:
        """回退方案：从主页面 HTML 解析视频地址。"""
        try:
            headers = self.default_http_headers(self._default_referer) | {
                "Accept-Language": "en-US,en;q=0.9,zh-CN;q=0.8",
            }
            resp = resolve_client.get(url, headers=headers)
            resp.raise_for_status()
            return self._parse_main_page_html(resp.text)
        except Exception as exc:
            logger.warning("Main page fetch failed for %s: %s", url, exc)
            return None, []

    def _parse_main_page_html(self, html: str) -> tuple[str | None, list[str]]:
        # 策略 1: __UNIVERSAL_DATA_FOR_REHYDRATION__ 精确提取
        title, candidates = self._parse_universal_data(html)
        if candidates:
            return title, candidates

        # 策略 2: SIGI_STATE
        title2, candidates2 = self._parse_sigi_state(html)
        if candidates2:
            return title2 or title, candidates2

        return title, []

    def _parse_universal_data(self, html: str) -> tuple[str | None, list[str]]:
        root = self._extract_json_by_script_id(html, "__UNIVERSAL_DATA_FOR_REHYDRATION__")
        if not isinstance(root, dict):
            return None, []

        scope = root.get("__DEFAULT_SCOPE__", {})
        video_detail = (
            scope.get("webapp.reflow.video.detail")
            or scope.get("webapp.video-detail")
            or {}
        )
        item_struct = (
            video_detail.get("itemInfo", {}).get("itemStruct")
            or video_detail.get("itemStruct")
            or {}
        )

        title = item_struct.get("desc") or item_struct.get("title") or None
        video_obj = item_struct.get("video", {})

        candidates: list[str] = []
        for key in ("downloadAddr", "playAddr"):
            val = video_obj.get(key)
            if isinstance(val, str) and val.startswith("http"):
                candidates.append(self._unescape_url(val))
            elif isinstance(val, list):
                for v in val:
                    if isinstance(v, str) and v.startswith("http"):
                        candidates.append(self._unescape_url(v))

        for br in video_obj.get("bitrateInfo", []):
            play_addr = br.get("PlayAddr", {})
            for u in play_addr.get("UrlList", []):
                if isinstance(u, str) and u.startswith("http"):
                    candidates.append(self._unescape_url(u))

        return title, list(dict.fromkeys(candidates))

    def _parse_sigi_state(self, html: str) -> tuple[str | None, list[str]]:
        root = self._extract_json_by_script_id(html, "SIGI_STATE")
        if root is None:
            root = self._extract_json_from_assignment(html)
        if not isinstance(root, dict):
            return None, []

        title: str | None = None
        candidates: list[str] = []

        def walk(node: object) -> None:
            nonlocal title
            if isinstance(node, dict):
                for k, v in node.items():
                    if k in ("desc", "title") and isinstance(v, str) and v.strip() and not title:
                        title = v.strip()
                    elif k in ("downloadAddr", "playAddr") and isinstance(v, str) and v.startswith("http"):
                        candidates.append(self._unescape_url(v))
                    else:
                        walk(v)
            elif isinstance(node, list):
                for item in node:
                    walk(item)

        walk(root)
        return title, list(dict.fromkeys(candidates))

    # ------------------------------------------------------------------
    # 工具方法
    # ------------------------------------------------------------------

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

    @staticmethod
    def _unescape_url(value: str) -> str:
        url = (
            value.replace("\\u002F", "/")
            .replace("\\u0026", "&")
            .replace("\\/", "/")
            .replace("&amp;", "&")
        )
        return html_lib.unescape(url)
