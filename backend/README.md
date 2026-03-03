# Douyin Resolver Backend (Codespaces)

A lightweight backend service for resolving Douyin share links using `yt-dlp`.

## Why this works better
Client-side requests are often blocked by Douyin anti-crawler rules (e.g. 404 on `aweme/v1/play`).
Running resolution on a server with `yt-dlp` is more stable.

## Endpoints
- `GET /health`
- `POST /resolve`

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
  "download_url": "https://...",
  "formats": []
}
```

## Run locally / in Codespaces

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pip install -U yt-dlp
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Test:

```bash
curl http://127.0.0.1:8000/health
curl -X POST http://127.0.0.1:8000/resolve \
  -H 'Content-Type: application/json' \
  -d '{"text":"https://v.douyin.com/oSWhN1HCRAM/"}'
```

## Optional cookies
If some videos require login/region cookies:

```bash
export DOUYIN_COOKIES_FILE=/workspaces/your-repo/cookies.txt
```

Then restart service.

## Deploy notes for Codespaces
- Keep process alive with `uvicorn` in terminal, or use a process manager.
- Expose port `8000` as public in Codespaces Ports panel.
- Use the public URL in your iOS app backend config.
