from __future__ import annotations

import json
import re
import time

from .base import BaseExtractor, ResolvedVideo, resolve_client
from ..local_resolver import LocalResolveError


class XiaohongshuExtractor(BaseExtractor):
    platform = "xiaohongshu"
    _CDN_HOSTS = ("xhscdn.com", "xhscdn.net")
    _default_referer = "https://www.xiaohongshu.com/"

    # 短链：http://xhslink.com/o/2z7YRSHBEWZ 或 http://xhslink.com/AbCd1234
    _short_pattern = re.compile(
        r"https?://xhslink\.com/(?:o/)?[a-zA-Z0-9_\-]+/?", re.I
    )
    # 长链：https://www.xiaohongshu.com/explore/<noteId>
    _long_pattern = re.compile(
        r"https?://(?:www\.)?xiaohongshu\.com/(?:explore|discovery/item)/[a-zA-Z0-9_\-]+",
        re.I,
    )

    def extract_url(self, text: str) -> str | None:
        for pattern in (self._short_pattern, self._long_pattern):
            match = pattern.search(text)
            if match:
                return match.group(0).strip().rstrip("。.,!;，！；")
        return None

    def resolve(self, text: str, client_cookies: dict[str, str] | None = None) -> ResolvedVideo:
        url = self.extract_url(text)
        if not url:
            raise LocalResolveError("No XiaoHongShu URL found in input")

        try:
            headers = self.default_http_headers(self._default_referer)
            resp = resolve_client.get(url, headers=headers)
            resp.raise_for_status()
            html = resp.text
            webpage_url = str(resp.url)
        except LocalResolveError:
            raise
        except Exception as exc:
            raise LocalResolveError(f"XiaoHongShu resolve failed: {exc}") from exc

        note_id = self._extract_note_id_from_url(webpage_url)
        title, candidates, media_type, image_urls = self._parse_html(html)

        note_id = note_id or f"xhs_unknown_{int(time.time())}"

        if media_type == "image" and image_urls:
            return ResolvedVideo(
                platform=self.platform,
                input_url=url,
                webpage_url=webpage_url,
                title=title,
                video_id=note_id,
                best_url=image_urls[0],
                candidates=[],
                media_type="image",
                image_urls=image_urls,
            )

        if not candidates:
            raise LocalResolveError("No video link found in XiaoHongShu page")

        return ResolvedVideo(
            platform=self.platform,
            input_url=url,
            webpage_url=webpage_url,
            title=title,
            video_id=note_id,
            best_url=candidates[0],
            candidates=candidates,
        )

    # ------------------------------------------------------------------
    # 内部方法
    # ------------------------------------------------------------------

    @staticmethod
    def _extract_note_id_from_url(url: str) -> str | None:
        m = re.search(r"/(?:explore|discovery/item)/([a-zA-Z0-9_\-]+)", url)
        return m.group(1) if m else None

    def _parse_html(self, html: str) -> tuple[str | None, list[str], str, list[str]]:
        """解析小红书 HTML 页面，返回 (title, video_candidates, media_type, image_urls)。"""
        # 策略 1: window.__INITIAL_STATE__
        title, candidates, media_type, image_urls = self._parse_initial_state(html)
        if candidates or image_urls:
            return title, candidates, media_type, image_urls

        # 策略 2: 原始 HTML 正则匹配 CDN URL
        candidates2 = self._parse_raw_html(html)
        return None, candidates2, "video", []

    def _parse_initial_state(self, html: str) -> tuple[str | None, list[str], str, list[str]]:
        """返回 (title, video_candidates, media_type, image_urls)。"""
        m = re.search(
            r"window\.__INITIAL_STATE__\s*=\s*(\{.*?\})\s*(?:;|</script>)",
            html,
            re.S,
        )
        if not m:
            return None, [], "video", []

        try:
            raw = m.group(1).replace("undefined", "null")
            root = json.loads(raw)
        except Exception:
            return None, [], "video", []

        # 收集所有 note 对象（可能来自不同路径）
        notes: list[dict] = []

        # 路径 1: root.noteData.data.noteData（移动端分享页）
        nd = (root.get("noteData") or {}).get("data") or {}
        note_data = nd.get("noteData")
        if isinstance(note_data, dict):
            notes.append(note_data)

        # 路径 2: root.note.noteDetailMap.<id>.note（Web 端）
        note_detail_map = (root.get("note") or {}).get("noteDetailMap") or {}
        for entry in note_detail_map.values():
            if isinstance(entry, dict):
                inner = entry.get("note")
                if isinstance(inner, dict):
                    notes.append(inner)

        title: str | None = None
        candidates: list[str] = []
        image_urls: list[str] = []

        for note in notes:
            note_type = note.get("type")
            if not title:
                title = note.get("title") or note.get("desc")

            # 图文笔记: type == "normal"
            if note_type == "normal":
                image_list = note.get("imageList") or []
                for img in image_list:
                    if not isinstance(img, dict):
                        continue
                    # 优先使用 infoList 中 H5_DTL 场景的高清图
                    img_url = None
                    info_list = img.get("infoList") or []
                    for info in info_list:
                        if isinstance(info, dict) and info.get("imageScene") == "H5_DTL":
                            img_url = info.get("url")
                            break
                    # 回退到顶层 url
                    if not img_url:
                        img_url = img.get("url")
                    if isinstance(img_url, str) and img_url:
                        # 确保 https
                        if img_url.startswith("http://"):
                            img_url = "https://" + img_url[7:]
                        image_urls.append(img_url)
                if image_urls:
                    return title, [], "image", list(dict.fromkeys(image_urls))

            # 视频笔记: type == "video"
            if note_type == "video":
                video = note.get("video") or {}
                stream = (video.get("media") or {}).get("stream") or {}

                # 按编码优先级: h264 → h265 → av1
                for codec in ("h264", "h265", "av1"):
                    for item in stream.get(codec) or []:
                        url = item.get("masterUrl") if isinstance(item, dict) else None
                        if isinstance(url, str) and url.startswith("http"):
                            candidates.append(url)

        return title, list(dict.fromkeys(candidates)), "video", []

    @staticmethod
    def _parse_raw_html(html: str) -> list[str]:
        patterns = [
            r'(https?:\\/\\/[^"\']+xhscdn\.(?:com|net)[^"\']*\.mp4[^"\']*)',
            r'(https?://[^"\']+xhscdn\.(?:com|net)[^"\']*\.mp4[^"\']*)',
            r'(https?:\\/\\/[^"\']+xhscdn\.(?:com|net)[^"\']*)',
            r'(https?://[^"\']+xhscdn\.(?:com|net)[^"\']*)',
        ]
        candidates: list[str] = []
        for p in patterns:
            for m in re.finditer(p, html, re.I):
                url = m.group(1).replace("\\/", "/")
                # 过滤非视频资源（图片缩略图等）
                if any(sig in url for sig in ("/stream/", "/video/", "masterUrl", ".mp4")):
                    candidates.append(url)
        return list(dict.fromkeys(candidates))
