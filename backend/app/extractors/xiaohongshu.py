from __future__ import annotations

import json
import re
import time

import httpx

from .base import ResolvedVideo
from ..local_resolver import LocalResolveError


class XiaohongshuExtractor:
    platform = "xiaohongshu"

    # 短链：http://xhslink.com/o/2z7YRSHBEWZ 或 http://xhslink.com/AbCd1234
    _short_pattern = re.compile(
        r"https?://xhslink\.com/(?:o/)?[a-zA-Z0-9_\-]+/?", re.I
    )
    # 长链：https://www.xiaohongshu.com/explore/<noteId>
    _long_pattern = re.compile(
        r"https?://(?:www\.)?xiaohongshu\.com/(?:explore|discovery/item)/[a-zA-Z0-9_\-]+",
        re.I,
    )

    # 小红书 CDN 主机名片段
    _CDN_HOSTS = ("xhscdn.com", "xhscdn.net")

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
            raise LocalResolveError("No XiaoHongShu URL found in input")

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
            raise LocalResolveError(f"XiaoHongShu resolve failed: {exc}") from exc

        note_id = self._extract_note_id_from_url(webpage_url)
        title, candidates = self._parse_html(html)

        if not candidates:
            raise LocalResolveError("No video link found in XiaoHongShu page")

        note_id = note_id or f"xhs_unknown_{int(time.time())}"

        return ResolvedVideo(
            platform=self.platform,
            input_url=url,
            webpage_url=webpage_url,
            title=title,
            video_id=note_id,
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
                f"XiaoHongShu download failed: status={resp.status_code}"
            )
        except LocalResolveError:
            raise
        except Exception as exc:
            raise LocalResolveError(f"XiaoHongShu download failed: {exc}") from exc

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
            "Referer": "https://www.xiaohongshu.com/",
        }

    @staticmethod
    def _extract_note_id_from_url(url: str) -> str | None:
        m = re.search(r"/(?:explore|discovery/item)/([a-zA-Z0-9_\-]+)", url)
        return m.group(1) if m else None

    def _parse_html(self, html: str) -> tuple[str | None, list[str]]:
        """二级回退解析小红书 HTML 页面，返回 (title, candidate_urls)。"""
        # 策略 1: window.__INITIAL_STATE__
        title, candidates = self._parse_initial_state(html)
        if candidates:
            return title, candidates

        # 策略 2: 原始 HTML 正则匹配 CDN URL
        candidates2 = self._parse_raw_html(html)
        return None, candidates2

    def _parse_initial_state(self, html: str) -> tuple[str | None, list[str]]:
        m = re.search(
            r"window\.__INITIAL_STATE__\s*=\s*(\{.*?\})\s*(?:;|</script>)",
            html,
            re.S,
        )
        if not m:
            return None, []

        try:
            raw = m.group(1).replace("undefined", "null")
            root = json.loads(raw)
        except Exception:
            return None, []

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

        for note in notes:
            if note.get("type") != "video":
                continue

            if not title:
                title = note.get("title") or note.get("desc")

            video = note.get("video") or {}
            stream = (video.get("media") or {}).get("stream") or {}

            # 按编码优先级: h264 → h265 → av1
            for codec in ("h264", "h265", "av1"):
                for item in stream.get(codec) or []:
                    url = item.get("masterUrl") if isinstance(item, dict) else None
                    if isinstance(url, str) and url.startswith("http"):
                        candidates.append(url)

        return title, list(dict.fromkeys(candidates))

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
