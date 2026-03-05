from __future__ import annotations

import json
import re
import time
from dataclasses import dataclass
from typing import Any
from urllib.parse import quote, unquote

import httpx


class LocalResolveError(RuntimeError):
    pass


@dataclass
class LocalResolvedVideo:
    input_url: str
    webpage_url: str | None
    title: str | None
    video_id: str
    best_url: str
    candidates: list[str]
    media_type: str = "video"  # "video" | "image"
    image_urls: list[str] | None = None

    def __post_init__(self):
        if self.image_urls is None:
            self.image_urls = []


def _http_headers() -> dict[str, str]:
    return {
        "User-Agent": (
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 "
            "Mobile/15E148 Safari/604.1"
        ),
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "zh-CN,zh-Hans;q=0.9",
        "Referer": "https://www.douyin.com/",
    }


def _normalize_video_url(raw: str) -> str:
    url = raw.replace("playwm", "play")
    url = re.sub(r"([?&])(watermark|logo_name)=[^&]*", "", url)
    url = re.sub(r"[?&]$", "", url)
    return url


def _extract_json_payload(html: str) -> tuple[str | None, bool]:
    patterns = [
        r"window\._ROUTER_DATA\s*=\s*(\{.*?\})(?:\s*</script>|\s*;)",
        r"window\._SSR_HYDRATED_DATA\s*=\s*(\{.*?\})(?:\s*</script>|\s*;)",
        r'<script[^>]*id="RENDER_DATA"[^>]*>(.*?)</script>',
    ]
    for p in patterns:
        m = re.search(p, html, flags=re.S)
        if m:
            return m.group(1).strip(), "RENDER_DATA" in p
    return None, False


def _find_dict_containing(value: Any, key: str) -> dict[str, Any] | None:
    if isinstance(value, dict):
        if key in value:
            return value
        for v in value.values():
            found = _find_dict_containing(v, key)
            if found:
                return found
    elif isinstance(value, list):
        for v in value:
            found = _find_dict_containing(v, key)
            if found:
                return found
    return None


def _build_candidates_from_item(item: dict[str, Any]) -> list[str]:
    candidates: list[str] = []
    video = item.get("video") or {}
    play_addr = video.get("play_addr") or {}
    for url in play_addr.get("url_list", []) or []:
        if isinstance(url, str):
            candidates.append(_normalize_video_url(url))
    # 一些页面会把可播地址放在 bit_rate 里
    for br in video.get("bit_rate", []) or []:
        play = (br or {}).get("play_addr") or {}
        for url in play.get("url_list", []) or []:
            if isinstance(url, str):
                candidates.append(_normalize_video_url(url))
    return list(dict.fromkeys(candidates))


def _build_image_urls_from_item(item: dict[str, Any]) -> list[str]:
    """从图文作品 item 中提取无水印图片 URL 列表。"""
    image_urls: list[str] = []
    images = item.get("images") or []
    if not isinstance(images, list):
        return image_urls
    for img in images:
        if not isinstance(img, dict):
            continue
        url_list = img.get("url_list") or []
        if not isinstance(url_list, list) or not url_list:
            continue
        # 优先选 jpeg/jpg，其次任意可用 URL
        chosen = None
        for u in url_list:
            if isinstance(u, str) and u:
                if chosen is None:
                    chosen = u
                if "jpeg" in u.lower() or "jpg" in u.lower():
                    chosen = u
                    break
        if chosen:
            image_urls.append(chosen)
    return image_urls


def _is_image_post(item: dict[str, Any]) -> bool:
    """判断一个 aweme item 是否为图文作品。"""
    aweme_type = item.get("aweme_type")
    if aweme_type == 2 or aweme_type == "2":
        return True
    images = item.get("images")
    return isinstance(images, list) and len(images) > 0


