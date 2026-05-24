# Story 8.1.2 · Flutter Clipboard Auto-Read Parity

**Status:** 🔧 In Progress（Dev Done @ commit pending；QA 静态审核通过 14/16 ✅ + 2 ⏸ 待用户编译；等待用户手动运行验证）
**Epic:** 7 · 输入体验
**Depends on:** Story 7.1 (iOS done), Architecture decisions at `docs/superpowers/architecture/2026-05-25-story-8.1-architecture.md`

## User Story

作为一个 Flutter 端用户（iOS / Android 双端），我希望每次打开 App 或从后台切回 App 时，App 能自动识别我刚才复制的链接并自动填入主输入框，同时显示一个 3 秒后自动消失的轻量提示，这样我不需要每次都手动点"粘贴"按钮，体验与已上线的原生 iOS 端完全一致。

## Acceptance Criteria

> 提示文案锁定为常量（在两端代码中必须严格一致，与 iOS Story 7.1 `showClipboardHint` 调用点一致）：
>
> ```dart
> // 建议放在 download_viewmodel.dart 顶部或类内 static const
> static const String kClipboardHintText = '已识别到剪贴板内容，已自动填入';
> ```

| AC | 标准 |
|---|---|
| **AC1（触发频率）** | `DownloadViewModel` 必须 `with WidgetsBindingObserver`，在构造函数体内调用 `WidgetsBinding.instance.addObserver(this)`，在 `dispose()` 内调用 `WidgetsBinding.instance.removeObserver(this)`。`@override void didChangeAppLifecycleState(AppLifecycleState state)` 中，**仅**在 `state == AppLifecycleState.resumed` 时调用 `checkClipboardOnForeground()`，其它状态忽略。冷启动后首次 `resumed` 也必须触发。 |
| **AC2（API 与缓存）** | 新增 `Future<void> checkClipboardOnForeground() async` 公共方法，内部通过 `final data = await Clipboard.getData(Clipboard.kTextPlain); final text = data?.text;` 读取剪贴板（与现有 `pasteFromClipboard` 使用同一 API）。`data == null` 或 `text == null` 时静默 no-op。 |
| **AC3（比较三条件）** | 仅当读取到的字符串同时满足：(a) 非 `null` AND (b) `text.isNotEmpty`（不做 `trim`） AND (c) `text != _lastClipboardContent` —— 三条件全部满足时，才进入填入流程；任何一条不满足则静默返回（不调用 `notifyListeners()`、不更新任何字段）。 |
| **AC4（缓存范围 = 仅内存）** | `_lastClipboardContent` 必须是 `DownloadViewModel` 的 `String? _lastClipboardContent` 私有字段。**禁止**写入 `shared_preferences` / `path_provider` / 任何 disk。进程被系统杀死后缓存丢失是预期行为。 |
| **AC5（私有 vs 公开字段）** | `_lastClipboardContent` 必须是私有（下划线前缀）。新增 `String? clipboardHint` 必须是公开字段（UI 通过 `context.watch<DownloadViewModel>()` 观察）。`_clipboardHintDismissTimer` 必须是私有 `Timer?` 字段。 |
| **AC6（缓存更新时机）** | 在进入填入流程后**立即**赋值 `_lastClipboardContent = text;`，**先于** `inputText = text;` 与 `notifyListeners()`。即使用户后续编辑输入框，缓存值不变；用户复制同一字符串再次进入前台时必须 no-op。 |
| **AC7（输入填入行为）** | 填入方式为**替换** `inputText = text;`（直接赋值），**不是**追加；用户后续仍可通过 `TextField` 编辑。**必须**触发 `notifyListeners()` 以让 `input_section.dart` 的 `TextField` 重建。 |
| **AC8（公开 hint 字段）** | 新增 `String? clipboardHint;` 字段；类型严格为 `String?`（不是 `bool`），便于未来文案变更但本 Story 写入值固定为 `kClipboardHintText`。 |
| **AC9（提示时长 = 恰好 3 秒）** | 在 VM 内部通过 `Timer(const Duration(seconds: 3), () { clipboardHint = null; notifyListeners(); })` 实现 3 秒后自动清空。Timer 必须保存到 `_clipboardHintDismissTimer`，下次触发时先 `_clipboardHintDismissTimer?.cancel()` 再启动新 Timer —— 即 **cancel-and-restart**，不允许堆叠。`dispose()` 内必须 `_clipboardHintDismissTimer?.cancel()`。 |
| **AC10（提示视觉 = 内联蓝色 Card）** | 在 `flutter/lib/widgets/status_section.dart::StatusSection` 的 `Column` 内顶部（在 `errorMessage` / `successMessage` Card 之前或之后均可，但**必须**在该 Column 内）新增条件渲染：`if (vm.clipboardHint != null) _StatusCard(color: Colors.blue.shade50, textColor: Colors.blue.shade800, icon: Icons.content_paste, message: vm.clipboardHint!)`。**必须**复用现有 `_StatusCard` 私有 widget 类（不新增其他 widget 类）。**禁止**使用 `SnackBar` / `ScaffoldMessenger` / `OverlayEntry`。 |
| **AC11（不做 URL 校验）** | 任何非空且与缓存不同的字符串都触发填入；**不**校验是否是 URL、不**校验**是否包含 `http://` / `https://`、不裁剪空白。 |
| **AC12（接受系统横幅）** | iOS 端会出现 "<App> 已粘贴自 XX" 系统横幅；Android 12+ 端会出现 toast "<App> 已读取你的剪贴板"。两者均**不规避**（与 iOS Story 7.1 AC5 对齐：透明度优于隐藏读取）。 |
| **AC13（Share intent / 初始 inputText no-op 防抖）** | 当前 Flutter 项目无 share intent 处理（不像 Android 原生有 `handleShareIntent`），但为对齐 iOS 行为并防止未来 Provider 在外部预填 `inputText` 的情况，必须在 `checkClipboardOnForeground()` 进入填入分支前同步初始 inputText 到 cache：若 `_lastClipboardContent == null && inputText.isNotEmpty`，先执行 `_lastClipboardContent = inputText`，仅在首次（cache 为 null）时执行这次同步。这样若剪贴板内容恰好等于已预填的 `inputText`，会被视为重复并 no-op。 |
| **AC14（clearInput 行为对齐 iOS）** | 现有 `clearInput()` 不改变 cache 行为：**不可**在 `clearInput()` 中重置 `_lastClipboardContent`。可以选择是否在 `clearInput()` 中清空 `clipboardHint` 与取消 `_clipboardHintDismissTimer`，但**禁止**重置 `_lastClipboardContent`（与 iOS 行为一致：用户清空后再切前台、若剪贴板仍是上次值，必须 no-op）。 |
| **AC15（Provider 注册无变化）** | `flutter/lib/views/download_page.dart` 中 `ChangeNotifierProvider(create: (_) => DownloadViewModel(), ...)` 保持不变；VM 在构造期就能调用 `WidgetsBinding.instance.addObserver(this)`（生产环境 `WidgetsFlutterBinding.ensureInitialized()` 已在 `main.dart:5` 调用，符合前置条件）。 |
| **AC16（编译与运行通过）** | `cd flutter && flutter analyze` 无新增 lint error；`flutter run` 在 iOS 与 Android 双端：复制任意非空字符串 → 杀掉 App → 重新打开 → 输入框必须填入该字符串 + 蓝色 Card 提示 3 秒后消失。再次按 home 切到后台，复制同样的字符串，回到 App 必须 no-op。 |

