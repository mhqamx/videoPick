from __future__ import annotations

import json
import re
import time
from urllib.parse import urlparse

import httpx

from .base import ResolvedVideo
from ..local_resolver import LocalResolveError


class BilibiliExtractor:
    platform = "bilibili"

    _short_pattern = re.compile(r"https?://b23\.tv/[a-zA-Z0-9]+/?", re.I)
    _long_pattern = re.compile(
        r"https?://(?:www\.|m\.)?bilibili\.com/video/(?:BV[0-9A-Za-z]+|av[0-9]+)",
        re.I,
    )

    _playinfo_pattern = re.compile(
        r"window\.__playinfo__\s*=\s*(\{.*?\})\s*(?:;|</script>)",
        re.S,
    )
    _initial_state_pattern = re.compile(
        r"window\.__INITIAL_STATE__\s*=\s*(\{.*?\})\s*(?:;|</script>)",
        re.S,
    )

    _source_host_keywords = ("bilivideo", "bilibili", "upos")

    def extract_url(self, text: str) -> str | None:
        for pattern in (self._short_pattern, self._long_pattern):
            match = pattern.search(text)
            if match:
                return match.group(0).strip().rstrip("。.,!;，！；")
        return None

    def can_handle_source(self, source_url: str) -> bool:
        try:
            host = (urlparse(source_url).hostname or "").lower()
        except Exception:
            return False
        return any(k in host for k in self._source_host_keywords)

    def resolve(self, text: str) -> ResolvedVideo:
        url = self.extract_url(text)
        if not url:
            raise LocalResolveError("No Bilibili URL found in input")

        try:
            with httpx.Client(timeout=20, follow_redirects=False) as client:
                webpage_url = self._resolve_canonical_webpage_url(client, url)
                html, webpage_url = self._fetch_html_with_retry(client, webpage_url)
        except LocalResolveError:
            raise
        except Exception as exc:
            raise LocalResolveError(f"Bilibili resolve failed: {exc}") from exc

        title = self._extract_title_from_initial_state(html)
        video_id = self._extract_video_id_from_url(webpage_url) or f"bili_unknown_{int(time.time())}"
        candidates = self._extract_progressive_candidates(html)

        if not candidates:
            raise LocalResolveError("Bilibili DASH-only stream is not supported yet")

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
        headers = self._http_headers(referer="https://www.bilibili.com/") | {
            "Accept": "*/*",
            "Range": "bytes=0-",
        }
        try:
            with httpx.Client(timeout=60, follow_redirects=True, headers=headers) as client:
                resp = client.get(source_url)
                if 200 <= resp.status_code < 300 and resp.content:
                    return resp.content, source_url
            raise LocalResolveError(
                f"Bilibili download failed: status={resp.status_code}"
            )
        except LocalResolveError:
            raise
        except Exception as exc:
            raise LocalResolveError(f"Bilibili download failed: {exc}") from exc

    @staticmethod
    def _http_headers(referer: str) -> dict[str, str]:
        return {
            "User-Agent": (
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/124.0.0.0 Safari/537.36"
            ),
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh-Hans;q=0.9",
            "Referer": referer,
            "Origin": "https://www.bilibili.com",
        }

    @staticmethod
    def _extract_video_id_from_url(url: str) -> str | None:
        match = re.search(r"/video/(BV[0-9A-Za-z]+|av[0-9]+)", url, re.I)
        return match.group(1) if match else None

    def _extract_progressive_candidates(self, html: str) -> list[str]:
        payload = self._extract_script_json(html, self._playinfo_pattern)
        if not isinstance(payload, dict):
            return []

        data = payload.get("data")
        if not isinstance(data, dict):
            return []

        candidates: list[str] = []
        durl = data.get("durl")
        if isinstance(durl, list):
            for item in durl:
                if not isinstance(item, dict):
                    continue
                url = item.get("url")
                if isinstance(url, str) and url.startswith("http"):
                    candidates.append(url)
                backups = item.get("backup_url") or item.get("backupUrl")
                if isinstance(backups, list):
                    for backup in backups:
                        if isinstance(backup, str) and backup.startswith("http"):
                            candidates.append(backup)

        return list(dict.fromkeys(candidates))

    def _extract_title_from_initial_state(self, html: str) -> str | None:
        payload = self._extract_script_json(html, self._initial_state_pattern)
        if not isinstance(payload, dict):
            return None

        video_data = payload.get("videoData")
        if isinstance(video_data, dict):
            title = video_data.get("title")
            if isinstance(title, str) and title.strip():
                return title.strip()

        for key in ("h1Title", "title"):
            value = payload.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()

        return None

    @staticmethod
    def _extract_script_json(html: str, pattern: re.Pattern[str]) -> dict | None:
        match = pattern.search(html)
        if not match:
            return None
        raw = match.group(1).replace("undefined", "null")
        try:
            decoded = json.loads(raw)
        except Exception:
            return None
        return decoded if isinstance(decoded, dict) else None

    def _resolve_canonical_webpage_url(self, client: httpx.Client, input_url: str) -> str:
        # b23 短链常携带 story/分享参数，先解析出 BV/av 后回到标准视频页，规避 412。
        if self._short_pattern.search(input_url):
            current = input_url
            for _ in range(6):
                resp = client.get(current, headers=self._http_headers(referer="https://www.bilibili.com/"))
                if 300 <= resp.status_code < 400 and resp.headers.get("Location"):
                    location = resp.headers["Location"]
                    current = str(httpx.URL(location, base=current))
                    video_id = self._extract_video_id_from_url(current)
                    if video_id:
                        return f"https://www.bilibili.com/video/{video_id}"
                    continue
                video_id = self._extract_video_id_from_url(str(resp.url))
                if video_id:
                    return f"https://www.bilibili.com/video/{video_id}"
                break
            raise LocalResolveError("Bilibili short URL redirect did not resolve to video page")

        video_id = self._extract_video_id_from_url(input_url)
        if video_id:
            return f"https://www.bilibili.com/video/{video_id}"
        return input_url

    def _fetch_html_with_retry(self, client: httpx.Client, webpage_url: str) -> tuple[str, str]:
        headers = self._http_headers(referer="https://www.bilibili.com/")
        resp = client.get(webpage_url, headers=headers, follow_redirects=True)
        if resp.status_code in (403, 412):
            # 二次尝试：避免被判定为不带浏览器上下文请求。
            alt_headers = headers | {
                "Upgrade-Insecure-Requests": "1",
                "Sec-Fetch-Dest": "document",
                "Sec-Fetch-Mode": "navigate",
                "Sec-Fetch-Site": "none",
            }
            resp = client.get(webpage_url, headers=alt_headers, follow_redirects=True)
        resp.raise_for_status()
        return resp.text, str(resp.url)
