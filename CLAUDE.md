# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

多平台短视频/图文无水印下载工具，采用"iOS/Android/Flutter 客户端 + Python backend 解析代理"四端架构。支持抖音、TikTok、Instagram、X (Twitter)、B站、快手、小红书。客户端支持本地解析（抖音/小红书/快手/Instagram/X）+ backend 回退。支持视频和图文两种媒体类型下载。

## 常用命令

### iOS 构建

```bash
# 打开 Xcode 项目
open ios/DouyinDownLoad.xcodeproj

# 命令行构建（模拟器）
xcodebuild -project ios/DouyinDownLoad.xcodeproj -scheme DouyinDownLoad -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

### Flutter 构建

```bash
cd flutter
flutter pub get
flutter run                    # debug 模式（需要连接设备）
flutter run --release          # release 模式（可脱机使用）
flutter build ipa              # 打 iOS ipa 包
flutter build apk              # 打 Android apk 包
```

### Android 构建

```bash
cd android
./gradlew assembleDebug
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
      → CookieStore (nonisolated, UserDefaults 持久化)
  → CookieSettingsView (Cookie 配置界面)
```

**关键流程：** 用户输入 → 提取 URL → 判断平台（抖音/小红书/快手优先本地解析，Instagram/X 仅本地解析，其他平台调 backend） → 失败则回退 → 下载视频/图片到临时目录 → 可选保存到相册

**本地 HTML 解析多级回退（抖音）：**
1. `window._ROUTER_DATA` JSON（当前主要结构）
2. `window._SSR_HYDRATED_DATA` JSON
3. `<script id="RENDER_DATA">` URL 编码 JSON
4. 原始 HTML 正则匹配

**并发模型：** 构建设置中 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，所有类型默认 `@MainActor`。`DouyinDownloadService` 显式声明为 `actor` 以获得独立隔离域。`CookieStore` 为 `nonisolated final class: @unchecked Sendable`（UserDefaults 自身线程安全）。

**媒体类型：** `MediaType` 枚举支持 `.video` 和 `.images`，图文作品通过 `imageURLs` 列表下载多张图片。

### Android 端 (Jetpack Compose + MVVM)

```
MainActivity (Compose)
  → DownloadScreen / CookieSettingsScreen / FullscreenImageScreen
    → DownloadViewModel
      → DownloadRepository (OkHttp + kotlinx.serialization)
      → CookieStore (SharedPreferences 持久化)
```

**包名：** `com.demo.videopick`

**依赖：** OkHttp、kotlinx.serialization、Jetpack Compose、Media3 ExoPlayer

**与 iOS 对等功能：** 后端解析 + 本地抖音解析回退、视频/图文下载、Cookie 配置、保存到相册/下载目录。

### Flutter 端 (Provider + MVVM)

```
VideoPickApp (@main)
  → DownloadPage (ChangeNotifierProvider)
    → DownloadViewModel (ChangeNotifier)
      → DownloadService (singleton, 本地解析 + backend 回退)
      → CookieStore (SharedPreferences 持久化)
  → CookieSettingsPage (Cookie 配置界面)
  → FullscreenImagePage (图片全屏预览)
```

**包名：** `com.demo.videoPick`

**HTTP 网络栈：** iOS/macOS 使用 `cupertino_http`（`CupertinoClient`，基于原生 `URLSession`，走系统代理/VPN）；其他平台使用 `dart:io` 默认客户端。解决了 `dart:io HttpClient` 不走系统代理导致的网络超时问题。

**ATS 兼容：** 所有 URL 在请求前统一通过 `_ensureHttps()` 转为 HTTPS，避免 iOS App Transport Security 拦截 HTTP 请求。

**UIScene 生命周期：** iOS 端使用 `FlutterImplicitEngineDelegate` + `FlutterSceneDelegate`（Flutter 3.41+ UIScene 迁移方案），Info.plist 需要 `UIApplicationSceneManifest` 配置。

**与 iOS/Android 对等功能：** 本地解析（抖音/小红书/快手/Instagram/X）+ backend 回退、视频/图文下载、Cookie 配置、保存到相册。

### Python Backend (FastAPI + Extractor 插件架构)

```
FastAPI (main.py)
  → ExtractorRegistry → [DouyinExtractor, TikTokExtractor, InstagramExtractor,
                          XExtractor, BilibiliExtractor, KuaishouExtractor,
                          XiaohongshuExtractor] → local_resolver.py
