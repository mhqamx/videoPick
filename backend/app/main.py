from fastapi import FastAPI, HTTPException, Query, Request, Response

from .models import ResolveRequest, ResolveResponse
from .local_resolver import LocalResolveError, build_proxy_download_url
from .extractors.registry import ExtractorRegistry

app = FastAPI(title="Douyin Resolver API", version="0.1.0")
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
    try:
        content, selected = registry.download(source)
        headers = {
            "X-Source-URL": selected,
            "Content-Disposition": 'attachment; filename="douyin_video.mp4"',
        }
        return Response(content=content, media_type="video/mp4", headers=headers)
    except LocalResolveError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