## 实施上下文（Dev Context）

### 要修改的文件清单（绝对路径）

1. `/Users/maxiao/Desktop/videoPick/flutter/lib/viewmodels/download_viewmodel.dart`
   - 顶部 import 新增 `import 'dart:async';`（已存在）；新增 `import 'package:flutter/widgets.dart';`（如 `material.dart` 不足以暴露 `WidgetsBindingObserver` / `WidgetsBinding` / `AppLifecycleState`，实际 `material.dart` re-export 已包含，验证后决定是否需要额外 import）
   - 类签名改为 `class DownloadViewModel extends ChangeNotifier with WidgetsBindingObserver`
   - 新增 `static const String kClipboardHintText = '已识别到剪贴板内容，已自动填入';`
   - 新增字段：`String? clipboardHint;`、`String? _lastClipboardContent;`、`Timer? _clipboardHintDismissTimer;`
   - 新增构造函数 `DownloadViewModel() { WidgetsBinding.instance.addObserver(this); }`
   - `@override void dispose()`：先 `WidgetsBinding.instance.removeObserver(this);`，再 `_clipboardHintDismissTimer?.cancel();`，最后 `super.dispose();`
   - `@override void didChangeAppLifecycleState(AppLifecycleState state)`：`if (state == AppLifecycleState.resumed) checkClipboardOnForeground();`
   - 新增 `Future<void> checkClipboardOnForeground() async`
   - 新增 `void _showClipboardHint(String message)`（cancel-and-restart 3s Timer，触发 `notifyListeners()`）
   - **不**修改 `clearInput()` 中关于 `_lastClipboardContent` 的行为（AC14）

