# DouyinDownLoad

多平台短视频/图文无水印下载工具，采用 **iOS/Android/Flutter 客户端 + Python backend 解析代理** 四端架构。

## 支持平台

| 平台 | 链接格式 | 视频 | 图文 | 需要 Cookie |
|------|---------|------|------|-------------|
| **抖音** | `v.douyin.com` 短链 / `www.douyin.com/video/` 长链 | ✅ | ✅ | 否 |
| **TikTok** | `vm.tiktok.com` / `www.tiktok.com/@user/video/` | ✅ | ❌ | 否 |
| **Instagram** | `instagram.com/reel/` / `/p/` / `/tv/` | ✅ | ✅ | 是 |
| **X (Twitter)** | `x.com/<user>/status/<id>` / `twitter.com/...` | ✅ | ✅ | 是 |
| **B站** | `b23.tv` 短链 / `www.bilibili.com/video/` | ✅ | ❌ | 否 |
| **快手** | `v.kuaishou.com` 短链 / `www.kuaishou.com/short-video/` | ✅ | ✅ | 否 |
| **小红书** | `xhslink.com` 短链 / `www.xiaohongshu.com/explore/` | ✅ | ✅ | 否 |

### 本地解析能力

| 平台 | iOS 本地 | Android 本地 | Flutter 本地 | Backend |
|------|---------|-------------|-------------|---------|
| 抖音 | ✅ local-first | ✅ local-first | ✅ local-first | ✅ |
| 小红书 | ✅ local-first | ✅ local-first | ✅ local-first | ✅ |
| 快手 | ✅ local-first | ✅ local-first | ✅ local-first | ✅ |
| Instagram | ✅ local-only | ✅ local-only | ✅ local-only | ✅ |
| X (Twitter) | ✅ local-only | ✅ local-only | ✅ local-only | ✅ |
| TikTok | ❌ backend-only | ❌ backend-only | ❌ backend-only | ✅ |
| B站 | ❌ backend-only | ❌ backend-only | ❌ backend-only | ✅ |

## 项目结构

```text
.
├── ios/                                 # iOS App (SwiftUI, MVVM + Actor)
│   ├── DouyinDownLoad.xcodeproj/
│   └── DouyinDownLoad/
│       ├── Models/
│       ├── Services/
│       ├── ViewModels/
│       └── Views/
├── android/                             # Android App (Jetpack Compose + MVVM)
│   └── app/src/main/java/com/demo/videopick/
├── flutter/                             # Flutter App (Provider + MVVM, 跨平台)
│   └── lib/
│       ├── models/
│       ├── services/
│       ├── viewmodels/
│       ├── views/
│       ├── widgets/
│       └── main.dart
├── backend/                             # Python 解析/下载代理服务 (FastAPI)
│   ├── app/
│   │   ├── extractors/                  # 各平台解析插件
│   │   ├── local_resolver.py
│   │   └── main.py
│   └── tests/
├── CLAUDE.md                            # Claude Code 开发指南
└── README.md
```

## 快速开始

```bash
git clone https://github.com/mhqamx/videoPick.git
cd videoPick
```

### 1) 启动 backend

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

### 2) 运行 Flutter（跨平台）

```bash
cd flutter
flutter pub get
flutter run              # debug 模式
flutter run --release    # release 模式（脱机使用）
```

### 3) 运行 iOS

```bash
open ios/DouyinDownLoad.xcodeproj
```

选择模拟器或真机，`Cmd + R`。

### 4) 运行 Android

```bash
cd android
./gradlew assembleDebug
```

## Cookie 配置

Instagram 和 X 需要用户在客户端 **Cookie 设置页面** 填入认证信息。

Backend 也支持通过 cookie 文件配置：

- **Instagram**: `backend/cookies/www.instagram.com_cookies.txt`（需包含 `sessionid`）
- **X**: `backend/cookies/x.com_cookies.txt`（需包含 `auth_token` 和 `ct0`）

可通过环境变量覆盖路径：

```bash
export INSTAGRAM_COOKIE_FILE="path/to/cookies.txt"
export X_COOKIE_FILE="path/to/cookies.txt"
```

## 架构说明

- **iOS 端**: 零第三方依赖，仅 SwiftUI + Foundation + Photos。`DouyinDownloadService` 为 actor，保证线程安全
- **Android 端**: OkHttp + kotlinx.serialization + Jetpack Compose + Media3 ExoPlayer
- **Flutter 端**: Provider + cupertino_http（iOS 原生网络栈）+ photo_manager。与 iOS/Android 对等的本地解析能力
- **Backend**: FastAPI + httpx + pydantic，可扩展 Extractor 插件架构。`/resolve` 解析 + `/download` 代理下载

详细架构和实现细节参见 [CLAUDE.md](CLAUDE.md)。

## Codespaces 对接

- backend 端口 `8000` 需要设为 `Public`
- 使用 `https://<name>-8000.app.github.dev` 地址
- iOS/Android 端已做 localhost 归一化处理

## 已知限制

- TikTok/B站 完全依赖 backend，无 backend 时不可用（所有客户端均适用）
- B站当前仅支持可直接下载的 MP4；DASH 分离流可能解析失败
- 各平台页面结构会随时间变化，个别内容可能出现 403/404

## 合规说明

下载内容请仅用于个人学习与测试，遵守平台规则与相关法律法规。
