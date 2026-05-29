# PRD · 无水印下载控制台 · Neo-Cyber 改版

> 版本：v1.0 · 改版分支 `feat/neo-cyber-redesign`
> 维护：iOS 端 ｜ 关联模块：ViewModel / Service / Settings

---

## 一、背景与目标

### 1.1 立项背景

现有 iOS 端"短视频无水印下载"功能视觉上偏系统默认风格，吸引力弱；下载流程存在"链接→点粘贴→点下载→点保存"四次手动操作，体验断点多。同时，旧版下载中状态只有一根线性进度条，缺乏沉浸感与情绪反馈。

### 1.2 北极星指标

| 指标 | 现状（估算） | 目标 | 抓手 |
|------|-------------|------|------|
| 首次下载完成时长（自启动起） | ~12s | ≤ 4s | 自动粘贴 + 自动下载 + 自动保存 |
| 下载流程平均点击次数 | 4 次 | ≤ 1 次（极致 0 次） | 全链路自动化 + 自动保存开关 |
| 视觉满意度（主观） | 6/10 | 9/10 | Neo-Cyber 设计语言 + 动效闭环 |
| Loading 卡顿率 | 偶发掉帧 | 60fps 稳定 | Canvas 离屏 + drawingGroup |

### 1.3 价值主张

**一句话**：从"工具"升级为"控制台"——粘贴即解析、解析即归档，用户只需关心结果。

---

## 二、用户故事

### 2.1 核心场景

| ID | 角色 | 场景 | 期望 |
|----|------|------|------|
| US-01 | 任意用户 | 在抖音/小红书等 App 复制分享链接后切回本 App | App 自动读到剪贴板内容并触发下载，无需任何点击 |
| US-02 | 重度用户 | 经常需要把视频/图集保存到相册 | 设置里开一次"自动保存"，之后所有下载完成后直接进相册 |
| US-03 | 偶尔用户 | 只想预览不想保存 | 关闭"自动保存"，下载后停留在预览态，手动决定是否归档 |
| US-04 | 视觉敏感用户 | 等待下载时希望有沉浸的视觉反馈 | 看到能量进度环、数据流、粒子轨道等动效，等待变成"看戏" |

### 2.2 边缘场景

- 剪贴板内容是非 URL 文本 → 不打扰，不自动粘贴
- 剪贴板内容与当前输入框相同 → 不重复粘贴
- 用户清空输入框后又切回前台 → 同一条剪贴板不会被再次自动回填（去重靠 `lastAutoPastedClipboard`）
- 下载中切回前台 → 不打断（`autoPasteFromClipboardIfNeeded()` 检查 `isLoading`）
- 自动保存失败（如相册权限被拒）→ 在状态卡片显示错误，引导用户去系统设置授权

---

## 三、功能清单

### 3.1 自动化三连（核心抓手）

| 功能 | 触发时机 | 落地点 |
|------|---------|--------|
| 自动粘贴 | App 启动 / 后台→前台（scenePhase=.active） | `DouyinDownloadViewModel.autoPasteFromClipboardIfNeeded()` |
| 自动解析下载 | 自动粘贴成功且内容含 http(s) | 同上方法尾部调用 `processInput()` |
| 自动保存到相册 | 下载完成且 `AppSettings.autoSaveKey == true` | `downloadVideo()` 成功分支调用 `saveMedia()` |

### 3.2 设置项

| 项 | 类型 | 默认 | 存储 | 影响 |
|----|------|------|------|------|
| 自动保存到相册 | Bool | false | UserDefaults: `settings.autoSaveToLibrary` | 下载完成后自动调 `saveMedia()` |
| Cookie 配置 | 多平台分组 | 空 | UserDefaults（已有） | 影响 Instagram / X 解析能力 |
| 坐标管家 | 子页面 | — | 文件存储（已有） | 与下载功能无关，辅助工具 |

### 3.3 视觉设计系统（Neo-Cyber）

#### 调色板（私有 `NeoCyber` namespace）

| Token | 值 | 用途 |
|-------|-----|------|
| `void` | #05070F | 深空背景基色 |
| `abyss` | #090D1A | 背景渐变中段 |
| `surface` | #121A2D | 玻璃面板底色 |
| `cyan` | #00E5FF | 主品牌色 / 解析态 |
| `magenta` | #FF2D7A | 警示 / 下载传输态 |
| `lime` | #7BFF61 | 成功 / 待机指示 |
| `amber` | #FFBB00 | 强调标签 |
| `textPrimary` | #E8F2FF | 主要文字 |
| `textMuted` | #8FA3C7 | 次要文字 |