def _parse_from_json(root: Any) -> tuple[str | None, str | None, list[str], str, list[str]]:
    """返回 (title, video_id, candidates, media_type, image_urls)"""
    title: str | None = None
    video_id: str | None = None
    candidates: list[str] = []
    media_type: str = "video"
    image_urls: list[str] = []

    if isinstance(root, dict):
        loader = root.get("loaderData")
        if isinstance(loader, dict):
            for v in loader.values():
                if not isinstance(v, dict):
                    continue
                info = v.get("videoInfoRes")
                if not isinstance(info, dict):
                    continue
                items = info.get("item_list") or []
                if isinstance(items, list) and items:
                    first = items[0] if isinstance(items[0], dict) else {}
                    title = first.get("desc") if isinstance(first.get("desc"), str) else title
                    video_id = first.get("aweme_id") if isinstance(first.get("aweme_id"), str) else video_id
                    if _is_image_post(first):
                        media_type = "image"
                        image_urls = _build_image_urls_from_item(first)
                        if image_urls:
                            break
                    else:
                        candidates.extend(_build_candidates_from_item(first))
                        if candidates:
                            break

    if not candidates and not image_urls:
        # 先尝试找图文
        aweme = _find_dict_containing(root, "images")
        if isinstance(aweme, dict) and _is_image_post(aweme):
            title = aweme.get("desc") if isinstance(aweme.get("desc"), str) else title
            video_id = aweme.get("aweme_id") if isinstance(aweme.get("aweme_id"), str) else video_id
            media_type = "image"
            image_urls = _build_image_urls_from_item(aweme)

    if not candidates and media_type == "video":
        aweme = _find_dict_containing(root, "video")
        if isinstance(aweme, dict):
            title = aweme.get("desc") if isinstance(aweme.get("desc"), str) else title
            video_id = aweme.get("aweme_id") if isinstance(aweme.get("aweme_id"), str) else video_id
            candidates.extend(_build_candidates_from_item(aweme))

    return title, video_id, list(dict.fromkeys(candidates)), media_type, image_urls


def _parse_from_raw_html(html: str) -> list[str]:
    patterns = [
        r"(https?:\\/\\/[^\"']+aweme\\/v1\\/playwm?\\/[^\"']*)",
        r"(https?://[^\"']+aweme/v1/playwm?/[^\"']*)",
        r"(https?:\\/\\/[^\"']+\.mp4[^\"']*)",
    ]
    candidates: list[str] = []
    for p in patterns:
        for m in re.finditer(p, html, flags=re.I):
            url = m.group(1).replace("\\/", "/")
            candidates.append(_normalize_video_url(url))
    return list(dict.fromkeys(candidates))


def _candidate_download_urls(url: str) -> list[str]:
    urls = [url, url.replace("/play/", "/playwm/")]
    urls.append(re.sub(r"([?&])line=\d+&?", r"\1", url).rstrip("?&"))
    urls.append(urls[-1].replace("/play/", "/playwm/"))
    cleaned = [u for u in urls if u]
    return list(dict.fromkeys(cleaned))


def resolve_video(url: str) -> LocalResolvedVideo:
    headers = _http_headers()
    with httpx.Client(timeout=20, follow_redirects=True, headers=headers) as client:
        resp = client.get(url)
        resp.raise_for_status()
        html = resp.text
        webpage_url = str(resp.url)

    json_payload, is_render_data = _extract_json_payload(html)
    title: str | None = None
    video_id: str | None = None
    candidates: list[str] = []

    media_type: str = "video"
    image_urls: list[str] = []

    if json_payload:
        if is_render_data:
            json_payload = unquote(json_payload)
        json_payload = json_payload.replace("undefined", "null")
        try:
            root = json.loads(json_payload)
            title, video_id, candidates, media_type, image_urls = _parse_from_json(root)
        except (json.JSONDecodeError, ValueError, KeyError):
            candidates = []

    if media_type == "image" and image_urls:
        video_id = video_id or f"unknown_{int(time.time())}"
        return LocalResolvedVideo(
            input_url=url,
            webpage_url=webpage_url,
            title=title,
            video_id=video_id,
            best_url=image_urls[0],
            candidates=[],
            media_type="image",
            image_urls=image_urls,
        )

    if not candidates:
        candidates = _parse_from_raw_html(html)

    if not candidates:
        raise LocalResolveError("No video link found in page")

    best = candidates[0]
    download_candidates = _candidate_download_urls(best)
    video_id = video_id or f"unknown_{int(time.time())}"

    return LocalResolvedVideo(
        input_url=url,
        webpage_url=webpage_url,
        title=title,
        video_id=video_id,
        best_url=best,
        candidates=download_candidates,
    )


def download_video_bytes(source: str) -> tuple[bytes, str]:
    headers = _http_headers() | {
        "Accept": "*/*",
        "Range": "bytes=0-",
    }
    last_error = "download failed"
    with httpx.Client(timeout=60, follow_redirects=True, headers=headers) as client:
        for candidate in _candidate_download_urls(source):
            try:
                resp = client.get(candidate)
                if 200 <= resp.status_code < 300 and resp.content:
                    return resp.content, candidate
                last_error = f"status={resp.status_code}"
            except httpx.HTTPError as exc:
                last_error = str(exc)
                continue
    raise LocalResolveError(last_error)


def build_proxy_download_url(base_url: str, source: str) -> str:
    return f"{base_url.rstrip('/')}/download?source={quote(source, safe='')}"
