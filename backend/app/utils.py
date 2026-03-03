import re
from urllib.parse import urlparse


URL_PATTERN = re.compile(r"https?://[^\s]+")
DOUYIN_SHORT_PATTERN = re.compile(r"https?://v\.douyin\.com/[a-zA-Z0-9_]+/?", re.I)
DOUYIN_LONG_PATTERN = re.compile(
    r"https?://(?:www\.|m\.)?(?:douyin\.com|iesdouyin\.com)/(?:video|share/video)/[0-9]+",
    re.I,
)


def extract_url(text: str) -> str:
    # 优先命中结构化平台链接,与 DouyinDownloadKit 的提取思路一致
    match = DOUYIN_SHORT_PATTERN.search(text) or DOUYIN_LONG_PATTERN.search(text) or URL_PATTERN.search(text)
    if not match:
        raise ValueError("No URL found in input")

    raw = match.group(0).strip().rstrip("。.,!;，！；")
    parsed = urlparse(raw)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ValueError("Invalid URL")
    return raw
