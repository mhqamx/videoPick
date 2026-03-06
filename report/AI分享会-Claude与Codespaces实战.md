# AI 辅助开发实战：Claude Code + GitHub Codespaces

> 以"短视频下载工具"为例，展示 AI 如何改变个人开发者的工作方式

---

## 自我介绍 & 开场

大家好，今天分享一个我最近的实践：**用 AI 工具从零搭建一个完整的全栈项目**。

不是 Demo 级别的 HelloWorld，而是一个真正可用的工具——支持抖音、快手、B站、小红书等多平台视频下载，包含 iOS 客户端 + Python 后端，前后端配合，从想法到落地全程由 AI 辅助完成。

---

## Part 1: 工具介绍

### Claude Code —— AI 编程助手

- Anthropic 官方 CLI 工具，运行在终端里
- 能理解整个项目上下文，不只是单个文件
- 核心能力：
  - **读写代码**：直接创建、修改项目文件
  - **执行命令**：运行 build、test、curl 等 shell 命令
  - **多文件协作**：跨文件理解架构，保持一致性
  - **CLAUDE.md**：项目级记忆文件，告诉 AI "这个项目是什么、怎么构建、有什么注意事项"

### GitHub Codespaces —— 云端开发环境

- 一键启动的云端 VS Code / 终端环境
- 自带公网 URL，手机可以直接访问
- 对这个项目的意义：
  - iOS 客户端在本地 Xcode 开发
  - Python 后端部署在 Codespaces，提供公网 API
  - **手机上的 App 可以直接调后端**，不需要内网穿透

---

## Part 2: 项目架构

```
┌─────────────────────────────────────────────┐
│                  用户手机                      │
│           DouyinDownLoad iOS App              │
│        (SwiftUI + MVVM + Actor 并发)          │
└───────────────┬─────────────────────────────┘
                │ HTTPS
                ▼
┌─────────────────────────────────────────────┐
│        GitHub Codespaces (Python Backend)     │
│              FastAPI + httpx                  │
│                                               │
│  ┌──────────────────────────────────────┐    │
│  │        ExtractorRegistry              │    │
│  │  ┌─────────┐ ┌─────────┐ ┌────────┐ │    │
│  │  │  抖音    │ │  快手   │ │  B站   │  │    │
│  │  └─────────┘ └─────────┘ └────────┘ │    │
│  │  ┌───────────┐                       │    │
│  │  │  小红书    │                       │    │
│  │  └───────────┘                       │    │
│  └──────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
```

### 关键设计

| 设计点 | 说明 |
|--------|------|
| 双模式架构 | 优先调后端 API，后端不可用时回退到本地 HTML 解析 |
| 代理下载 | 后端返回自身 `/download?source=...` 代理地址，避免移动端被 CDN 封锁 |
| 插件化 Extractor | 新增平台只需实现一个 `VideoExtractor` Protocol，注册即可 |
| 零第三方依赖 (iOS) | 纯 SwiftUI + Foundation + Photos，无 CocoaPods/SPM 依赖 |

---

## Part 3: Claude Code 实战演示

### 3.1 CLAUDE.md —— 给 AI 的项目说明书

```markdown
# CLAUDE.md
## 项目概述
iOS 抖音视频下载 Demo，采用"iOS 客户端 + Python backend 解析代理"双模式架构...

## 常用命令
### iOS 构建
xcodebuild -project DouyinDownLoad.xcodeproj ...

### Python Backend
uvicorn app.main:app --host 0.0.0.0 --port 8000

## 架构
DouyinDownLoadApp (@main)
  → ContentView → DouyinDownloadView (SwiftUI)
    → DouyinDownloadViewModel
      → DouyinDownloadService (actor)
```

**为什么重要？**
- AI 每次对话都会读取这个文件，保证上下文一致
- 新成员（或未来的自己）也能快速理解项目
- 等于把"口头知识"变成了"可版本控制的文档"

### 3.2 真实开发过程复盘

从 git log 看整个项目的演进：

```
f3367d5 Initial commit
0898743 feat: upload DouyinDownLoad app and backend resolver
ad89748 docs: refresh app and backend readme
db0ec82 feat(backend): add Kuaishou video download support
0212f3c feat(backend): add XiaoHongShu video download support
8900cc5 feat(backend): add bilibili b23/video extractor and docs
b86bc86 fix(backend): handle bilibili 412 by canonicalizing video url
46b7e3d fix(backend): correct b23 redirect url joining
2edda3d fix(backend): fallback to bilibili open api when web page blocked
```

**值得注意的几点：**

