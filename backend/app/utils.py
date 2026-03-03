import re
from urllib.parse import urlparse


URL_PATTERN = re.compile(r"https?://[^\s]+")


def extract_url(text: str) -> str:
    match = URL_PATTERN.search(text)
    if not match:
        raise ValueError("No URL found in input")

    raw = match.group(0).strip().rstrip("。.,!;，！；")
    parsed = urlparse(raw)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ValueError("Invalid URL")
    return raw
