from __future__ import annotations

import html as html_lib
import json
import logging
import re
import time
from urllib.parse import urljoin, urlparse

import httpx

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
        r"https?://(?:www\.|m\.)?tiktok\.com/(?:@[\w.\-]+/(?:video|photo)/\d+|v/\d+|embed/v2/\d+)",
        re.I,
    )
    _generic_pattern = re.compile(r"https?://[^\s]+")
    _video_id_pattern = re.compile(r"/(?:video|v|photo|embed/v2)/(\d+)")

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

    def resolve(self, text: str, client_cookies: dict[str, str] | None = None) -> ResolvedVideo:
        url = self.extract_url(text)
        if not url:
            raise LocalResolveError("No TikTok URL found in input")

        # Step 1: 解析短链获取 video_id
        video_id = self._resolve_video_id(url)
        if not video_id:
            raise LocalResolveError("Could not extract TikTok video ID")

        # Step 2: 通过 embed 页面获取带有效 token 的视频/图片 URL
        title, candidates, image_urls = self._resolve_via_embed(video_id)
        if candidates or image_urls:
            logger.info("Successfully resolved via embed for %s", video_id)
        else:
            logger.info("Embed page failed for %s, trying main page", video_id)
            # Step 3: 若 embed 失败，回退到主页面解析
            title2, candidates, image_urls = self._resolve_via_main_page(url)
            title = title or title2
            if candidates or image_urls:
                logger.info("Successfully resolved via main page for %s", video_id)

        # AWS Lambda 的公网出口有时拿到的 TikTok 页面不含视频字段。
        # 这里仅作为演示兜底：官方页面解析失败后，再调用公开解析接口。
        if not candidates and not image_urls:
            logger.info("TikTok official pages failed, falling back to TikWM for %s", video_id)
            title3, candidates, image_urls = self._resolve_via_tikwm(url)
            title = title or title3
            if candidates or image_urls:
                logger.info("Successfully resolved via TikWM for %s", video_id)

        if not candidates and not image_urls:
            logger.error("All TikTok resolution methods failed for %s", video_id)
            raise LocalResolveError("No video/image link found in TikTok page")

        # 判断媒体类型
        # TikTok 的图集 (photo) 作品通常带有一个 mp4 格式的 BGM，
        # 如果图片数量较多，应优先识别为 image。
        if image_urls and len(image_urls) > 1:
            media_type = "image"
            best_url = image_urls[0]
        elif image_urls and not candidates:
            media_type = "image"
            best_url = image_urls[0]
        else:
            media_type = "video"
            best_url = candidates[0] if candidates else (image_urls[0] if image_urls else "")

        return ResolvedVideo(
            platform=self.platform,
            input_url=url,
            webpage_url=f"https://www.tiktok.com/embed/v2/{video_id}",
            title=title,
            video_id=video_id,
            best_url=best_url,
            candidates=candidates,
            media_type=media_type,
            image_urls=image_urls,
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
            # 使用独立 client 避免长连接 SSL 干扰
            with httpx.Client(timeout=10, follow_redirects=True) as client:
                headers = self.default_http_headers(self._default_referer)
                resp = client.get(url, headers=headers)
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

    def _resolve_via_embed(self, video_id: str) -> tuple[str | None, list[str], list[str]]:
        """通过 /embed/v2/{id} 获取视频/图片 URL。"""
        embed_url = f"https://www.tiktok.com/embed/v2/{video_id}"
        try:
            # 尝试多次不同的 UA
            headers_list = [
                {
                    "User-Agent": self._DESKTOP_UA,
                    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                    "Accept-Language": "en-US,en;q=0.9",
                },
                self.default_http_headers(self._default_referer)
            ]
            
            for headers in headers_list:
                resp = resolve_client.get(embed_url, headers=headers)
                if resp.status_code == 200:
                    title, candidates, image_urls = self._parse_embed_html(resp.text, video_id)
                    if candidates or image_urls:
                        return title, candidates, image_urls
                logger.debug("Embed fetch status %s for %s with UA %s", resp.status_code, video_id, headers.get("User-Agent"))
                
        except Exception as exc:
            logger.warning("Embed page fetch failed for %s: %s", video_id, exc)
            
        return None, [], []

    def _parse_embed_html(self, html: str, video_id: str) -> tuple[str | None, list[str], list[str]]:
        """从 embed 页面的 __FRONTITY_CONNECT_STATE__ 中提取视频或图片 URL。"""
        root = self._extract_json_by_script_id(html, "__FRONTITY_CONNECT_STATE__")
        if not isinstance(root, dict):
            return None, [], []

        source_data = root.get("source", {}).get("data", {})
        # embed 数据的 key 是 /embed/v2/{video_id}
        embed_key = f"/embed/v2/{video_id}"
        embed_data = source_data.get(embed_key)
        
        # 兜底：如果 key 不匹配，尝试找第一个含 videoData 或 imagePost 的
        if not embed_data:
            for k, v in source_data.items():
                if isinstance(v, dict) and ("videoData" in v or "imagePost" in v):
                    embed_data = v
                    break
        
        if not isinstance(embed_data, dict):
            return None, [], []
            
        video_data = embed_data.get("videoData", {})
        item = video_data.get("itemInfos", {})

        title = item.get("text") or None
        
        # 1. 尝试提取视频
        video_obj = item.get("video", {})
        urls = video_obj.get("urls", [])
        candidates = [u for u in urls if isinstance(u, str) and u.startswith("http")]
        
        # 2. 尝试提取图集 (Slideshow)
        image_urls: list[str] = []
        image_post = item.get("imagePost", {})
        if isinstance(image_post, dict):
            images = image_post.get("images", [])
            for img in images:
                # 尝试多种路径获取图片 URL
                img_obj = img.get("displayAddr") or img.get("imageURL") or img.get("imageAddr")
                if isinstance(img_obj, dict):
                    u = img_obj.get("urlList", [None])[0]
                    if u: image_urls.append(u)
                elif isinstance(img_obj, str) and img_obj.startswith("http"):
                    image_urls.append(img_obj)

        return title, candidates, image_urls

    # ------------------------------------------------------------------
    # Step 3: 主页面解析（回退）
    # ------------------------------------------------------------------

    def _resolve_via_main_page(self, url: str) -> tuple[str | None, list[str], list[str]]:
        """回退方案：从主页面 HTML 解析视频/图片地址。"""
        try:
            headers = self.default_http_headers(self._default_referer) | {
                "Accept-Language": "en-US,en;q=0.9,zh-CN;q=0.8",
            }
            resp = resolve_client.get(url, headers=headers)
            resp.raise_for_status()
            return self._parse_main_page_html(resp.text)
        except Exception as exc:
            logger.warning("Main page fetch failed for %s: %s", url, exc)
            return None, [], []

    def _parse_main_page_html(self, html: str) -> tuple[str | None, list[str], list[str]]:
        # 策略 1: __UNIVERSAL_DATA_FOR_REHYDRATION__ 精确提取
        title, candidates, image_urls = self._parse_universal_data(html)
        if candidates or image_urls:
            return title, candidates, image_urls

        # 策略 2: SIGI_STATE
        title2, candidates2, image_urls2 = self._parse_sigi_state(html)
        if candidates2 or image_urls2:
            return title2 or title, candidates2, image_urls2

        return title, [], []

    def _parse_universal_data(self, html: str) -> tuple[str | None, list[str], list[str]]:
        root = self._extract_json_by_script_id(html, "__UNIVERSAL_DATA_FOR_REHYDRATION__")
        if not isinstance(root, dict):
            return None, [], []

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
        
        # 1. 提取视频
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
                    
        # 2. 提取图集
        image_urls: list[str] = []
        image_post = item_struct.get("imagePost", {})
        if isinstance(image_post, dict):
            for img in image_post.get("images", []):
                u = (img.get("displayAddr") or img.get("imageAddr") or {}).get("urlList", [None])[0]
                if u: image_urls.append(u)

        return title, list(dict.fromkeys(candidates)), list(dict.fromkeys(image_urls))

    def _parse_sigi_state(self, html: str) -> tuple[str | None, list[str], list[str]]:
        root = self._extract_json_by_script_id(html, "SIGI_STATE")
        if root is None:
            root = self._extract_json_from_assignment(html)
        if not isinstance(root, dict):
            return None, [], []

        title: str | None = None
        candidates: list[str] = []
        image_urls: list[str] = []

        def walk(node: object) -> None:
            nonlocal title
            if isinstance(node, dict):
                # 检查是否为图文
                if "imagePost" in node and isinstance(node["imagePost"], dict):
                    for img in node["imagePost"].get("images", []):
                        u = (img.get("displayAddr") or img.get("imageAddr") or {}).get("urlList", [None])[0]
                        if u: image_urls.append(u)

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
        return title, list(dict.fromkeys(candidates)), list(dict.fromkeys(image_urls))

    # ------------------------------------------------------------------
    # Step 4: 第三方接口兜底（演示用）
    # ------------------------------------------------------------------

    def _resolve_via_tikwm(self, url: str) -> tuple[str | None, list[str], list[str]]:
        """使用独立 client 并解析视频和图片。"""
        try:
            with httpx.Client(timeout=15, follow_redirects=True) as client:
                resp = client.get(
                    "https://www.tikwm.com/api/",
                    params={"url": url},
                    headers={
                        "User-Agent": self._DESKTOP_UA,
                        "Accept": "application/json,text/plain,*/*",
                        "Referer": "https://www.tikwm.com/",
                    },
                )
                resp.raise_for_status()
                payload = resp.json()
        except Exception as exc:
            logger.warning("TikWM fallback failed for %s: %s", url, exc)
            return None, [], []

        return self._parse_tikwm_payload(payload)

    @staticmethod
    def _parse_tikwm_payload(payload: object) -> tuple[str | None, list[str], list[str]]:
        if not isinstance(payload, dict) or payload.get("code") != 0:
            return None, [], []

        data = payload.get("data")
        if not isinstance(data, dict):
            return None, [], []

        title = data.get("title") if isinstance(data.get("title"), str) else None
        candidates: list[str] = []
        image_urls: list[str] = []

        # 视频
        for key in ("play", "hdplay", "wmplay"):
            value = data.get(key)
            if not isinstance(value, str) or not value:
                continue
            if value.startswith("//"):
                value = "https:" + value
            elif value.startswith("/"):
                value = urljoin("https://www.tikwm.com", value)
            if value.startswith("http"):
                candidates.append(value)

        # 图片 (TikWM 返回 images 数组)
        images = data.get("images")
        if isinstance(images, list):
            for img in images:
                if isinstance(img, str) and img.startswith("http"):
                    image_urls.append(img)

        return title, list(dict.fromkeys(candidates)), list(dict.fromkeys(image_urls))

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
