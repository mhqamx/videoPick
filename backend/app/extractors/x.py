from __future__ import annotations

import json
import os
import re
import time
from pathlib import Path
from urllib.parse import urlparse

from .base import BaseExtractor, ResolvedVideo, download_client, resolve_client
from ..local_resolver import LocalResolveError


class XExtractor(BaseExtractor):
    platform = "x"
    _CDN_HOSTS = (
        "video.twimg.com",
        "pbs.twimg.com",
        "twimg.com",
        "x.com",
        "twitter.com",
    )
    _default_referer = "https://x.com/"

    _x_pattern = re.compile(r"https?://(?:www\.)?x\.com/[A-Za-z0-9_]+/status/(\d+)(?:\?[^\s]*)?", re.I)
    _twitter_pattern = re.compile(r"https?://(?:www\.)?twitter\.com/[A-Za-z0-9_]+/status/(\d+)(?:\?[^\s]*)?", re.I)
    _generic_pattern = re.compile(r"https?://[^\s]+")
    _main_js_pattern = re.compile(r"https://abs\.twimg\.com/responsive-web/client-web/main\.[^\"']+\.js", re.I)
    _metadata_cache: tuple[str, str, float] | None = None

    def extract_url(self, text: str) -> str | None:
        for pattern in (self._x_pattern, self._twitter_pattern):
            match = pattern.search(text)
            if match:
                return match.group(0).strip().rstrip("。.,!;，！；")

        match = self._generic_pattern.search(text)
        if match:
            candidate = match.group(0).strip().rstrip("。.,!;，！；")
            lowered = candidate.lower()
            if "x.com/" in lowered or "twitter.com/" in lowered:
                return candidate
        return None

    def can_handle_source(self, source_url: str) -> bool:
        try:
            host = (urlparse(source_url).hostname or "").lower()
        except Exception:
            return False
        return any(host == d or host.endswith("." + d) for d in self._CDN_HOSTS)

    def resolve(self, text: str, client_cookies: dict[str, str] | None = None) -> ResolvedVideo:
        url = self.extract_url(text)
        if not url:
            raise LocalResolveError("No X/Twitter URL found in input")

        tweet_id = self._extract_tweet_id(url)
        if not tweet_id:
            raise LocalResolveError("Could not extract tweet ID from URL")

        cookies = client_cookies if client_cookies else self._load_x_cookies()
        query_id, bearer_token = self._load_graphql_metadata(tweet_id=tweet_id)
        title, candidates, image_urls = self._resolve_video_variants(
            tweet_id=tweet_id,
            query_id=query_id,
            bearer_token=bearer_token,
            cookies=cookies,
        )

        # 视频推文
        if candidates:
            return ResolvedVideo(
                platform=self.platform,
                input_url=url,
                webpage_url=f"https://x.com/i/status/{tweet_id}",
                title=title,
                video_id=tweet_id,
                best_url=candidates[0],
                candidates=candidates,
            )

        # 图片推文
        if image_urls:
            return ResolvedVideo(
                platform=self.platform,
                input_url=url,
                webpage_url=f"https://x.com/i/status/{tweet_id}",
                title=title,
                video_id=tweet_id,
                best_url=image_urls[0],
                candidates=[],
                media_type="image",
                image_urls=image_urls,
            )

        raise LocalResolveError("No media found in X tweet")

    def download_bytes(self, source_url: str) -> tuple[bytes, str]:
        cookies = self._load_x_cookies(allow_missing=True)
        headers = {
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            "Accept": "*/*",
            "Accept-Language": "en-US,en;q=0.9",
            "Referer": "https://x.com/",
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
            raise LocalResolveError(f"X download failed: status={resp.status_code}")
        except LocalResolveError:
            raise
        except Exception as exc:
            raise LocalResolveError(f"X download failed: {exc}") from exc

    # ------------------------------------------------------------------
    # Cookie
    # ------------------------------------------------------------------

    def _load_x_cookies(self, allow_missing: bool = False) -> dict[str, str]:
        cookie_path = self._resolve_cookie_file()
        if not cookie_path:
            if allow_missing:
                return {}
            raise LocalResolveError(
                "X cookie file not found. "
                "Set X_COOKIE_FILE or place cookies at backend/cookies/x.com_cookies.txt"
            )

        cookies = self._parse_cookie_file(cookie_path)
        if not cookies and not allow_missing:
            raise LocalResolveError(f"X cookie file is empty: {cookie_path}")
        if not allow_missing and "auth_token" not in cookies:
            raise LocalResolveError(f"X cookie file missing auth_token: {cookie_path}")
        if not allow_missing and "ct0" not in cookies:
            raise LocalResolveError(f"X cookie file missing ct0: {cookie_path}")
        return cookies

    @staticmethod
    def _resolve_cookie_file() -> Path | None:
        env_path = os.getenv("X_COOKIE_FILE")
        backend_root = Path(__file__).resolve().parents[2]
        candidates = [
            env_path,
            str(backend_root / "cookies" / "x.com_cookies.txt"),
            str(backend_root / "x.com_cookies.txt"),
            str(Path.home() / "Downloads" / "x.com_cookies.txt"),
        ]
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
                    if ("x.com" in domain or "twitter.com" in domain) and name and value:
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
    # GraphQL resolve
    # ------------------------------------------------------------------

    def _resolve_video_variants(
        self,
        tweet_id: str,
        query_id: str,
        bearer_token: str,
        cookies: dict[str, str],
    ) -> tuple[str | None, list[str], list[str]]:
        variables = {
            "tweetId": tweet_id,
            "withCommunity": False,
            "includePromotedContent": False,
            "withVoice": True,
        }
        features = {
            "responsive_web_graphql_exclude_directive_enabled": True,
            "longform_notetweets_inline_media_enabled": True,
            "responsive_web_media_download_video_enabled": True,
            "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": True,
        }

        headers = {
            "User-Agent": "Mozilla/5.0",
            "Authorization": f"Bearer {bearer_token}",
            "X-CSRF-Token": cookies.get("ct0", ""),
            "X-Twitter-Active-User": "yes",
            "X-Twitter-Auth-Type": "OAuth2Session",
            "Referer": f"https://x.com/i/status/{tweet_id}",
            "Origin": "https://x.com",
            "Accept": "*/*",
        }

        endpoint = f"https://x.com/i/api/graphql/{query_id}/TweetResultByRestId"
        params = {
            "variables": json.dumps(variables, separators=(",", ":")),
            "features": json.dumps(features, separators=(",", ":")),
        }

        last_error = "unknown error"
        for _ in range(3):
            try:
                resp = resolve_client.get(endpoint, params=params, headers=headers, cookies=cookies)
                if resp.status_code == 401:
                    last_error = "unauthorized, cookie may be expired"
                    continue
                resp.raise_for_status()
                payload = resp.json()
                title, candidates, image_urls = self._extract_media_from_graphql(payload)
                if candidates or image_urls:
                    return title, candidates, image_urls
                last_error = "no media in graphql response"
            except Exception as exc:
                last_error = str(exc)
                continue

        raise LocalResolveError(f"X graphql resolve failed: {last_error}")

    def _load_graphql_metadata(self, tweet_id: str) -> tuple[str, str]:
        now = time.time()
        if self._metadata_cache and now - self._metadata_cache[2] < 1800:
            return self._metadata_cache[0], self._metadata_cache[1]

        page_url = f"https://x.com/i/status/{tweet_id}"
        headers = {
            "User-Agent": "Mozilla/5.0",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
            "Referer": "https://x.com/",
        }
        try:
            page_resp = resolve_client.get(page_url, headers=headers)
            page_resp.raise_for_status()
            html = page_resp.text
        except Exception as exc:
            raise LocalResolveError(f"X page load failed: {exc}") from exc

        main_js_url = self._extract_main_js_url(html)
        if not main_js_url:
            raise LocalResolveError("Could not locate X main.js bundle")

        try:
            js_resp = resolve_client.get(main_js_url, headers=headers)
            js_resp.raise_for_status()
            js = js_resp.text
        except Exception as exc:
            raise LocalResolveError(f"X main.js fetch failed: {exc}") from exc

        query_id = self._extract_query_id(js)
        bearer = self._extract_bearer_token(js)
        if not query_id or not bearer:
            raise LocalResolveError("Could not parse X graphql metadata from main.js")
        self._metadata_cache = (query_id, bearer, now)
        return query_id, bearer

    def _extract_media_from_graphql(self, payload: object) -> tuple[str | None, list[str], list[str]]:
        """返回 (title, video_candidates, image_urls)"""
        title: str | None = None
        mp4s: list[tuple[int, str]] = []
        others: list[str] = []
        image_urls: list[str] = []

        def walk(node: object) -> None:
            nonlocal title
            if isinstance(node, dict):
                full_text = node.get("full_text")
                if isinstance(full_text, str) and full_text.strip() and not title:
                    title = full_text.strip()

                variants = node.get("variants")
                if isinstance(variants, list):
                    for variant in variants:
                        if not isinstance(variant, dict):
                            continue
                        url = variant.get("url")
                        if not isinstance(url, str) or "video.twimg.com" not in url:
                            continue
                        content_type = variant.get("content_type")
                        bitrate = variant.get("bitrate")
                        if content_type == "video/mp4":
                            mp4s.append((int(bitrate) if isinstance(bitrate, int) else 0, url))
                        elif ".m3u8" in url:
                            others.append(url)

                # 图片推文: type == "photo" 的 media_url_https
                if node.get("type") == "photo":
                    media_url = node.get("media_url_https")
                    if isinstance(media_url, str) and "pbs.twimg.com" in media_url:
                        image_urls.append(media_url)

                # 一些推文视频在 unified_card.string_value(JSON 字符串) 里
                if node.get("key") == "unified_card" and isinstance(node.get("value"), dict):
                    string_value = node["value"].get("string_value")
                    if isinstance(string_value, str) and string_value.startswith("{"):
                        try:
                            card_obj = json.loads(string_value)
                            walk(card_obj)
                        except Exception:
                            pass

                for child in node.values():
                    walk(child)
            elif isinstance(node, list):
                for child in node:
                    walk(child)

        walk(payload)

        mp4s_sorted = [url for _, url in sorted(mp4s, key=lambda x: x[0], reverse=True)]
        candidates = list(dict.fromkeys(mp4s_sorted + others))
        return title, candidates, list(dict.fromkeys(image_urls))

    @staticmethod
    def _extract_tweet_id(url: str) -> str | None:
        m = re.search(r"/status/(\d+)", url)
        return m.group(1) if m else None

    def _extract_main_js_url(self, html: str) -> str | None:
        m = self._main_js_pattern.search(html)
        return m.group(0) if m else None

    @staticmethod
    def _extract_query_id(js: str) -> str | None:
        m = re.search(
            r'queryId:"([A-Za-z0-9_-]{20,})",operationName:"TweetResultByRestId"',
            js,
        )
        return m.group(1) if m else None

    @staticmethod
    def _extract_bearer_token(js: str) -> str | None:
        m = re.search(r"AAAAAAAAAAAAAAAAAAAAA[A-Za-z0-9%_=-]{40,}", js)
        if not m:
            return None
        return m.group(0)
