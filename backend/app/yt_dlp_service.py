from __future__ import annotations

import json
import os
import subprocess
from typing import Any

from .models import ResolveResponse, VideoFormat


class YtDlpError(RuntimeError):
    pass


def _build_command(url: str) -> list[str]:
    cmd = [
        "yt-dlp",
        "--no-playlist",
        "--dump-single-json",
        "--no-warnings",
        "--skip-download",
        "--user-agent",
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
    ]

    cookie_file = os.getenv("DOUYIN_COOKIES_FILE", "").strip()
    if cookie_file:
        cmd.extend(["--cookies", cookie_file])

    cmd.append(url)
    return cmd


def resolve_video(url: str) -> ResolveResponse:
    cmd = _build_command(url)

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=False,
            timeout=45,
        )
    except FileNotFoundError as exc:
        raise YtDlpError("yt-dlp not installed on server") from exc
    except subprocess.TimeoutExpired as exc:
        raise YtDlpError("yt-dlp request timed out") from exc

    if result.returncode != 0:
        msg = result.stderr.strip() or result.stdout.strip() or "yt-dlp resolve failed"
        raise YtDlpError(msg)

    try:
        data: dict[str, Any] = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise YtDlpError("invalid yt-dlp json output") from exc

    direct_url = data.get("url")
    if not direct_url:
        raise YtDlpError("No playable URL in yt-dlp output")

    formats: list[VideoFormat] = []
    for item in data.get("formats", [])[:8]:
        formats.append(
            VideoFormat(
                format_id=item.get("format_id"),
                ext=item.get("ext"),
                width=item.get("width"),
                height=item.get("height"),
            )
        )

    return ResolveResponse(
        input_url=url,
        webpage_url=data.get("webpage_url"),
        title=data.get("title"),
        uploader=data.get("uploader") or data.get("channel"),
        duration=data.get("duration"),
        video_id=data.get("id"),
        download_url=direct_url,
        formats=formats,
    )
