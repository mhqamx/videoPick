from __future__ import annotations

import json
import logging

import httpx

from .base import ResolvedVideo, VideoExtractor
from .bilibili import BilibiliExtractor
from .douyin import DouyinExtractor
from .kuaishou import KuaishouExtractor
from .tiktok import TikTokExtractor
from .xiaohongshu import XiaohongshuExtractor
from ..local_resolver import LocalResolveError

logger = logging.getLogger(__name__)


class ExtractorRegistry:
    def __init__(self) -> None:
        self.extractors: list[VideoExtractor] = [
            DouyinExtractor(),
            TikTokExtractor(),
            BilibiliExtractor(),
            KuaishouExtractor(),
            XiaohongshuExtractor(),
        ]

    def resolve(self, text: str) -> ResolvedVideo:
        last_error: Exception | None = None
        for extractor in self.extractors:
            try:
                url = extractor.extract_url(text)
                if not url:
                    continue
                return extractor.resolve(text)
            except (LocalResolveError, httpx.HTTPError, json.JSONDecodeError) as exc:
                logger.warning("Extractor %s failed: %s", extractor.platform, exc)
                last_error = exc
                continue
            except Exception as exc:
                logger.exception("Unexpected error in extractor %s", extractor.platform)
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
