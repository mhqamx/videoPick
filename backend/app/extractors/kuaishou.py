from __future__ import annotations

import json
import re
import time

from .base import BaseExtractor, ResolvedVideo, resolve_client
from ..local_resolver import LocalResolveError


class KuaishouExtractor(BaseExtractor):
    platform = "kuaishou"
    _CDN_HOSTS = ("kwimgs.com", "kwai.net", "kuaishou.com", "yximgs.com")
    _default_referer = "https://www.kuaishou.com/"

    _short_pattern = re.compile(r"https?://v\.kuaishou\.com/[a-zA-Z0-9_\-]+/?", re.I)
    _long_pattern = re.compile(
        r"https?://(?:www\.|m\.)?kuaishou\.com/(?:short-video|video)/[a-zA-Z0-9_\-]+",
        re.I,
    )
    _ATLAS_PHOTO_TYPES = {"VERTICAL_ATLAS", "HORIZONTAL_ATLAS", "MULTI_IMAGE"}

    def extract_url(self, text: str) -> str | None:
        for pattern in (self._short_pattern, self._long_pattern):
            match = pattern.search(text)
            if match:
                return match.group(0).strip().rstrip("。.,!;，！；")
        return None

    def resolve(self, text: str) -> ResolvedVideo:
        url = self.extract_url(text)
        if not url:
            raise LocalResolveError("No Kuaishou URL found in input")

        try:
            headers = self.default_http_headers(self._default_referer)
            resp = resolve_client.get(url, headers=headers)
            resp.raise_for_status()
            html = resp.text
            webpage_url = str(resp.url)
        except LocalResolveError:
            raise
        except Exception as exc:
            raise LocalResolveError(f"Kuaishou resolve failed: {exc}") from exc

        video_id = self._extract_video_id_from_url(webpage_url)
        photo_id = self._extract_photo_id_from_url(webpage_url)

        # 尝试通过 API 获取图文数据
        if photo_id:
            result = self._resolve_via_api(photo_id)
            if result is not None:
                title, media_type, image_urls, candidates = result
                vid = video_id or photo_id or f"ks_unknown_{int(time.time())}"
                if media_type == "image" and image_urls:
                    return ResolvedVideo(
                        platform=self.platform,
                        input_url=url,
                        webpage_url=webpage_url,
                        title=title,
                        video_id=vid,
                        best_url=image_urls[0],
                        candidates=[],
                        media_type="image",
                        image_urls=image_urls,
                    )
                if candidates:
                    return ResolvedVideo(
                        platform=self.platform,
                        input_url=url,
                        webpage_url=webpage_url,
                        title=title,
                        video_id=vid,
                        best_url=candidates[0],
                        candidates=candidates,
                    )

        # 回退到 HTML 解析
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

    # ------------------------------------------------------------------
    # 内部方法
    # ------------------------------------------------------------------

    @staticmethod
    def _extract_video_id_from_url(url: str) -> str | None:
        m = re.search(r"/(?:short-video|video)/([a-zA-Z0-9_\-]+)", url)
        return m.group(1) if m else None

    @staticmethod
    def _extract_photo_id_from_url(url: str) -> str | None:
        """从重定向后的 URL 提取 photoId（如 /fw/photo/{id} 或查询参数）。"""
        m = re.search(r"/(?:fw/)?photo/([a-zA-Z0-9_\-]+)", url)
        if m:
            return m.group(1)
        m = re.search(r"photoId=([a-zA-Z0-9_\-]+)", url)
        return m.group(1) if m else None

    def _resolve_via_api(
        self, photo_id: str
    ) -> tuple[str | None, str, list[str], list[str]] | None:
        """调用快手 API 获取图文/视频数据。

        返回 (title, media_type, image_urls, video_candidates) 或 None。
        """
        api_url = "https://v.m.chenzhongtech.com/rest/wd/ugH5App/photo/simple/info"
        headers = self.default_http_headers(self._default_referer) | {
            "Content-Type": "application/json",
        }
        try:
            resp = resolve_client.post(
                api_url, json={"photoId": photo_id, "kpn": "KUAISHOU"}, headers=headers
            )
            if resp.status_code != 200:
                return None
            data = resp.json()
            if data.get("result") != 1:
                return None
        except Exception:
            return None

        photo = data.get("photo") or {}
        title = photo.get("caption")
        photo_type = photo.get("photoType", "")

        # 图文作品：从 atlas 提取图片 URL
        atlas = data.get("atlas") or {}
        cdn_list = atlas.get("cdnList") or []
        img_list = atlas.get("list") or []

        if photo_type in self._ATLAS_PHOTO_TYPES and cdn_list and img_list:
            cdn = cdn_list[0].get("cdn", "")
            image_urls = [f"https://{cdn}{path}" for path in img_list if path]
            if image_urls:
                return title, "image", image_urls, []

        # 视频作品：从 mainMvUrls 提取
        main_mv_urls = photo.get("mainMvUrls") or []
        video_candidates = []
        for item in main_mv_urls:
            url = item.get("url") if isinstance(item, dict) else None
            if isinstance(url, str) and url.startswith("http"):
                video_candidates.append(url)

        if video_candidates:
            return title, "video", [], video_candidates

        return None

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
