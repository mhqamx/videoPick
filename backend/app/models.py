from pydantic import BaseModel, Field


class ResolveRequest(BaseModel):
    text: str = Field(..., description="Douyin share text or URL")


class VideoFormat(BaseModel):
    format_id: str | None = None
    ext: str | None = None
    width: int | None = None
    height: int | None = None


class ResolveResponse(BaseModel):
    input_url: str
    webpage_url: str | None = None
    title: str | None = None
    uploader: str | None = None
    duration: float | None = None
    video_id: str | None = None
    download_url: str
    formats: list[VideoFormat] = []


class ErrorResponse(BaseModel):
    detail: str
