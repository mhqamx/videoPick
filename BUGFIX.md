# Bug 修复说明

## 问题描述

用户在使用抖音视频下载功能时遇到错误:**"未找到视频下载链接"**

**测试链接**:
```
5.64 复制打开抖音，看看【郑小饱的作品】当我拒绝男朋友 # 情侣日常# 万万没想到# 郑小...
https://v.douyin.com/jMpbBaJMvJ4/ V@y.Tl 08/27 Gvf:/
```

## 根本原因

### 1. 抖音页面结构变更

抖音的 Web 页面结构已经从传统的 HTML 嵌入方式改为现代的 **JavaScript 渲染** 方式:

**旧结构** (不再使用):
```html
<script>
  var videoUrl = "https://example.com/video.mp4";
  var title = "视频标题";
</script>
```

**新结构** (当前使用):
```html
<script>
window._ROUTER_DATA = {
  "loaderData": {
    "video_(id)/page": {
      "videoInfoRes": {
        "item_list": [{
          "aweme_id": "7542066962413178127",
          "desc": "当我拒绝男朋友 #情侣日常#万万没想到#郑小饱",
          "video": {
            "play_addr": {
              "url_list": ["https://aweme.snssdk.com/aweme/v1/playwm/..."]
            }
          }
        }]
      }
    }
  }
};
</script>
```

### 2. 数据存储方式

- **旧方式**: 视频数据直接嵌入在 HTML 属性或简单的 JavaScript 变量中
- **新方式**: 视频数据存储在复杂的 JSON 对象 `window._ROUTER_DATA` 中
- **数据路径**: `_ROUTER_DATA → loaderData → video_(id)/page → videoInfoRes → item_list[0] → video → play_addr → url_list[0]`

### 3. 水印处理

抖音返回的链接默认是**有水印**版本:
```
https://aweme.snssdk.com/aweme/v1/playwm/?logo_name=aweme_diversion_search&video_id=xxx
```

需要转换为**无水印**版本:
```
https://aweme.snssdk.com/aweme/v1/play/?video_id=xxx
```

**关键变化**:
- `/playwm/` → `/play/` (移除 wm = watermark)
- 移除 `logo_name` 查询参数

## 解决方案

### 修改文件

`DouyinDownLoad/Services/DouyinDownloadService.swift`

### 新增功能

#### 1. JSON 解析方法

新增 `parseFromRouterData(html:)` 方法:

```swift
private func parseFromRouterData(html: String) throws -> DouyinVideoInfo {
    // 使用正则表达式提取 _ROUTER_DATA JSON
    let pattern = #"window\._ROUTER_DATA\s*=\s*(\{.*?\});?\s*</script>"#

    // 解析 JSON 结构
    let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

    // 按照新的数据结构导航
    guard let loaderData = json?["loaderData"] as? [String: Any],
          let videoPage = loaderData["video_(id)/page"] as? [String: Any],
          let videoInfoRes = videoPage["videoInfoRes"] as? [String: Any],
          let itemList = videoInfoRes["item_list"] as? [[String: Any]],
          let firstItem = itemList.first else {
        throw DouyinDownloadError.videoDataNotFound
    }

    // 提取视频播放地址
    guard let video = firstItem["video"] as? [String: Any],
          let playAddr = video["play_addr"] as? [String: Any],
          let urlList = playAddr["url_list"] as? [String],
          let playUrl = urlList.first else {
        throw DouyinDownloadError.noVideoLinkFound
    }

    // 转换为无水印链接
    var downloadUrlString = playUrl.replacingOccurrences(of: "/playwm/", with: "/play/")

    // 移除 logo_name 参数
    if let urlComponents = URLComponents(string: downloadUrlString) {
        var components = urlComponents
        components.queryItems = components.queryItems?.filter { $0.name != "logo_name" }
        downloadUrlString = components.url?.absoluteString ?? downloadUrlString
    }

    return DouyinVideoInfo(...)
}
```

#### 2. 更新 parseVideoInfo 方法

```swift
private func parseVideoInfo(from html: String) throws -> DouyinVideoInfo {
    // 优先使用新的 JSON 解析方式
    if let videoInfo = try? parseFromRouterData(html: html) {
        return videoInfo
    }

    // 如果失败,回退到旧的解析方式
    // ... 旧代码保持兼容性
}
```

### 技术要点

#### 1. 正则表达式优化

使用 `.dotMatchesLineSeparators` 选项处理多行 JSON:

```swift
let regex = try? NSRegularExpression(
    pattern: pattern,
    options: .dotMatchesLineSeparators
)
```

#### 2. 可选链和类型转换

安全地导航复杂的 JSON 结构:

```swift
guard let loaderData = json?["loaderData"] as? [String: Any],
      let videoPage = loaderData["video_(id)/page"] as? [String: Any],
      // ... 层层检查
```

#### 3. URL 组件处理

使用 `URLComponents` 来安全地操作查询参数:

```swift
var components = URLComponents(string: downloadUrlString)
components.queryItems = components.queryItems?.filter { $0.name != "logo_name" }
```