```

**三个路由：** `GET /health`、`POST /resolve`（解析视频/图文信息）、`GET /download?source=...`（代理下载字节流）

**代理下载设计：** backend 不直接返回 CDN URL，而是返回指向自身的 `/download?source=...` 代理地址，客户端从 backend 下载，由 backend 转发 CDN 请求，避免移动端被 CDN 封锁。图片 URL 同样走代理。`/download` 端点根据 URL 自动判断媒体类型（video/mp4、image/webp、image/jpeg 等）。

**SSRF 防护：** `_ALLOWED_CDN_HOSTS` 白名单限制代理下载的目标域名，仅允许已知视频/图片 CDN。

**Cookie 机制：** `/resolve` 接口支持 `cookies` 字段，客户端传递各平台认证 Cookie（如 Instagram sessionid、X auth_token），由 `ExtractorRegistry` 分发给对应 Extractor。

**扩展新平台：** 在 `backend/app/extractors/` 新建文件继承 `BaseExtractor` → 实现 `extract_url`/`can_handle_source`/`resolve` → 在 `registry.py` 注册。

**各平台解析策略：**

| 平台 | Extractor | 解析方式 | 需要 Cookie |
|------|-----------|----------|-------------|
| 抖音 | `DouyinExtractor` | 移动页面 HTML JSON（`_ROUTER_DATA` 等多级回退） | 否 |
| TikTok | `TikTokExtractor` | embed 页面 `/embed/v2/{id}` 的 `__FRONTITY_CONNECT_STATE__` JSON | 否 |
| Instagram | `InstagramExtractor` | Cookie 认证 API（支持 reel/post/tv） | 是（sessionid, ds_user_id, csrftoken） |
| X (Twitter) | `XExtractor` | Cookie 认证 API | 是（auth_token, ct0） |
| B站 | `BilibiliExtractor` | 网页 `__INITIAL_STATE__` + Open API 回退 | 否 |
| 快手 | `KuaishouExtractor` | 移动页面 `APOLLO_STATE` / `__INITIAL_STATE__`（支持图集） | 否 |
| 小红书 | `XiaohongshuExtractor` | 移动页面 `__INITIAL_STATE__`（支持图文笔记） | 否 |

## 重要实现细节

- **去水印（抖音）：** `/playwm/` 替换为 `/play/`，移除 `logo_name` 和 `watermark` 查询参数
- **TikTok 注意事项：** 主页面视频 URL 带 `tk=tt_chain_token` 占位符（Akamai CDN 返回 403），必须通过 embed 页面获取带有效 token 的 URL
- **Instagram/X 需要 Cookie：** 这两个平台需要用户在客户端 Cookie 设置页面填入认证信息，通过 `/resolve` 请求传递给 backend
- **图文下载：** 快手、小红书、Instagram 支持图文/图集下载，`ResolvedVideo.image_urls` 返回多张图片 URL，客户端逐张下载并可保存到相册
- **图文下载（抖音）：** 本地解析支持 `aweme_type == 2` 或包含 `images` 数组的图文作品，提取 `images[].url_list` 中的无水印图片
- **X 图片推文：** GraphQL 响应中 `type == "photo"` 的 `media_url_https`（`pbs.twimg.com`）
- **快手本地解析：** API（`/rest/wd/ugH5App/photo/simple/info`）+ `__APOLLO_STATE__` + `__INITIAL_STATE__` + 正则回退，支持图集
- **Backend URL 列表：** iOS 端 `backendResolveURLs` 按优先级尝试多个后端地址（局域网 IP 优先，Codespaces 公网备用）
- **localhost 归一化：** `normalizeBackendDownloadURL()` 将后端返回的 localhost 下载地址替换为实际后端域名
- **Cookie 持久化：** iOS 用 `CookieStore`（UserDefaults），Android 用 `CookieStore`（SharedPreferences）
- **相册权限：** 通过构建设置 `INFOPLIST_KEY_NSPhotoLibrary*` 注入，不是独立的 Info.plist 文件
- **网络重试：** iOS 端大文件下载支持断点续传和不稳定网络重试
- **Xcode 16+ 文件同步：** 使用 `PBXFileSystemSynchronizedRootGroup`，新增 Swift 文件无需手动添加到 project.pbxproj
- **页面结构会变化：** 各平台解析逻辑需要跟进前端变更，调试时用 `curl -L <url> -H 'User-Agent: Mozilla/5.0 (iPhone; ...)'` 抓取页面检查结构

## 依赖

- **iOS 端：** 零第三方依赖，仅使用系统框架（SwiftUI, Foundation, Photos, AVKit, UIKit）
- **Android 端：** OkHttp, kotlinx.serialization, Jetpack Compose, Media3 ExoPlayer
- **Flutter 端：** http, cupertino_http, provider, photo_manager, video_player, path_provider, shared_preferences, share_plus, photo_view, permission_handler
- **Backend：** fastapi + httpx + pydantic
