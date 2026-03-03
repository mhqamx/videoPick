# Douyin Resolver Backend (Codespaces)

A lightweight backend service for resolving Douyin share links with local parsing (no `yt-dlp` dependency).

## Architecture (extensible)
- `app/extractors/base.py`: extractor contract
- `app/extractors/douyin.py`: Douyin extractor implementation
- `app/extractors/registry.py`: extractor registry/router
- `app/local_resolver.py`: Douyin local parse + download proxy helpers

To add a new platform (e.g. Kuaishou/Bilibili/TikTok):
1. Add `app/extractors/<platform>.py` implementing `extract_url/resolve/download_bytes`
2. Register extractor in `ExtractorRegistry`
3. Keep API unchanged (`/resolve` + `/download`)

## Endpoints
- `GET /health`
- `POST /resolve`
- `GET /download?source=...`

Request body:

```json
{ "text": "看春晚，玩AI！https://v.douyin.com/oSWhN1HCRAM/" }
```

Response body (example):

```json
{
  "input_url": "https://v.douyin.com/oSWhN1HCRAM/",
  "webpage_url": "https://www.douyin.com/video/7607807621344562451",
  "title": "...",
  "uploader": "...",
  "duration": 12.3,
  "video_id": "7607807621344562451",
  "download_url": "http://127.0.0.1:8000/download?source=...",
  "formats": []
}
```

`/resolve` returns a backend proxy URL in `download_url` so the iOS app downloads through backend instead of direct `aweme` URL.

## Run locally / in Codespaces

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Test:

```bash
curl http://127.0.0.1:8000/health
curl -X POST http://127.0.0.1:8000/resolve \
  -H 'Content-Type: application/json' \
  -d '{"text":"https://v.douyin.com/oSWhN1HCRAM/"}'
```

## Deploy notes for Codespaces
- Keep process alive with `uvicorn` in terminal, or use a process manager.
- Expose port `8000` as public in Codespaces Ports panel.
- Use the public URL in your iOS app backend config.
