from __future__ import annotations

from .base import ResolvedVideo, VideoExtractor
from .douyin import DouyinExtractor
from ..local_resolver import LocalResolveError


class ExtractorRegistry:
    def __init__(self) -> None:
        # 后续可直接在这里注册更多平台:
        # KuaishouExtractor(), BilibiliExtractor(), TikTokExtractor() ...
        self.extractors: list[VideoExtractor] = [DouyinExtractor()]

    def resolve(self, text: str) -> ResolvedVideo:
        last_error: Exception | None = None
        for extractor in self.extractors:
            try:
                url = extractor.extract_url(text)
                if not url:
                    continue
                return extractor.resolve(text)
            except Exception as exc:
                last_error = exc
                continue
        if last_error:
            raise LocalResolveError(str(last_error))
        raise LocalResolveError("No supported platform URL found")

    def download(self, source_url: str) -> tuple[bytes, str]:
        for extractor in self.extractors:
            if extractor.can_handle_source(source_url):
                return extractor.download_bytes(source_url)
        raise LocalResolveError("No extractor supports this source URL")
