# DouyinDownLoadSPMDemo

这是一个最小宿主 iOS App，用来把本地 Swift Package `../spm` 跑到模拟器或真机。

生成工程：

```bash
cd spm-demo-ios
xcodegen generate
```

打开工程：

```bash
open DouyinDownLoadSPMDemo.xcodeproj
```

命令行构建：

```bash
xcodebuild -project DouyinDownLoadSPMDemo.xcodeproj \
  -scheme DouyinDownLoadSPMDemo \
  -destination 'generic/platform=iOS Simulator' build
```

真机运行：

1. 用 Xcode 打开工程
2. 选择你的 iPhone
3. 检查 `Signing & Capabilities`
4. 点击 Run
