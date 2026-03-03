# DouyinDownLoad

<div align="center">

![Platform](https://img.shields.io/badge/Platform-iOS%2015.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.7-orange.svg)
![Xcode](https://img.shields.io/badge/Xcode-13.0+-brightgreen.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

**iOS 无水印抖音视频下载工具**

从抖音分享链接提取并下载无水印视频，保存到相册。

[功能特性](#功能特性) • [项目结构](#项目结构) • [快速开始](#快速开始) • [使用说明](#使用说明) • [技术栈](#技术栈)

</div>

---

## 功能特性

| 特性 | 状态 |
|------|------|
| 从分享链接提取视频 URL | ✅ |
| 解析短链接获取视频信息（去水印） | ✅ |
| 下载视频到本地存储 | ✅ |
| 保存视频到相册 | ✅ |
| 视频预览播放 | ✅ |
| 友好的用户界面 | ✅ |
| 剪贴板一键粘贴 | ✅ |
| 错误提示与处理 | ✅ |

## 项目结构

```
DouyinDownLoad/
├── DouyinDownLoad/
│   ├── DouyinDownLoadApp.swift      # App 入口
│   ├── ContentView.swift             # 应用入口视图
│   ├── Models/
│   │   ├── DouyinVideoInfo.swift    # 视频信息数据模型
│   │   └── DouyinDownloadError.swift # 错误类型定义
│   ├── Services/
│   │   └── DouyinDownloadService.swift # 核心下载服务 (Actor)
│   ├── ViewModels/
│   │   └── DouyinDownloadViewModel.swift # UI 状态管理
│   ├── Views/
│   │   └── DouyinDownloadView.swift  # 主界面视图
│   └── Assets.xcassets/              # 资源文件
├── DouyinDownLoad.xcodeproj/         # Xcode 项目文件
├── README.md                         # 项目说明文档
├── BUILD_REPORT.md                   # 构建报告
└── BUGFIX.md                         # 问题修复记录
```

## 快速开始

### 环境要求

- iOS 15.0+
- Swift 5.7+
- Xcode 13.0+

### 配置步骤

#### 1. 打开项目

```bash
open DouyinDownLoad.xcodeproj
```

#### 2. 配置相册权限

在 Xcode 中配置相册访问权限：

**方式一：通过 Info 标签页**
1. 选择项目 Target: `DouyinDownLoad`
2. 进入 `Info` 标签页
3. 添加 `Privacy - Photo Library Additions Usage Description`
   - 值: `需要访问您的相册以保存下载的视频`
4. 添加 `Privacy - Photo Library Usage Description`
   - 值: `需要访问您的相册以保存下载的视频`

**方式二：编辑 Info.plist**
```xml
<key>NSPhotoLibraryAddUsageDescription</key>
<string>需要访问您的相册以保存下载的视频</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>需要访问您的相册以保存下载的视频</string>
```

#### 3. 构建运行

1. 选择目标设备或模拟器
2. 按 `Cmd + R` 运行项目

## 使用说明

### 基本使用

1. 打开抖音 App，找到想要下载的视频
2. 点击分享按钮 → 选择"复制链接"
3. 打开本 App
4. 点击"粘贴"按钮（或手动粘贴）
5. 点击"下载"按钮
6. 等待下载完成
7. 点击"保存到相册"

### 支持的链接格式

- 短链接: `https://v.douyin.com/xxx/`
- 长链接: `https://www.douyin.com/video/1234567890`
- 分享文本: `在抖音,记录美好生活! https://v.douyin.com/xxx/ 复制此链接`

## 代码使用示例

### 方式一：使用完整 UI 组件（推荐）

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        DouyinDownloadView()
    }
}
```

### 方式二：自定义 UI + ViewModel

```swift
import SwiftUI

struct MyCustomView: View {
    @StateObject private var viewModel = DouyinDownloadViewModel()

    var body: some View {
        VStack {
            TextField("抖音链接", text: $viewModel.inputText)

            Button("下载") {
                viewModel.processInput()
            }

            if viewModel.isLoading {
                ProgressView()
            }

            if let error = viewModel.errorMessage {
                Text(error).foregroundColor(.red)
            }

            if let videoInfo = viewModel.videoInfo {
                Text("标题: \(videoInfo.title ?? "无标题")")

                Button("保存到相册") {
                    Task { await viewModel.saveToAlbum() }
                }
            }
        }
    }
}
```

### 方式三：仅使用核心服务

```swift
import Foundation

Task {
    do {
        let service = DouyinDownloadService.shared
        let videoInfo = try await service.parseAndDownload(shareText)

        if let localURL = videoInfo.localURL {
            try await service.saveToAlbum(videoURL: localURL)
            print("保存成功!")
        }
    } catch let error as DouyinDownloadError {
        print("错误: \(error.errorDescription ?? "")")
    }
}
```

## 核心组件说明

### DouyinDownloadService (Actor)

线程安全的下载服务，主要方法：

| 方法 | 描述 |
|------|------|
| `parseAndDownload(_ text: String)` | 一步完成解析和下载 |
| `saveToAlbum(videoURL: URL)` | 保存到相册 |
| `extractURL(from: String)` | 从文本提取 URL |
| `resolveDouyinShortURL(_ url: URL)` | 解析短链接 |
| `downloadVideo(from: URL, id: String)` | 下载视频 |

### DouyinDownloadViewModel (@MainActor)

UI 状态管理器，发布属性：

| 属性 | 类型 | 描述 |
|------|------|------|
| `inputText` | String | 输入文本 |
| `isLoading` | Bool | 加载状态 |
| `errorMessage` | String? | 错误信息 |
| `videoInfo` | DouyinVideoInfo? | 视频信息 |
| `saveResult` | String? | 保存结果 |
| `showPreview` | Bool | 显示预览 |

### DouyinVideoInfo

```swift
struct DouyinVideoInfo {
    let id: String              // 视频 ID
    let downloadURL: URL        // 下载链接
    var localURL: URL?          // 本地文件路径
    let title: String?          // 视频标题
    let coverURL: String?       // 封面图链接
}
```

### DouyinDownloadError

```swift
enum DouyinDownloadError: LocalizedError {
    case invalidURL              // 未找到有效链接
    case urlResolutionFailed     // 链接解析失败
    case videoDataNotFound       // 未找到视频数据
    case downloadFailed(statusCode: Int) // 下载失败
    case noVideoLinkFound        // 未找到视频链接
    case invalidVideoLink        // 无效视频链接
    case saveToAlbumFailed(reason: String) // 保存失败
    case noPermission            // 无相册权限
}
```

## 技术栈

- **SwiftUI** - 用户界面
- **Combine** - 响应式编程
- **Swift Concurrency** (async/await, Actor) - 异步编程
- **URLSession** - 网络请求
- **Photos Framework** - 相册操作
- **AVKit** - 视频播放

## 常见问题

### Q: 无法保存到相册

**A:** 未配置相册权限。请按照配置步骤在 Info 中添加相册权限说明。

### Q: 下载失败

**可能原因:**
- 网络连接问题
- 链接已过期
- 抖音 API 变更

**解决:**
- 检查网络连接
- 尝试获取新的分享链接
- 更新解析逻辑

### Q: 无法解析链接

**A:** 链接格式不正确或 HTML 解析失败。请确保复制完整的抖音分享链接。

### Q: 构建错误

**A:** 文件未正确添加到项目。
1. 清理构建文件夹 (Cmd + Shift + K)
2. 重新添加文件到项目
3. 确保文件在正确的 Target 中

## 注意事项

⚠️ **重要提醒:**

1. **版权声明**: 下载的视频仅供个人学习和研究使用，请勿用于商业用途
2. **隐私保护**: 尊重视频创作者的版权和隐私
3. **网络安全**: 生产环境应配置具体的网络安全策略
4. **API 稳定性**: 抖音可能随时调整接口，需要及时更新解析逻辑
5. **存储空间**: 下载的视频会占用设备存储空间

## 更新日志

### v1.0.0 (2026/2/2)

- 初始版本发布
- 支持无水印视频下载
- 支持保存到相册
- 友好的 SwiftUI 界面
- 完整的错误处理

## License

MIT License

## 作者

**马霄**

- GitHub: [@maxiao](https://github.com/maxiao)
- Email: 开发者邮箱

---

<div align="center">

**如果这个项目对你有帮助，欢迎 Star ⭐️**

</div>
