from __future__ import annotations

import html as html_lib
import json
import os
import re
import time
from pathlib import Path
from urllib.parse import parse_qsl, urlencode, urlparse, urlunparse

from .base import BaseExtractor, ResolvedVideo, download_client, resolve_client
from ..local_resolver import LocalResolveError


class InstagramExtractor(BaseExtractor):
    platform = "instagram"
    _CDN_HOSTS = (
        "cdninstagram.com",
        "fbcdn.net",
        "instagram.com",
    )
    _default_referer = "https://www.instagram.com/"

    _short_pattern = re.compile(r"https?://(?:www\.)?instagram\.com/reel/[A-Za-z0-9_-]+/?(?:\?[^\s]*)?", re.I)
    _post_pattern = re.compile(r"https?://(?:www\.)?instagram\.com/p/[A-Za-z0-9_-]+/?(?:\?[^\s]*)?", re.I)
    _tv_pattern = re.compile(r"https?://(?:www\.)?instagram\.com/tv/[A-Za-z0-9_-]+/?(?:\?[^\s]*)?", re.I)
    _generic_pattern = re.compile(r"https?://[^\s]+")
    _shortcode_pattern = re.compile(r"/(?:reel|p|tv)/([A-Za-z0-9_-]+)", re.I)

    _desktop_ua = (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    )

    def extract_url(self, text: str) -> str | None:
        for pattern in (self._short_pattern, self._post_pattern, self._tv_pattern):
            match = pattern.search(text)
            if match:
                return match.group(0).strip().rstrip("。.,!;，！；")

        match = self._generic_pattern.search(text)
        if match:
            candidate = match.group(0).strip().rstrip("。.,!;，！；")
            if "instagram.com" in candidate.lower():
                return candidate
        return None

    def can_handle_source(self, source_url: str) -> bool:
        try:
            host = (urlparse(source_url).hostname or "").lower()
        except Exception:
            return False
        return any(host == d or host.endswith("." + d) for d in self._CDN_HOSTS)

    def resolve(self, text: str) -> ResolvedVideo:
        url = self.extract_url(text)
        if not url:
            raise LocalResolveError("No Instagram URL found in input")

        cookie_jar = self._load_instagram_cookies()
        normalized_url = self._normalize_input_url(url)
        title = None
        candidates: list[str] = []
        webpage_url = normalized_url
        video_id: str | None = None

        # 优先走 cookie API 链路：oembed -> media info
        api_title, api_video_id, api_candidates, api_webpage_url = self._resolve_via_private_api(
            normalized_url,
            cookie_jar,
        )
        if api_candidates:
            title = api_title
            candidates = api_candidates
            video_id = api_video_id
            if api_webpage_url:
                webpage_url = api_webpage_url

        if not candidates:
            headers = self._build_headers(normalized_url)
            try:
                resp = resolve_client.get(normalized_url, headers=headers, cookies=cookie_jar)
                resp.raise_for_status()
                webpage_url = str(resp.url)
            except Exception as exc:
                raise LocalResolveError(f"Instagram resolve failed: {exc}") from exc

            json_title, json_candidates = self._resolve_via_json(webpage_url, cookie_jar)
            title = title or json_title
            candidates = json_candidates

            if not candidates:
                html_title, html_candidates = self._parse_html(resp.text)
                title = title or html_title
                candidates = html_candidates

        if not candidates:
            raise LocalResolveError("No video link found in Instagram page (cookie may be expired)")

        shortcode = self._extract_shortcode_from_url(webpage_url) or self._extract_shortcode_from_url(normalized_url)
        video_id = video_id or shortcode or f"ig_unknown_{int(time.time())}"
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
        cookies = self._load_instagram_cookies(allow_missing=True)
        headers = self._build_headers(self._default_referer) | {
            "Accept": "*/*",
            "Range": "bytes=0-",
        }
        try:
            resp = download_client.get(
                source_url,
                headers=headers,
                cookies=cookies if cookies else None,
            )
            if 200 <= resp.status_code < 300 and resp.content:
                return resp.content, source_url
            raise LocalResolveError(f"Instagram download failed: status={resp.status_code}")
        except LocalResolveError:
            raise
        except Exception as exc:
            raise LocalResolveError(f"Instagram download failed: {exc}") from exc

    # ------------------------------------------------------------------
    # Cookie 处理
    # ------------------------------------------------------------------

    def _load_instagram_cookies(self, allow_missing: bool = False) -> dict[str, str]:
        cookie_path = self._resolve_cookie_file()
        if not cookie_path:
            if allow_missing:
                return {}
            raise LocalResolveError(
                "Instagram cookie file not found. "
                "Set INSTAGRAM_COOKIE_FILE or place cookies at ~/Downloads/www.instagram.com_cookies.txt"
            )

        cookies = self._parse_cookie_file(cookie_path)
        if not cookies and not allow_missing:
            raise LocalResolveError(f"Instagram cookie file is empty: {cookie_path}")
        if not allow_missing and "sessionid" not in cookies:
            raise LocalResolveError(
                f"Instagram cookie file missing sessionid: {cookie_path}"
            )
        return cookies

    @staticmethod
    def _resolve_cookie_file() -> Path | None:
        env_path = os.getenv("INSTAGRAM_COOKIE_FILE")
        candidates = [env_path, str(Path.home() / "Downloads" / "www.instagram.com_cookies.txt")]
        for raw in candidates:
            if not raw:
                continue
            path = Path(raw).expanduser()
            if path.is_file():
                return path
        return None

    @staticmethod
    def _parse_cookie_file(path: Path) -> dict[str, str]:
        text = path.read_text(encoding="utf-8", errors="ignore")
        cookies: dict[str, str] = {}

        for raw_line in text.splitlines():
            line = raw_line.strip()
            if not line:
                continue
            if line.startswith("#") and not line.startswith("#HttpOnly_"):
                continue
            if line.startswith("#HttpOnly_"):
                line = line[len("#HttpOnly_"):]

            if "\t" in line:
                parts = line.split("\t")
                if len(parts) >= 7:
                    domain = parts[0].strip().lower()
                    name = parts[5].strip()
                    value = parts[6].strip()
                    if "instagram.com" in domain and name and value:
                        cookies[name] = value
                continue

            if "=" in line:
                for chunk in line.split(";"):
                    key, sep, val = chunk.strip().partition("=")
                    if not sep or not key or not val:
                        continue
                    if key.lower() in {"domain", "path", "expires", "max-age", "secure", "httponly", "samesite"}:
                        continue
                    cookies[key.strip()] = val.strip()

        return cookies

    # ------------------------------------------------------------------
    # 页面/JSON 解析
    # ------------------------------------------------------------------

    def _resolve_via_private_api(
        self,
        normalized_url: str,
        cookies: dict[str, str],
    ) -> tuple[str | None, str | None, list[str], str | None]:
        headers = self._build_headers(normalized_url) | {
            "Accept": "application/json, text/plain, */*",
            "X-IG-App-ID": "936619743392459",
            "X-Requested-With": "XMLHttpRequest",
        }

        try:
            oembed_resp = resolve_client.get(
                "https://www.instagram.com/api/v1/oembed/",
                params={"url": normalized_url},
                headers=headers,
                cookies=cookies,
            )
            oembed_resp.raise_for_status()
            oembed_payload = oembed_resp.json()
        except Exception:
            return None, None, [], None

        media_id = oembed_payload.get("media_id")
        fallback_title = oembed_payload.get("title") if isinstance(oembed_payload.get("title"), str) else None
        if not isinstance(media_id, str) or not media_id:
            return fallback_title, None, [], None

        try:
            info_resp = resolve_client.get(
                f"https://www.instagram.com/api/v1/media/{media_id}/info/",
                headers=headers,
                cookies=cookies,
            )
            info_resp.raise_for_status()
            info_payload = info_resp.json()
        except Exception:
            return fallback_title, media_id, [], None

        title, video_id, candidates, webpage_url = self._extract_from_media_info_payload(
            info_payload,
            fallback_title=fallback_title,
        )
        return title, video_id or media_id, candidates, webpage_url

    def _extract_from_media_info_payload(
        self,
        payload: object,
        fallback_title: str | None = None,
    ) -> tuple[str | None, str | None, list[str], str | None]:
        if not isinstance(payload, dict):
            return fallback_title, None, [], None
        items = payload.get("items")
        if not isinstance(items, list) or not items:
            return fallback_title, None, [], None
        item = items[0] if isinstance(items[0], dict) else None
        if not isinstance(item, dict):
            return fallback_title, None, [], None

        video_id_obj = item.get("id") or item.get("pk")
        video_id = str(video_id_obj) if video_id_obj is not None else None

        code = item.get("code")
        webpage_url = f"https://www.instagram.com/reel/{code}/" if isinstance(code, str) and code else None

        title = fallback_title
        caption = item.get("caption")
        if isinstance(caption, dict):
            caption_text = caption.get("text")
            if isinstance(caption_text, str) and caption_text.strip():
                title = caption_text.strip()

        candidates: list[str] = []
        candidates.extend(self._extract_urls_from_video_versions(item.get("video_versions")))

        carousel = item.get("carousel_media")
        if isinstance(carousel, list):
            for media_item in carousel:
                if isinstance(media_item, dict):
                    candidates.extend(
                        self._extract_urls_from_video_versions(media_item.get("video_versions"))
                    )

        return title, video_id, list(dict.fromkeys(candidates)), webpage_url

    def _extract_urls_from_video_versions(self, video_versions: object) -> list[str]:
        if not isinstance(video_versions, list):
            return []
        candidates: list[str] = []
        for item in video_versions:
            if not isinstance(item, dict):
                continue
            url = item.get("url")
            if isinstance(url, str):
                normalized = self._normalize_candidate(url)
                if normalized:
                    candidates.append(normalized)
        return candidates

    def _resolve_via_json(self, webpage_url: str, cookies: dict[str, str]) -> tuple[str | None, list[str]]:
        api_url = self._append_query(webpage_url, {"__a": "1", "__d": "dis"})
        headers = self._build_headers(webpage_url) | {
            "Accept": "application/json, text/plain, */*",
            "X-IG-App-ID": "936619743392459",
            "X-Requested-With": "XMLHttpRequest",
        }
        try:
            resp = resolve_client.get(api_url, headers=headers, cookies=cookies)
            resp.raise_for_status()
            payload = resp.json()
        except Exception:
            return None, []
        return self._collect_from_json(payload)

    def _parse_html(self, html: str) -> tuple[str | None, list[str]]:
        title, candidates = self._parse_ld_json(html)
        if candidates:
            return title, candidates

        # 兜底：直接从 HTML 文本提取 video_url / mp4 链接
        pattern_list = [
            r'"video_url":"(https:[^"]+)"',
            r'"contentUrl":"(https:[^"]+)"',
            r'"url":"(https:[^"]+\.mp4[^"]*)"',
            r'"video_versions":\[(.*?)\]',
        ]

        extracted: list[str] = []
        for pattern in pattern_list:
            for m in re.finditer(pattern, html, re.I | re.S):
                if "video_versions" in pattern:
                    block = m.group(1)
                    for um in re.finditer(r'"url":"(https:[^"]+)"', block, re.I):
                        normalized = self._normalize_candidate(um.group(1))
                        if normalized:
                            extracted.append(normalized)
                else:
                    normalized = self._normalize_candidate(m.group(1))
                    if normalized:
                        extracted.append(normalized)

        title = title or self._extract_og_title(html)
        return title, list(dict.fromkeys(extracted))

    def _parse_ld_json(self, html: str) -> tuple[str | None, list[str]]:
        title: str | None = None
        candidates: list[str] = []

        for m in re.finditer(
            r'<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>',
            html,
            re.S | re.I,
        ):
            raw = m.group(1).strip()
            if not raw:
                continue
            try:
                payload = json.loads(raw)
            except Exception:
                continue

            inner_title, inner_candidates = self._collect_from_json(payload)
            if not title:
                title = inner_title
            candidates.extend(inner_candidates)

        return title, list(dict.fromkeys(candidates))

    def _collect_from_json(self, payload: object) -> tuple[str | None, list[str]]:
        title: str | None = None
        candidates: list[str] = []

        def walk(node: object) -> None:
            nonlocal title
            if isinstance(node, dict):
                for key, value in node.items():
                    if key in {"title", "caption", "name", "description"} and isinstance(value, str):
                        stripped = value.strip()
                        if stripped and not title:
                            title = stripped
                    elif key in {"video_url", "videoUrl", "contentUrl", "url", "src"} and isinstance(value, str):
                        normalized = self._normalize_candidate(value)
                        if normalized:
                            candidates.append(normalized)
                    else:
                        walk(value)
            elif isinstance(node, list):
                for item in node:
                    walk(item)

        walk(payload)
        return title, list(dict.fromkeys(candidates))

    # ------------------------------------------------------------------
    # 工具方法
    # ------------------------------------------------------------------

    def _build_headers(self, referer: str) -> dict[str, str]:
        return {
            "User-Agent": self._desktop_ua,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9,zh-CN;q=0.8",
            "Referer": referer,
            "Origin": "https://www.instagram.com",
        }

    @staticmethod
    def _normalize_input_url(raw_url: str) -> str:
        parsed = urlparse(raw_url)
        return urlunparse((parsed.scheme, parsed.netloc, parsed.path, "", "", ""))

    def _normalize_candidate(self, value: str) -> str | None:
        url = value.strip()
        if not url.startswith("http"):
            return None

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

        if any(host == d or host.endswith("." + d) for d in self._CDN_HOSTS):
            if ".mp4" in url.lower() or "bytestart" in url.lower() or "video" in url.lower():
                return url
        return None

    @staticmethod
    def _extract_shortcode_from_url(url: str) -> str | None:
        m = re.search(r"/(?:reel|p|tv)/([A-Za-z0-9_-]+)", url, re.I)
        return m.group(1) if m else None

    @staticmethod
    def _append_query(url: str, extra: dict[str, str]) -> str:
        parsed = urlparse(url)
        q = dict(parse_qsl(parsed.query, keep_blank_values=True))
        q.update(extra)
        return urlunparse((parsed.scheme, parsed.netloc, parsed.path, "", urlencode(q), ""))

    @staticmethod
    def _extract_og_title(html: str) -> str | None:
        m = re.search(
            r'<meta[^>]+property="og:title"[^>]+content="([^"]+)"',
            html,
            re.I,
        )
        if not m:
            return None
        return html_lib.unescape(m.group(1)).strip() or None
