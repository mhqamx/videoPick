# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

多平台短视频无水印下载工具，采用"iOS 客户端 + Python backend 解析代理"双模式架构。支持抖音、TikTok、B站、快手、小红书。iOS 端优先调用后端，后端不可用时自动回退到本地 HTML 解析（仅抖音）。

## 常用命令

### iOS 构建

```bash
# 打开 Xcode 项目
open DouyinDownLoad.xcodeproj

# 命令行构建（模拟器）
xcodebuild -project DouyinDownLoad.xcodeproj -scheme DouyinDownLoad -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

### Python Backend

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

### Backend 测试

```bash
cd backend
source .venv/bin/activate
pytest tests/
```

### 快速验证 Backend API

```bash
curl http://127.0.0.1:8000/health
curl -X POST http://127.0.0.1:8000/resolve -H 'Content-Type: application/json' -d '{"text":"https://v.douyin.com/xxx/"}'
```

## 架构

### iOS 端 (MVVM + Actor)

```
DouyinDownLoadApp (@main)
  → ContentView → DouyinDownloadView (SwiftUI)
    → DouyinDownloadViewModel (@MainActor ObservableObject)
      → DouyinDownloadService (actor, singleton)
```

**关键流程：** 用户输入 → 提取 URL → 优先调 backend `/resolve` → 失败则本地 HTML 解析 → 下载视频到临时目录 → 可选保存到相册

**本地 HTML 解析多级回退：**
1. `window._ROUTER_DATA` JSON（当前主要结构）
2. `window._SSR_HYDRATED_DATA` JSON
3. `<script id="RENDER_DATA">` URL 编码 JSON
4. 原始 HTML 正则匹配

**并发模型：** 构建设置中 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，所有类型默认 `@MainActor`。`DouyinDownloadService` 显式声明为 `actor` 以获得独立隔离域。

### Python Backend (FastAPI + Extractor 插件架构)

```
FastAPI (main.py)
  → ExtractorRegistry → [DouyinExtractor, TikTokExtractor, BilibiliExtractor,
                          KuaishouExtractor, XiaohongshuExtractor] → local_resolver.py
```

**三个路由：** `GET /health`、`POST /resolve`（解析视频信息）、`GET /download?source=...`（代理下载字节流）

**代理下载设计：** backend 不直接返回 CDN URL，而是返回指向自身的 `/download?source=...` 代理地址，iOS 从 backend 下载，由 backend 转发 CDN 请求，避免移动端被 CDN 封锁。

**扩展新平台：** 在 `backend/app/extractors/` 新建文件继承 `BaseExtractor` → 实现 `extract_url`/`can_handle_source`/`resolve` → 在 `registry.py` 注册。

**各平台解析策略：**

| 平台 | Extractor | 解析方式 |
|------|-----------|----------|
| 抖音 | `DouyinExtractor` | 移动页面 HTML JSON（`_ROUTER_DATA` 等多级回退） |
| TikTok | `TikTokExtractor` | embed 页面 `/embed/v2/{id}` 的 `__FRONTITY_CONNECT_STATE__` JSON（主页面 URL 带占位符 token 无法下载） |
| B站 | `BilibiliExtractor` | 网页 `__INITIAL_STATE__` + Open API 回退 |
| 快手 | `KuaishouExtractor` | 移动页面 `APOLLO_STATE` / `__INITIAL_STATE__` |
| 小红书 | `XiaohongshuExtractor` | 移动页面 `__INITIAL_STATE__` |

## 重要实现细节

- **去水印（抖音）：** `/playwm/` 替换为 `/play/`，移除 `logo_name` 和 `watermark` 查询参数
- **TikTok 注意事项：** 主页面视频 URL 带 `tk=tt_chain_token` 占位符（Akamai CDN 返回 403），必须通过 embed 页面获取带有效 token 的 URL
- **Backend URL 列表：** iOS 端 `backendResolveURLs` 按优先级尝试多个后端地址（Codespaces 公网优先，localhost 兜底）
- **localhost 归一化：** `normalizeBackendDownloadURL()` 将后端返回的 localhost 下载地址替换为实际后端域名
- **相册权限：** 通过构建设置 `INFOPLIST_KEY_NSPhotoLibrary*` 注入，不是独立的 Info.plist 文件
- **Xcode 16+ 文件同步：** 使用 `PBXFileSystemSynchronizedRootGroup`，新增 Swift 文件无需手动添加到 project.pbxproj
- **页面结构会变化：** 各平台解析逻辑需要跟进前端变更，调试时用 `curl -L <url> -H 'User-Agent: Mozilla/5.0 (iPhone; ...)'` 抓取页面检查结构

## 无外部依赖

iOS 端零第三方依赖，仅使用系统框架（SwiftUI, Foundation, Photos, AVKit, UIKit）。Backend 依赖 fastapi + httpx + pydantic。