2. `/Users/maxiao/Desktop/videoPick/flutter/lib/widgets/status_section.dart`
   - 在 `Column` 的 `children` 列表头部（`errorMessage` 之前）新增条件 `if (vm.clipboardHint != null) _StatusCard(color: Colors.blue.shade50, textColor: Colors.blue.shade800, icon: Icons.content_paste, message: vm.clipboardHint!)`
   - 复用现有 `_StatusCard` 类，无需新增 widget 类

### 不要修改的文件（仅作为上下文阅读）

- `/Users/maxiao/Desktop/videoPick/flutter/lib/views/download_page.dart` — `ChangeNotifierProvider` 注册无变化
- `/Users/maxiao/Desktop/videoPick/flutter/lib/main.dart` — `WidgetsFlutterBinding.ensureInitialized()` 已存在（main.dart:5），生产环境前置条件已满足

### 架构决策引用（章节锚点）

- 决策 F1（VM 实现 `WidgetsBindingObserver`）：见 `docs/superpowers/architecture/2026-05-25-story-8.1-architecture.md` §2 Decision F1
- 决策 F2（缓存放在 VM 私有字段）：§2 Decision F2
- 决策 F3（内联蓝色 Card 而非 SnackBar）：§2 Decision F3
- 接口契约：§3 "Flutter — DownloadViewModel additions" 与 "status_section.dart addition"
- 跨端一致性 11 条：§4（已逐条复述到本 Story AC 中）
- 风险与回退：§5（测试环境 `WidgetsBinding.instance` 未初始化、`status_section.dart` 未来重构、3s 内切后台 hint 残留）

### 复用的现有接口 / 类（方法签名）

- `class DownloadViewModel extends ChangeNotifier` — 当前签名，本 Story 改为 `extends ChangeNotifier with WidgetsBindingObserver`
- `String inputText` — 公开字段，赋值后 `notifyListeners()`
- `Clipboard.getData(Clipboard.kTextPlain): Future<ClipboardData?>` — 与现有 `pasteFromClipboard()` 同一 API（`download_viewmodel.dart:38-44`）
- `WidgetsBinding.instance.addObserver` / `removeObserver` — 来自 `package:flutter/widgets.dart`（`material.dart` re-export）
- `AppLifecycleState.resumed` — 唯一关心的状态
- UI: `Card` / `Icons.content_paste` / `Colors.blue.shade50` / `Colors.blue.shade800`
- 复用 `_StatusCard`（私有 widget，在 `status_section.dart:78-112`）—— **不**新增 public widget

### 跨端一致性条款（Dev 必读，与 iOS Story 7.1 完全一致）

1. **触发频率：** Flutter 用 `AppLifecycleState.resumed`（对齐 iOS `scenePhase == .active` / Android `ON_RESUME`），每次前台切换触发一次。
2. **缓存范围：** 仅内存，**禁止**持久化（不用 `shared_preferences`）。
3. **比较逻辑：** 三条件 AND（非 null、非空、与缓存不同）。
4. **缓存更新时机：** 在填入前立即写入；用户后续编辑不影响缓存；同字符串重复复制是 no-op。
5. **输入填入行为：** **替换** `inputText`，不是追加；必须 `notifyListeners()`。
6. **提示时长：** 恰好 3 秒；cancel-and-restart `Timer`，不堆叠。`dispose()` 中必须 cancel。
7. **提示视觉：** `status_section.dart` 内联蓝色 `_StatusCard`，**不是** `SnackBar` / `Toast` / `OverlayEntry`。图标 = `Icons.content_paste`。
8. **提示文案：** `已识别到剪贴板内容，已自动填入`（与 iOS / Android 完全相同的常量字符串）。
9. **不做 URL 校验：** 任何非空差异文本都触发。
10. **接受系统横幅：** iOS "已粘贴自 XX" 横幅、Android 12+ 系统 toast 不规避。
11. **初始 inputText / Share-intent 优先：** Flutter 当前无 share intent 集成，但首次 cache 同步逻辑（AC13）保留以对齐语义。

### 已知陷阱（来自 Architecture §5 Risks）

- **测试环境** `WidgetsBinding.instance` 未初始化：构造 VM 时会抛错。单元测试需要先 `TestWidgetsFlutterBinding.ensureInitialized()`。本 Story 不强制要求添加 widget test，但 Dev 写任何 test 时需注意。
- **`status_section.dart` 未来重构** 可能丢失 hint 位置约定：在新增 `if (vm.clipboardHint != null)` 上方添加注释 `// Story 8.1.2: clipboard auto-read hint, position contract per docs/superpowers/architecture/2026-05-25-story-8.1-architecture.md §4`。
- **3s 内切后台**：iOS 行为是 hint 隐式存活 3s 然后消失；Flutter 实现接受相同行为（Timer 不会因 `paused` 而暂停）。
- **3s 内连续触发**：必须 cancel-and-restart 旧 Timer，不允许堆叠（AC9）。

