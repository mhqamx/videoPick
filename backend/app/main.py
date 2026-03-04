from contextlib import asynccontextmanager
from urllib.parse import urlparse

from fastapi import FastAPI, HTTPException, Query, Request, Response

from .models import ResolveRequest, ResolveResponse
from .local_resolver import LocalResolveError, build_proxy_download_url
from .extractors.registry import ExtractorRegistry
from .extractors.base import close_shared_clients

# ---------------------------------------------------------------------------
# SSRF 防护：仅允许已知视频 CDN 域名
# ---------------------------------------------------------------------------

_ALLOWED_CDN_HOSTS = (
    "douyin.com", "iesdouyin.com", "douyinpic.com", "douyinvod.com",
    "tiktok.com", "tiktokcdn.com", "tiktokcdn-us.com", "tiktokv.com",
    "byteoversea.com", "ibytedtos.com", "muscdn.com",
    "bilibili.com", "bilivideo.com", "bilivideo.cn", "hdslb.com",
    "kwimgs.com", "kwai.net", "kuaishou.com",
    "xiaohongshu.com", "xhscdn.com", "xhscdn.net", "xhslink.com",
)


def _is_allowed_source(url: str) -> bool:
    try:
        host = (urlparse(url).hostname or "").lower()
    except Exception:
        return False
    return any(host == d or host.endswith("." + d) for d in _ALLOWED_CDN_HOSTS)


# ---------------------------------------------------------------------------
# App lifecycle
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    yield
    close_shared_clients()


app = FastAPI(title="Douyin Resolver API", version="0.1.0", lifespan=lifespan)
registry = ExtractorRegistry()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/resolve", response_model=ResolveResponse)
def resolve(req: ResolveRequest, request: Request) -> ResolveResponse:
    try:
        resolved = registry.resolve(req.text)
        proxy_url = build_proxy_download_url(str(request.base_url), resolved.best_url)
        return ResolveResponse(
            input_url=resolved.input_url,
            webpage_url=resolved.webpage_url,
            title=f"[{resolved.platform}] {resolved.title or ''}".strip(),
            uploader=None,
            duration=None,
            video_id=resolved.video_id,
            download_url=proxy_url,
            formats=[],
        )
    except LocalResolveError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@app.get("/download")
def download(source: str = Query(..., description="Resolved video source URL")) -> Response:
    if not _is_allowed_source(source):
        raise HTTPException(status_code=400, detail="Source URL not in allowed CDN hosts")
    try:
        content, selected = registry.download(source)
        headers = {
            "X-Source-URL": selected,
            "Content-Disposition": 'attachment; filename="video.mp4"',
        }
        return Response(content=content, media_type="video/mp4", headers=headers)
    except LocalResolveError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