#### 字体策略

- **标题/动作**：SF Pro Rounded · weight=`.heavy/.black` · tracking 3–10 模拟艺术字
- **正文**：SF Pro Rounded · weight=`.medium/.semibold`
- **进度数字**：Rounded `.black` · monospacedDigit 防跳字
- 字间距（tracking）作为"艺术字"主要表达手段，配合渐变色 foregroundStyle

#### 动态层（三件套）

1. **`NeoCyberBackground`**
   - 静态等距网格（GridLines Shape）
   - 单 TimelineView @ 20fps 驱动呼吸光晕 + 扫描带，整体走 Canvas + `drawingGroup()` GPU 合成
2. **`NeonProgressRing`**（下载中）
   - 外层：60 刻度旋转环 @ 30fps
   - 中层：22% 反向品红弧
   - 主进度弧：角向渐变 + 末端高斯光晕
   - 中心：呼吸缩放的进度数字 + "进度" 艺术字
   - `ParticleOrbit`：18 颗粒子在 Canvas 内绕环抖动闪烁
   - 整体 `.drawingGroup()` 离屏渲染
3. **`DataStreamBar`**
   - 28 段均衡器柱，相位驱动高度，4 段品红 + 24 段青色

#### 玻璃面板（`HoloPanel` modifier）

`.ultraThinMaterial` 底 + 双向 LinearGradient 高光 + 双色 strokeBorder + 外发光 shadow。glow 颜色随语境（青/品红/青柠）切换。

### 3.4 中文艺术字文案表

| 旧（英文） | 新（中文艺术字） | 位置 |
|-----------|----------------|------|
| NEXUS · v1 | 灵 枢 · 壹 | 工具栏品牌 |
| MEDIA · DECRYPT · ENGINE | 媒 体 · 解 析 · 引 擎 | Hero 徽章 |
| LINK_INPUT | 链 接 · 入 口 | 输入区标题 |
| > paste share link here | 在此粘贴分享链接 … | 占位符 |
| PASTE | 粘 贴 | 主按钮 |
| DECRYPT | 立 即 解 析 | 主 CTA |
| CLEAR | 清 空 | 输入区辅助 |
| TRANSMISSION · IN · PROGRESS | 信 号 传 输 中 | 下载头 |
| LIVE | 实 时 | 实时徽章 |
| PARSING / PERCENT | 解 析 / 进 度 | 进度环中心 |
| STATE / CHANNEL / ENC | 状 态 / 通 道 / 编 码 | 指标格 |
| PARSE / STREAM | 解 析 / 传 输 | 状态值 |
| CDN-A1 / H264 | 主 线 一 / H · 264 | 通道值 |
| ABORT | 中 止 任 务 | 取消按钮 |
| STANDBY | 待 机 中 | 空预览 |
| awaiting media payload | 等 待 媒 体 载 入 | 空预览副 |
| VIDEO / IMAGE · PAYLOAD | 视 频 / 图 集 · 载 荷 | 预览头 |
| n FRAMES | 共 n 张 | 图集计数 |
| EXPORT TO DOWNLOADS | 导 出 · 至 · 下 载 | Mac 保存 |
| ARCHIVE TO LIBRARY | 归 档 · 至 · 相 册 | iOS 保存 |
| ERR · CODE | 错 误 提 示 | 错误卡 |
| OK · ARCHIVED | 已 归 档 | 成功卡 |

---

## 四、性能与稳定性

### 4.1 卡顿根因分析（旧版）

| 现象 | 根因 | 修复颗粒度 |
|------|------|----------|
| Loading 启动瞬间掉帧 | `isLoading` 切换触发整页布局，多个 TimelineView 同时进入活跃态 | 用 `.transition(.opacity)` + `.animation` 显式过渡，把布局变化收敛进单一动画 |
| 背景持续 60fps 渲染热 | 双 TimelineView（光晕 + 扫描线）+ RadialGradient 在 SwiftUI 树里 diff | 合并为单 Canvas @ 20fps + `drawingGroup()` 走 Metal |
| 进度环复杂层级触发 layout pass | 多个 ZStack 子图 + symbolEffect | 整体 `.drawingGroup()`，60→30fps |
| 粒子计算量大 | Canvas 内三角函数 18 颗粒子 | 已通过 drawingGroup 离屏，可控 |

