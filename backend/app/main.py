from fastapi import FastAPI, HTTPException

from .models import ResolveRequest, ResolveResponse
from .utils import extract_url
from .yt_dlp_service import YtDlpError, resolve_video

app = FastAPI(title="Douyin Resolver API", version="0.1.0")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/resolve", response_model=ResolveResponse)
def resolve(req: ResolveRequest) -> ResolveResponse:
    try:
        url = extract_url(req.text)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    try:
        return resolve_video(url)
    except YtDlpError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