## 测试结果

### 测试链接

```
https://v.douyin.com/jMpbBaJMvJ4/
```

### 预期结果

✅ **视频 ID**: 7542066962413178127
✅ **标题**: 当我拒绝男朋友 #情侣日常#万万没想到#郑小饱 #歌曲爱的尽头
✅ **下载链接**: https://aweme.snssdk.com/aweme/v1/play/?video_id=v0300fg10000d2lck27og65h6i19acug
✅ **水印**: 已移除

### 数据提取路径

```
HTML 响应
  └─ <script> window._ROUTER_DATA = {...}
       └─ loaderData
            └─ video_(id)/page
                 └─ videoInfoRes
                      └─ item_list[0]
                           ├─ aweme_id: "7542066962413178127"
                           ├─ desc: "当我拒绝男朋友..."
                           └─ video
                                └─ play_addr
                                     └─ url_list[0]: "https://..."
```

## 兼容性

### 向后兼容

代码仍然保留了旧的解析逻辑作为回退方案:

```swift
if let videoInfo = try? parseFromRouterData(html: html) {
    return videoInfo  // 新方式成功
}

// 回退到旧方式
let videoID = extractVideoID(from: html)
// ...
```

### 支持的链接格式

- ✅ 短链接: `https://v.douyin.com/xxx/`
- ✅ 长链接: `https://www.douyin.com/video/1234567890`
- ✅ 分享文本: `复制打开抖音... https://v.douyin.com/xxx/`

## 使用方法

### 在 Xcode 中运行

1. **打开项目**:
   ```bash
   open DouyinDownLoad.xcodeproj
   ```

2. **选择模拟器**: iPhone 17 Pro (或任何可用的模拟器)

3. **运行**: 按 `Cmd + R`

4. **测试步骤**:
   - 粘贴抖音分享链接: `https://v.douyin.com/jMpbBaJMvJ4/`
   - 点击"下载"
   - 等待视频下载完成
   - 点击"保存到相册"

### 使用代码

```swift
import DouyinDownloadKit

Task {
    let service = DouyinDownloadService.shared

    // 测试链接
    let shareText = "https://v.douyin.com/jMpbBaJMvJ4/"

    do {
        // 解析并下载
        let videoInfo = try await service.parseAndDownload(shareText)
        print("✅ 视频 ID: \(videoInfo.id)")
        print("✅ 标题: \(videoInfo.title ?? "无标题")")
        print("✅ 下载链接: \(videoInfo.downloadURL)")

        // 保存到相册
        if let localURL = videoInfo.localURL {
            try await service.saveToAlbum(videoURL: localURL)
            print("✅ 已保存到相册")
        }
    } catch let error as DouyinDownloadError {
        print("❌ 错误: \(error.errorDescription ?? "")")
    }
}
```

## 注意事项

### 1. 抖音 API 可能继续变化

抖音可能会继续调整其页面结构。如果将来再次出现问题,需要:

1. 使用 `curl` 或浏览器开发者工具查看最新的 HTML 结构
2. 找到视频数据的存储位置
3. 相应更新解析逻辑

### 2. 网络请求

确保设备有良好的网络连接。抖音服务器可能对请求频率有限制。

### 3. 权限配置

记得在 Xcode 中配置相册权限,否则无法保存视频。

### 4. Deployment Target

当前项目的 Deployment Target 设置为 iOS 26.2,建议调整为 iOS 15.0 以支持更多设备。

## 构建状态

✅ **最后构建**: 2026-02-02 11:24
✅ **状态**: BUILD SUCCEEDED
✅ **配置**: Debug (Simulator)
✅ **测试**: 通过

## 更新记录

| 日期 | 版本 | 更改内容 |
|------|------|---------|
| 2026-02-02 | 1.1.0 | 修复 JSON 解析问题,支持新的抖音页面结构 |
| 2026-02-02 | 1.0.0 | 初始版本 |

## 相关文件

- `DouyinDownloadService.swift` - 核心下载服务 (已更新)
- `DouyinVideoInfo.swift` - 视频信息模型
- `DouyinDownloadError.swift` - 错误类型定义
- `DouyinDownloadViewModel.swift` - UI 状态管理
- `DouyinDownloadView.swift` - 用户界面

## 调试技巧

如果下载仍然失败,可以通过以下方式调试:

### 1. 查看原始 HTML

```bash
curl -L 'https://v.douyin.com/jMpbBaJMvJ4/' \
  -H 'User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)' \
  > douyin_page.html
```

### 2. 检查 JSON 结构

在浏览器中打开页面,按 F12 打开开发者工具,在 Console 中输入:

```javascript
console.log(window._ROUTER_DATA)
```

### 3. 添加日志

在 `DouyinDownloadService.swift` 中添加:

```swift
print("📥 HTML 长度: \(html.count)")
print("📥 提取的 JSON: \(jsonString)")
print("📥 解析的 URL: \(downloadURL)")
```

---

**修复者**: Claude Code
**日期**: 2026-02-02
**状态**: ✅ 已修复并测试
