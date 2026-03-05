from __future__ import annotations

import re

from .base import BaseExtractor, ResolvedVideo
from ..local_resolver import LocalResolveError, download_video_bytes, resolve_video


class DouyinExtractor(BaseExtractor):
    platform = "douyin"
    _CDN_HOSTS = ("douyin.com", "iesdouyin.com", "snssdk.com", "douyinpic.com", "byteimg.com", "douyincdn.com")
    _default_referer = "https://www.douyin.com/"

    _short_pattern = re.compile(r"https?://v\.douyin\.com/[a-zA-Z0-9_]+/?", re.I)
    _long_pattern = re.compile(
        r"https?://(?:www\.|m\.)?(?:douyin\.com|iesdouyin\.com)/(?:video|share/video)/[0-9]+",
        re.I,
    )
    _generic_pattern = re.compile(r"https?://[^\s]+")

    def extract_url(self, text: str) -> str | None:
        for pattern in (self._short_pattern, self._long_pattern):
            match = pattern.search(text)
            if match:
                return match.group(0).strip().rstrip("。.,!;，！；")
        # 泛匹配仅在包含 douyin/iesdouyin 域名时生效
        match = self._generic_pattern.search(text)
        if match:
            candidate = match.group(0).strip().rstrip("。.,!;，！；")
            if any(d in candidate for d in ("douyin.com", "iesdouyin.com")):
                return candidate
        return None

    def resolve(self, text: str) -> ResolvedVideo:
        url = self.extract_url(text)
        if not url:
            raise LocalResolveError("No Douyin URL found in input")

        resolved = resolve_video(url)
        return ResolvedVideo(
            platform=self.platform,
            input_url=resolved.input_url,
            webpage_url=resolved.webpage_url,
            title=resolved.title,
            video_id=resolved.video_id,
            best_url=resolved.best_url,
            candidates=resolved.candidates,
            media_type=resolved.media_type,
            image_urls=resolved.image_urls,
        )

    def download_bytes(self, source_url: str) -> tuple[bytes, str]:
        return download_video_bytes(source_url)