### 4.2 帧率预算

| 层 | 帧率 | 渲染方式 |
|----|------|---------|
| 静态背景渐变 + 网格 | 静态 | SwiftUI Shape，无重绘 |
| 背景动效（光晕 + 扫描线） | 20 fps | Canvas + drawingGroup |
| 进度环 + 粒子 | 30 fps | Canvas + drawingGroup |
| 数据流均衡器 | 30 fps | Canvas |
| Hero/输入/状态等 SwiftUI 文本层 | 按需 | 不在 TimelineView 内 |

---

## 五、技术方案要点

### 5.1 模块拆分

```
DouyinDownloadView.swift
  ├─ NeoCyber (设计 Token 命名空间)
  ├─ NeoCyberBackground (背景层)
  ├─ HoloPanel modifier (玻璃面板)
  ├─ NeonProgressRing + ParticleOrbit (下载动效)
  ├─ DataStreamBar (均衡器)
  └─ DouyinDownloadView (主结构 - phoneLayout/macLayout)

ViewModels/DouyinDownloadViewModel.swift
  ├─ autoPasteFromClipboardIfNeeded()  ← 新
  ├─ pasteFromClipboard() ← 改造为自动触发下载
  └─ downloadVideo() ← 成功后判断 autoSaveEnabled

Services/AppSettings.swift  ← 新文件
  └─ autoSaveKey 常量

Views/CookieSettingsView.swift
  └─ 新增"通用 / 自动保存到相册" Section
```

### 5.2 关键状态机

```
[空闲]
  │ scenePhase→.active && 剪贴板有 http
  ↓
[输入框已填充] ─── 用户手动按下载 ──→ [解析中]
  │ 自动触发                              │
  ↓                                       ↓
[解析中] ──→ [下载中] ──→ [成功]
                            │
                            ├ autoSaveEnabled=true → [自动保存] → [已归档]
                            └ autoSaveEnabled=false → [等待手动]
```

### 5.3 权限

- 相册写入权限：构建设置 `INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription`（已有）
- 自动保存首次触发会弹系统权限询问，拒绝后状态卡显示错误引导

---

## 六、验收用例

| 用例 ID | 步骤 | 期望结果 |
|---------|------|---------|
| TC-01 | 在抖音复制链接，切回本 App | 输入框自动填充 + 自动开始解析下载 |
| TC-02 | 关闭"自动保存"，下载完成 | 停留在预览态，需手动点"归档至相册" |
| TC-03 | 开启"自动保存"，下载完成 | 状态卡显示"已归档：xx 已保存到相册" |
| TC-04 | 手动粘贴相同内容 | 不会触发重复下载（去重生效） |
| TC-05 | 下载中切到后台再回前台 | 下载继续，不被中断 |
| TC-06 | 剪贴板无 http 文本时切回前台 | 输入框无变化 |
| TC-07 | 下载中观察 | 进度环 30fps 流畅，无明显掉帧或布局抖动 |
| TC-08 | 长时间停留下载界面 | 内存稳定，无累积泄漏（Canvas drawingGroup 不持有外部引用） |

---

## 七、风险与待办

| 风险 | 缓解 |
|------|------|
| 相册权限被拒后自动保存连续失败 | 检测到 `PHAuthorizationStatus.denied` 后关闭一次开关并提示 |
| iOS 系统剪贴板提示横幅频繁出现 | 自动粘贴已通过 `lastAutoPastedClipboard` 去重，单次会话同一内容只读一次 |
| `drawingGroup` 在某些机型可能与 List/ScrollView 干扰 | 已限定在 Canvas 子层，不包裹整个 ScrollView |

**后续 Roadmap：**
- v1.1：进度环点击进入历史下载列表
- v1.2：批量队列下载（剪贴板含多条链接时排队）
- v1.3：自动保存按媒体类型分流（视频→相册、图集→自建相簿）

---

## 八、变更记录

| 日期 | 版本 | 内容 | 分支 |
|------|------|------|------|
| 2026-05-29 | v1.0 | 初版 PRD：Neo-Cyber 设计 + 自动化三连 + 自动保存开关 | `feat/neo-cyber-redesign` |
