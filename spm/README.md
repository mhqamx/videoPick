# DouyinDownLoadSPM

`spm` 目录是一个用于学习的 Swift Package 版本，按 `ios/DouyinDownLoad` 的分层重写为：

- `Models`
- `Services`
- `ViewModels`
- `Views`

和 `ios` 工程的区别：

- Swift Package 只能提供库 target，不能像 `.xcodeproj` 一样直接作为 iOS App 入口运行。
- 这里暴露的是 `DouyinDownLoadPackageView`，方便在宿主 App 中直接集成。
- 原有的 SwiftUI、MVVM、`actor`、本地解析和 backend 回退逻辑都保留在包内。

接入方式示例：

```swift
import SwiftUI
import DouyinDownLoadSPM

@main
struct DemoHostApp: App {
    var body: some Scene {
        WindowGroup {
            DouyinDownLoadPackageView()
        }
    }
}
```
