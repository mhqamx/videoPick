#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

if [ ! -d "$ROOT_DIR/.venv311" ]; then
  python3.11 -m venv .venv311
fi

source "$ROOT_DIR/.venv311/bin/activate"

echo "[backend] starting: http://127.0.0.1:8000"
exec uvicorn app.main:app --host 127.0.0.1 --port 8000