1. **从单平台到多平台**：最初只支持抖音，后来逐步扩展到快手、小红书、B站
2. **Bug 修复很真实**：B站的 412 反爬、b23 短链重定向、网页被封后的 API 回退——这些都是实际遇到的问题，AI 帮助快速定位和修复
3. **提交信息规范**：`feat/fix/docs/refactor` 前缀，Claude 自动遵循 Conventional Commits

### 3.3 现场演示（Live Demo）

> 以下根据实际演示情况选择

- **场景 A**：让 Claude 新增一个平台的 Extractor（展示插件化架构）
- **场景 B**：让 Claude 修一个 Bug（展示调试能力）
- **场景 C**：让 Claude 重构一段代码（展示对项目的理解深度）

---

## Part 4: GitHub Codespaces 实战

### 4.1 为什么用 Codespaces？

传统方案的痛点：
- 本地跑后端 → 手机访问不了（需要内网穿透）
- 买服务器部署 → 成本高、维护麻烦
- ngrok 等工具 → 不稳定、有限制

Codespaces 的优势：
- **一键启动**：`gh codespace create` 即可
- **自带公网 URL**：`xxx-8000.app.github.dev`，手机直连
- **免费额度**：个人用户每月 120 核心小时
- **环境一致**：开发、测试、演示用同一套环境

### 4.2 使用流程

```bash
# 1. 创建 Codespace
gh codespace create -r your-repo -b main

# 2. 进入 Codespace 终端
gh codespace ssh

# 3. 启动后端
cd backend
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000

# 4. 端口自动转发，获得公网 URL
# https://xxx-8000.app.github.dev

# 5. iOS App 配置后端地址，手机直接调用
```

### 4.3 与 Claude Code 的配合

在 Codespace 里可以直接使用 Claude Code：
- 远程调试后端问题
- 在云端环境中测试 API
- 同步代码改动到 GitHub

---

## Part 5: 经验总结

### AI 辅助开发的正确姿势

| 做法 | 效果 |
|------|------|
| 维护 CLAUDE.md | AI 理解项目更准确，减少"幻觉" |
| 明确描述需求 | "添加 B 站视频下载支持，参考现有 Extractor 架构" 比 "帮我加个功能" 好 10 倍 |
| 分步迭代 | 先跑通核心流程，再逐步完善错误处理和边界情况 |
| 人工审查 | AI 写的代码一定要 review，特别是安全相关逻辑 |
| 让 AI 写测试 | 单元测试是 AI 最擅长的场景之一 |

### AI 不擅长什么？

- 需要实际运行才能发现的问题（如抖音反爬策略变化）
- 高度依赖领域知识的决策（如 App 交互设计）
- 需要反复调试的网络问题（如 CDN 封锁策略）

### 效率提升体感

- **新增一个平台支持**（Extractor + 测试 + 文档）：从数小时 → ~30 分钟
- **Bug 修复**：AI 快速定位问题模式，人工确认方案
- **代码质量**：commit message、错误处理、架构一致性都有保障

---

## Part 6: 延伸思考

1. **CLAUDE.md 是不是新的 README？** —— 它既是给 AI 的，也是给人的
2. **Codespaces 适合什么场景？** —— 个人项目、Demo 演示、临时环境、教学
3. **AI 会取代程序员吗？** —— 不会，但会取代不用 AI 的程序员（开玩笑）
4. **下一步可以做什么？** —— CI/CD 集成、自动化测试、更多平台支持

---

## Q&A

欢迎提问！

---

## 附录：项目文件结构

```
DouyinDownLoad/
├── CLAUDE.md                          # AI 项目说明书
├── DouyinDownLoad/
│   ├── DouyinDownLoadApp.swift        # App 入口
│   ├── ContentView.swift              # 根视图
│   ├── Models/
│   │   ├── DouyinVideoInfo.swift      # 视频信息模型
│   │   └── DouyinDownloadError.swift  # 错误类型定义
│   ├── ViewModels/
│   │   └── DouyinDownloadViewModel.swift  # 业务逻辑
│   ├── Views/
│   │   └── DouyinDownloadView.swift   # 主界面
│   └── Services/
│       └── DouyinDownloadService.swift # 核心下载服务 (actor)
├── backend/
│   ├── app/
│   │   ├── main.py                    # FastAPI 入口
│   │   ├── models.py                  # Pydantic 模型
│   │   ├── local_resolver.py          # 本地解析器
│   │   └── extractors/               # 平台解析插件
│   │       ├── base.py                # VideoExtractor Protocol
│   │       ├── registry.py            # 注册中心
│   │       ├── douyin.py              # 抖音
│   │       ├── kuaishou.py            # 快手
│   │       ├── xiaohongshu.py         # 小红书
│   │       └── bilibili.py            # B站
│   └── tests/                         # 单元测试
```
