from __future__ import annotations

import json
import re
import time
import uuid
from urllib.parse import urlparse

import httpx

from .base import BaseExtractor, ResolvedVideo, download_client, resolve_client
from ..local_resolver import LocalResolveError

# B站需要桌面端 UA，不能用移动端 UA
_DESKTOP_USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0.0.0 Safari/537.36"
)


class BilibiliExtractor(BaseExtractor):
    platform = "bilibili"
    _CDN_HOSTS = ()  # B站 CDN 域名多变，使用自定义 can_handle_source
    _default_referer = "https://www.bilibili.com/"

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

    def resolve(self, text: str, client_cookies: dict[str, str] | None = None) -> ResolvedVideo:
        url = self.extract_url(text)
        if not url:
            raise LocalResolveError("No Bilibili URL found in input")

        webpage_url: str | None = None
        title: str | None = None
        candidates: list[str] = []

        try:
            # B站短链解析需要禁用 follow_redirects，使用独立 client
            with httpx.Client(timeout=20, follow_redirects=False) as client:
                webpage_url = self._resolve_canonical_webpage_url(client, url)
                video_id = self._extract_video_id_from_url(webpage_url) or f"bili_unknown_{int(time.time())}"

                try:
                    html, webpage_url = self._fetch_html_with_retry(client, webpage_url)
                    title = self._extract_title_from_initial_state(html)
                    candidates = self._extract_progressive_candidates(html)
                except httpx.HTTPStatusError as exc:
                    if exc.response.status_code not in (403, 412):
                        raise

                if not candidates:
                    api_title, api_candidates = self._resolve_via_open_api(
                        client=client,
                        video_id=video_id,
                        referer_url=webpage_url,
                    )
                    title = title or api_title
                    candidates = api_candidates
        except LocalResolveError:
            raise
        except Exception as exc:
            raise LocalResolveError(f"Bilibili resolve failed: {exc}") from exc

        video_id = self._extract_video_id_from_url(webpage_url or "") or f"bili_unknown_{int(time.time())}"

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
        """B站需要桌面端 UA + Referer，覆盖基类实现。"""
        headers = self._bili_headers(referer="https://www.bilibili.com/") | {
            "Accept": "*/*",
            "Range": "bytes=0-",
        }
        try:
            resp = download_client.get(source_url, headers=headers)
            if 200 <= resp.status_code < 300 and resp.content:
                return resp.content, source_url
            raise LocalResolveError(
                f"Bilibili download failed: status={resp.status_code}"
            )
        except LocalResolveError:
            raise
        except Exception as exc:
            raise LocalResolveError(f"Bilibili download failed: {exc}") from exc

    # ------------------------------------------------------------------
    # 内部方法
    # ------------------------------------------------------------------

    @staticmethod
    def _bili_headers(referer: str) -> dict[str, str]:
        return {
            "User-Agent": _DESKTOP_USER_AGENT,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh-Hans;q=0.9",
            "Referer": referer,
            "Origin": "https://www.bilibili.com",
        }

    @staticmethod
    def _api_headers(referer: str) -> dict[str, str]:
        return {
            "User-Agent": _DESKTOP_USER_AGENT,
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "zh-CN,zh-Hans;q=0.9",
            "Referer": referer,
            "Origin": "https://www.bilibili.com",
            "Cookie": (
                f"buvid3={uuid.uuid4()}infoc; "
                f"b_nut={int(time.time())}; "
                "CURRENT_FNVAL=0; CURRENT_QUALITY=80"
            ),
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

        return self._extract_durl_candidates(data)

    @staticmethod
    def _extract_durl_candidates(data: dict) -> list[str]:
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
        if self._short_pattern.search(input_url):
            current = input_url
            for _ in range(6):
                resp = client.get(current, headers=self._bili_headers(referer="https://www.bilibili.com/"))
                if 300 <= resp.status_code < 400 and resp.headers.get("Location"):
                    location = resp.headers["Location"]
                    current = str(resp.request.url.join(location))
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
        headers = self._bili_headers(referer="https://www.bilibili.com/")
        resp = client.get(webpage_url, headers=headers, follow_redirects=True)
        if resp.status_code in (403, 412):
            alt_headers = headers | {
                "Upgrade-Insecure-Requests": "1",
                "Sec-Fetch-Dest": "document",
                "Sec-Fetch-Mode": "navigate",
                "Sec-Fetch-Site": "none",
            }
            resp = client.get(webpage_url, headers=alt_headers, follow_redirects=True)
        resp.raise_for_status()
        return resp.text, str(resp.url)

    def _resolve_via_open_api(
        self,
        client: httpx.Client,
        video_id: str,
        referer_url: str,
    ) -> tuple[str | None, list[str]]:
        bvid, aid = self._split_video_id(video_id)
        view_params: dict[str, str] = {"bvid": bvid} if bvid else {"aid": aid}
        view_resp = client.get(
            "https://api.bilibili.com/x/web-interface/view",
            params=view_params,
            headers=self._api_headers(referer=referer_url),
            follow_redirects=True,
        )
        view_resp.raise_for_status()
        view_payload = view_resp.json()
        if not isinstance(view_payload, dict) or view_payload.get("code") != 0:
            message = view_payload.get("message") if isinstance(view_payload, dict) else "invalid response"
            raise LocalResolveError(f"Bilibili view api failed: {message}")

        data = view_payload.get("data") if isinstance(view_payload, dict) else None
        if not isinstance(data, dict):
            raise LocalResolveError("Bilibili view api returned invalid data")

        title = data.get("title") if isinstance(data.get("title"), str) else None
        cid = data.get("cid")
        if not isinstance(cid, int):
            pages = data.get("pages")
            if isinstance(pages, list) and pages and isinstance(pages[0], dict):
                cid = pages[0].get("cid")
        if not isinstance(cid, int):
            raise LocalResolveError("Bilibili view api did not return cid")

        play_params: dict[str, str | int] = {
            "cid": cid,
            "qn": 80,
            "fnval": 0,
            "fnver": 0,
            "fourk": 1,
            "otype": "json",
            "platform": "html5",
            "high_quality": 1,
        }
        if bvid:
            play_params["bvid"] = bvid
        else:
            play_params["avid"] = aid

        play_resp = client.get(
            "https://api.bilibili.com/x/player/playurl",
            params=play_params,
            headers=self._api_headers(referer=referer_url),
            follow_redirects=True,
        )
        play_resp.raise_for_status()
        play_payload = play_resp.json()
        if not isinstance(play_payload, dict) or play_payload.get("code") != 0:
            message = play_payload.get("message") if isinstance(play_payload, dict) else "invalid response"
            raise LocalResolveError(f"Bilibili playurl api failed: {message}")

        play_data = play_payload.get("data") if isinstance(play_payload, dict) else None
        if not isinstance(play_data, dict):
            raise LocalResolveError("Bilibili playurl api returned invalid data")

        candidates = self._extract_durl_candidates(play_data)
        return title, candidates

    @staticmethod
    def _split_video_id(video_id: str) -> tuple[str | None, str | None]:
        if video_id.upper().startswith("BV"):
            return video_id, None
        if video_id.lower().startswith("av"):
            return None, video_id[2:]
        raise LocalResolveError("Unsupported Bilibili video id format")
