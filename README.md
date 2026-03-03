# DouyinDownLoad

iOS 短视频下载 Demo，当前采用”iOS 客户端 + Python backend 解析代理”的模式。

## 支持平台

- **抖音** — `v.douyin.com` 短链 / `www.douyin.com/video/` 长链
- **快手** — `v.kuaishou.com` 短链 / `www.kuaishou.com/short-video/` 长链

## 当前状态
- iOS 端可粘贴分享文案并下载视频（抖音、快手）
- backend 提供 `/resolve` + `/download` 接口，自动识别平台
- 支持 Codespaces 公网地址对接
- backend 采用可扩展 extractor 插件架构，新增平台只需后端添加 Extractor

## 项目结构

```text
DouyinDownLoad/
├── DouyinDownLoad/                      # iOS App
│   ├── Models/
│   ├── Services/
│   ├── ViewModels/
│   └── Views/
├── DouyinDownLoad.xcodeproj/
├── backend/                             # Python 解析/下载代理服务
│   ├── app/
│   │   ├── extractors/
│   │   ├── local_resolver.py
│   │   └── main.py
│   └── README.md
└── README.md
```

## iOS 侧说明

核心服务：`DouyinDownloadService`

主要流程：
1. 从分享文案提取 URL
2. 优先调用 backend `/resolve`
3. backend 返回 `download_url` 后执行下载
4. 下载成功后可保存到相册
5. backend 不可用时，回退到本地解析流程

关键文件：
- `DouyinDownLoad/Services/DouyinDownloadService.swift`
- `DouyinDownLoad/ViewModels/DouyinDownloadViewModel.swift`
- `DouyinDownLoad/Views/DouyinDownloadView.swift`

## 相册权限

项目已在构建配置中加入：
- `NSPhotoLibraryAddUsageDescription`
- `NSPhotoLibraryUsageDescription`

如你修改了 Target/Info 生成方式，请确保这两个键仍存在。

## 快速运行

### 1) 启动 backend

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

### 2) 运行 iOS

```bash
open DouyinDownLoad.xcodeproj
```

选择模拟器或真机，`Cmd + R`。

## Codespaces 对接要点

- backend 端口 `8000` 需要设为 `Public`
- 使用类似 `https://<name>-8000.app.github.dev` 的地址
- 注意：某些代理环境下 backend 可能返回 `localhost` 下载地址，iOS 端已做域名归一化处理（替换为当前 backend 域名）

## 已知问题

- 抖音/快手页面结构会随时间变化，个别视频可能出现 403/404
- 不同网络环境下成功率不同
- 如果遇到失败，请优先查看 `DouyinDownloadService` 日志

## 合规说明

下载内容请仅用于个人学习与测试，遵守平台规则与相关法律法规。