## Out of Scope

- 不修改 iOS / Android 代码（Android 由 Story 8.1.1 承接）。
- 不修改现有 `pasteFromClipboard`（手动粘贴按钮）行为；新功能与手动粘贴并存。
- 不做 URL 合法性校验、不做自动解析、不做自动下载。
- 不重构 `status_section.dart` 其它分支（errorMessage / successMessage / loading 不动）。
- 不重构 `download_viewmodel.dart` 其它方法（`processInput` / `saveMedia` / `cancelDownload` / `dismissPreview` 不动）。
- 不持久化 `_lastClipboardContent` 到 `shared_preferences`。
- 不新增 Flutter 三方包依赖（`Clipboard` 是 `flutter/services` 内建）。
- 不接入 Android share intent 转发（Flutter 当前未实现 share intent，AC13 只是首次 inputText 同步逻辑，不需要 platform channel 改动）。
- 不修改 `clearInput()` 中 `_lastClipboardContent` 行为（缓存不重置）。

## QA Hint

QA Agent 后续可基于以下验收路径设计验证步骤（双端：iOS Simulator + Android Emulator）：

1. **冷启动触发（双端）：** 设备上复制字符串 `https://v.douyin.com/test1/` → 杀掉 App → 打开 App → 输入框出现该字符串 + 蓝色 Card "已识别到剪贴板内容，已自动填入" → 等待 3 秒 → Card 自动消失，输入框文本保留。
2. **背景→前台触发：** App 在前台 → 按 home → 复制字符串 `https://v.douyin.com/test2/` → 回到 App → 输入框出现该字符串 + 提示。
3. **重复字符串 no-op：** 在场景 2 后再次按 home → 不复制（剪贴板仍为 test2）→ 回到 App → **无**提示、输入框保持 test2 不变。
4. **空剪贴板 no-op：** 清空剪贴板（或剪贴板为空启动模拟器）→ 打开 App → 无提示、输入框为空、无 crash、`Clipboard.getData` 返回 null 或空字符串均能安全处理。
5. **3 秒内连续触发：** 复制 A → 回到 App（出现提示 1s 后）→ 立刻按 home → 复制 B → 回到 App → 旧 Timer 取消，新 Timer 重新计时 3 秒，提示文本一致；不会出现 6s 提示或重叠 Card。
6. **iOS 系统横幅：** iOS 15+ 上场景 1 应同时观察到系统横幅 "VideoPick 已粘贴自 XX"，这是预期行为，不算 bug。
7. **Android 系统 toast：** Android 12+ 模拟器上场景 1 应同时观察到 "VideoPick 已读取你的剪贴板" toast。
8. **进程杀死 cache 重置：** 场景 2 后杀 App（不是从最近任务划掉，而是系统 OOM 杀进程或 `flutter run` 重启）→ 重新打开 → 剪贴板仍是 test2 → 必须再次触发填入和提示（cache 已释放）。
9. **clearInput 不重置 cache：** 场景 2 后点击输入框的 Clear 图标清空 → 不切后台 → 再切后台不复制再回前台 → no-op（与 iOS 行为一致）。
10. **`dispose()` 不泄漏 observer / timer：** 切换页面到 `CookieSettingsPage` 后再返回 `DownloadPage`，新 VM 实例应能正常工作；旧 VM 的 `dispose()` 必须已执行 `removeObserver` 与 `_clipboardHintDismissTimer?.cancel()`（可通过 `flutter run --observatory-port` + DevTools 检查 observer 数量是否泄漏，可选）。
11. **跨端文案一致性：** 在 iOS、Android、Flutter（iOS build）、Flutter（Android build）四种组合下截图比对，蓝色 Card 文案必须**逐字相同**为 `已识别到剪贴板内容，已自动填入`，图标统一为 clipboard-paste 形态。

## Estimated LoC

约 60-90 行代码增量：
- `download_viewmodel.dart`：+40 行（`with` 混入、`static const`、3 个新字段、构造体、`dispose` override、`didChangeAppLifecycleState` override、`checkClipboardOnForeground`、`_showClipboardHint`、必要 import）
- `status_section.dart`：+8 行（`if (vm.clipboardHint != null)` 分支 + 注释 + 一行 `_StatusCard` 构造）
- 单 PR 可完成，无新增文件、无新增依赖。
