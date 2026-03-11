# DouyinDownLoad

多平台短视频 / 图文无水印下载工具，当前仓库包含 **iOS / Android / Flutter / React Native / Python backend** 五端实现。

客户端能力对齐方向：

- iOS：SwiftUI + MVVM + Actor
- Android：Jetpack Compose + MVVM
- Flutter：Provider + MVVM，作为跨平台主线客户端
- React Native：用于补充 RN 技术栈验证与 Android / iOS 联调
- Backend：FastAPI 解析与下载代理

## 支持平台

| 平台 | 链接格式 | 视频 | 图文 | 需要 Cookie |
|------|---------|------|------|-------------|
| 抖音 | `v.douyin.com` / `www.douyin.com/video/` | ✅ | ✅ | 否 |
| TikTok | `vm.tiktok.com` / `www.tiktok.com/@user/video/` | ✅ | ❌ | 否 |
| Instagram | `instagram.com/reel/` / `/p/` / `/tv/` | ✅ | ✅ | 是 |
| X (Twitter) | `x.com/<user>/status/<id>` / `twitter.com/...` | ✅ | ✅ | 是 |
| B站 | `b23.tv` / `www.bilibili.com/video/` | ✅ | ❌ | 否 |
| 快手 | `v.kuaishou.com` / `www.kuaishou.com/short-video/` | ✅ | ✅ | 否 |
| 小红书 | `xhslink.com` / `www.xiaohongshu.com/explore/` | ✅ | ✅ | 否 |

## 项目结构

```text
.
├── ios/                   # iOS App（SwiftUI）
├── android/               # Android App（Jetpack Compose）
├── flutter/               # Flutter 客户端
├── react-native/          # React Native 客户端
├── backend/               # FastAPI backend
├── scripts/               # 工具脚本（如 Android 图标生成）
├── CLAUDE.md
├── AGENTS.md
└── README.md
```

## 本地解析能力

| 平台 | iOS 本地 | Android 本地 | Flutter 本地 | React Native 本地 | Backend |
|------|---------|-------------|-------------|-------------------|---------|
| 抖音 | ✅ local-first | ✅ local-first | ✅ local-first | ✅ local-first | ✅ |
| 小红书 | ✅ local-first | ✅ local-first | ✅ local-first | ✅ local-first | ✅ |
| 快手 | ✅ local-first | ✅ local-first | ✅ local-first | ✅ local-first | ✅ |
| Instagram | ✅ local-only | ✅ local-only | ✅ local-only | ✅ local-only | ✅ |
| X (Twitter) | ✅ local-only | ✅ local-only | ✅ local-only | ✅ local-only | ✅ |
| TikTok | ❌ backend-only | ❌ backend-only | ❌ backend-only | ❌ backend-only | ✅ |
| B站 | ❌ backend-only | ❌ backend-only | ❌ backend-only | ❌ backend-only | ✅ |

## 环境要求

### 通用

- macOS
- Xcode 16+
- Android Studio / Android SDK
- Python 3.11+

### Flutter 客户端

- Flutter `3.41+`
- Dart `3.11+`

### React Native 客户端

- Node.js `20+`
- npm `10+`
- JDK `17`
- Watchman
- CocoaPods `1.10+`

### Android SDK 建议版本

- Android SDK Platform `36`
- Android Build-Tools `36.1.0`
- Android NDK `27.0.12077973`

## 快速开始

```bash
git clone https://github.com/mhqamx/videoPick.git
cd videoPick
```

## Backend 启动

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

快速验证：

```bash
curl http://127.0.0.1:8000/health
curl -X POST http://127.0.0.1:8000/resolve \
  -H 'Content-Type: application/json' \
  -d '{"text":"https://v.douyin.com/xxx/"}'
```

## Flutter 客户端

### 初始化

```bash
cd flutter
flutter pub get
```

### 运行

```bash
flutter run
flutter run --release
```

### Android 打包

```bash
flutter build apk --debug
flutter build apk --release
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

说明：

- `app-release.apk` 默认可能是通用包
- `--target-platform android-arm64 --split-per-abi` 可生成仅真机 `arm64` 的 Android release 包

## React Native 客户端

### 初始化

```bash
cd react-native
npm install
```

### Metro

```bash
cd react-native
npm start
```

### Android 环境变量

```bash
export JAVA_HOME=/Users/<your-name>/Library/Java/JavaVirtualMachines/jbr-17.0.14/Contents/Home
export ANDROID_HOME=$HOME/Library/Android/sdk
export ANDROID_SDK_ROOT=$HOME/Library/Android/sdk
```

### Android 运行

```bash
cd react-native
adb reverse tcp:8081 tcp:8081
npx react-native run-android
```

### Android 打包

```bash
cd react-native/android
./gradlew assembleDebug
./gradlew assembleRelease -PreactNativeArchitectures=arm64-v8a
```

说明：

- `reactNativeArchitectures` 可用于限制输出 ABI
- `assembleRelease -PreactNativeArchitectures=arm64-v8a` 生成仅真机 `arm64` 的 RN Android release 包
- 当前工程已对齐 `Build-Tools 36.1.0` 与 `NDK 27.0.12077973`

### iOS 初始化

```bash
cd react-native/ios
pod install
```

## 原生 iOS 客户端

```bash
open ios/DouyinDownLoad.xcodeproj
```

## 原生 Android 客户端

```bash
cd android
./gradlew assembleDebug
```

## Cookie 配置

Instagram 和 X 需要在客户端 Cookie 设置页填入认证信息。

Backend 也支持读取 cookie 文件：

- Instagram：`backend/cookies/www.instagram.com_cookies.txt`
- X：`backend/cookies/x.com_cookies.txt`

可通过环境变量覆盖：

```bash
export INSTAGRAM_COOKIE_FILE="path/to/instagram_cookies.txt"
export X_COOKIE_FILE="path/to/x_cookies.txt"
```

## 当前新增内容

- 新增 `react-native/` 客户端工程，补齐 Android / iOS 双端基础结构
- README 补充 Flutter 与 React Native 的环境搭建说明
- Android 图标资源同步到 Flutter 与 React Native 工程
- 保留原生 iOS / Android 与 Flutter / Backend 的既有结构

## 架构说明

- iOS：SwiftUI + Foundation + Photos，`DouyinDownloadService` 使用 actor 隔离
- Android：OkHttp + kotlinx.serialization + Compose + Media3 ExoPlayer
- Flutter：Provider + `cupertino_http` + `photo_manager`
- React Native：React Navigation + AsyncStorage + CameraRoll + RNFS + Video
- Backend：FastAPI + httpx + pydantic，提供 `/resolve` 与 `/download`

更细的实现说明见 [CLAUDE.md](./CLAUDE.md) 与 [AGENTS.md](./AGENTS.md)。

## 已知限制

- TikTok / B站 仍依赖 backend 解析
- B站当前仅支持可直接下载的 MP4，DASH 分离流可能失败
- 各平台页面结构会变化，解析逻辑需要持续跟进
- React Native iOS 端首次运行前需要先执行 `pod install`

## 合规说明

下载内容请仅用于个人学习与测试，遵守平台规则与相关法律法规。
