from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol


@dataclass
class ResolvedVideo:
    platform: str
    input_url: str
    webpage_url: str | None
    title: str | None
    video_id: str
    best_url: str
    candidates: list[str]


class VideoExtractor(Protocol):
    platform: str

    def extract_url(self, text: str) -> str | None:
        ...

    def can_handle_source(self, source_url: str) -> bool:
        ...

    def resolve(self, text: str) -> ResolvedVideo:
        ...

    def download_bytes(self, source_url: str) -> tuple[bytes, str]:
        ...
