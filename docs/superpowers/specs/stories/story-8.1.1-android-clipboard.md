# Story 8.1.1 · Android Clipboard Auto-Read Parity

**Status:** 🔧 In Progress（Dev Done @ commit pending；QA 静态审核通过 14/16 ✅ + 1 ⚠️ 非阻塞 + 1 ⏸ 待用户编译；等待用户手动运行验证）
**Epic:** 7 · 输入体验
**Depends on:** Story 7.1 (iOS done), Architecture decisions at `docs/superpowers/architecture/2026-05-25-story-8.1-architecture.md`

## User Story

作为一个 Android 用户，我希望每次打开 App 或从后台切回 App 时，App 能自动识别我刚才复制的链接并自动填入主输入框，同时显示一个 3 秒后自动消失的轻量提示，这样我不需要每次都手动点"粘贴"按钮，体验与已上线的 iOS 端完全一致。

## Acceptance Criteria

> 提示文案锁定为常量（在两端代码中必须严格一致，与 iOS Story 7.1 `showClipboardHint` 调用点一致）：
>
> ```kotlin
> private const val CLIPBOARD_HINT_TEXT = "已识别到剪贴板内容，已自动填入"
> ```

| AC | 标准 |
|---|---|
| **AC1（触发频率）** | 在 `MainActivity.kt::VideoPickApp` 顶层 Composable 内，通过 `DisposableEffect(lifecycleOwner)` 注册 `LifecycleEventObserver`，**仅**在 `Lifecycle.Event.ON_RESUME` 事件触发时调用 `viewModel.checkClipboardOnForeground()` 一次；冷启动后首次 `ON_RESUME` 也必须触发。`onDispose` 中必须 `removeObserver(observer)`。 |
| **AC2（API 与缓存）** | 在 `DownloadViewModel` 中新增 `fun checkClipboardOnForeground()` 公共方法，内部通过 `(getApplication<Application>().getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).primaryClip?.getItemAt(0)?.coerceToText(getApplication()).toString()` 读取剪贴板。**必须**使用 `coerceToText`（不是 `.text`）。`primaryClip` 为 `null` 或 `itemCount == 0` 时静默 no-op。 |
| **AC3（比较三条件）** | 仅当读取到的字符串同时满足：(a) 非 `null` AND (b) 非空字符串（`isNotEmpty()`，不做 `trim`） AND (c) `!= lastClipboardContent` —— 三条件全部满足时，才进入填入流程；任何一条不满足则静默返回（不更新 cache、不更新 UI）。 |
| **AC4（缓存范围 = 仅内存）** | `lastClipboardContent` 必须是 `DownloadViewModel` 的 `private var lastClipboardContent: String? = null` 字段。**禁止**写入 `SharedPreferences` / Room / DataStore / 任何 disk。进程被系统杀死后缓存丢失是预期行为。 |
| **AC5（缓存放在 VM 而非 UiState）** | `lastClipboardContent` **不可**放入 `UiState`，避免不必要的 Compose 重组。同理 `clipboardHintDismissJob` 也保持为 VM 的 `private var clipboardHintDismissJob: Job? = null`。 |
| **AC6（缓存更新时机）** | 在进入填入流程后**立即**写入 `lastClipboardContent = clipboardString`，**先于** UI 更新。即使用户后续编辑输入框，缓存值不变；用户复制同一字符串再次进入前台时必须 no-op。 |
| **AC7（输入填入行为）** | 填入方式为**替换**当前 `inputText`（通过更新 `_state.value = _state.value.copy(inputText = clipboardString)`），**不是**追加；用户后续仍可编辑 `OutlinedTextField`。 |
| **AC8（UiState 新字段）** | `UiState` 新增 `val clipboardHint: String? = null` 字段；类型严格为 `String?`（不是 `Boolean`），便于未来文案变更但本 Story 写入值固定为常量 `CLIPBOARD_HINT_TEXT`。 |
| **AC9（提示时长 = 恰好 3 秒）** | 在 `DownloadViewModel` 中通过 `viewModelScope.launch { delay(3000); _state.value = _state.value.copy(clipboardHint = null) }` 实现 3 秒后自动清空。Job 必须保存到 `clipboardHintDismissJob`，下次触发时先 `clipboardHintDismissJob?.cancel()` 再启动新 Job —— 即 **cancel-and-restart**，不允许堆叠。 |
| **AC10（提示视觉 = 内联 Card）** | 在 `DownloadScreen.kt::StatusSection` 中新增条件渲染：`state.clipboardHint?.let { ... }` 时显示一个 `Card`，使用 `MaterialTheme.colorScheme.primaryContainer` 或与 iOS 蓝色对齐的色（`Color(0xFFE3F2FD)` 背景 + `Color(0xFF1565C0)` 前景皆可），图标为 `Icons.Default.ContentPaste`。**禁止**使用 `Snackbar` / Toast / 全屏 Overlay。位置：位于 `state.errorMessage` 和 `state.successMessage` Card 渲染之前或之后均可，但**必须**在 `StatusSection` 这个 Composable 内部，不能漂浮在 Scaffold 之上。 |
| **AC11（不做 URL 校验）** | 任何非空且与缓存不同的字符串都触发填入；**不**校验是否是 URL、不**校验**是否包含 `http://` / `https://`、不裁剪空白。 |
| **AC12（接受系统横幅）** | Android 12+ 在 `primaryClip` 读取时会显示系统 toast "<App> 已读取你的剪贴板"，**不规避**（与 iOS AC5 对齐：透明度优于隐藏读取）。 |
| **AC13（Share-Intent 优先级 / no-op 防抖）** | `MainActivity.handleShareIntent(intent)` 在 `onCreate` 中先于 `setContent` 执行，会通过 `viewModel.updateInput(sharedText)` 在首次 `ON_RESUME` 之前填入 `inputText`。当首次 `ON_RESUME` 触发 `checkClipboardOnForeground()` 时：若**当前剪贴板内容字符串恰好等于 share intent 注入到 `_state.value.inputText` 的字符串**（即剪贴板和分享内容相同），则视为已处理 —— 实现方式：在 `checkClipboardOnForeground()` 进入填入分支前，先把 `lastClipboardContent` 初始化为当前 `_state.value.inputText`（如非空），等价地把"已被 share 填入的内容"视作"上次已处理的剪贴板内容"。具体实现策略：在比较三条件前增加 `if (lastClipboardContent == null && _state.value.inputText.isNotEmpty()) lastClipboardContent = _state.value.inputText`，仅在首次（cache 为 null）时执行这次同步。 |
| **AC14（clearInput 行为对齐 iOS）** | 现有 `clearInput()` 不改变行为：仅清 `inputText` 等状态（实际现在是 `_state.value = UiState()` 整体重置，其中 `clipboardHint` 默认 `null` 是可接受的）。但**不可**在 `clearInput()` 中重置 `lastClipboardContent`；用户清空输入后再回前台，若剪贴板内容仍是上次值，必须 no-op（与 iOS 行为一致）。 |
| **AC15（Lifecycle 依赖确认）** | Dev 实施前需先确认 `androidx.lifecycle:lifecycle-runtime-compose:2.8.7`（已在 `android/app/build.gradle.kts:79` 存在）可被 import；`LocalLifecycleOwner` 从 `androidx.lifecycle.compose.LocalLifecycleOwner` 导入（不是从 `androidx.compose.ui.platform`）。 |
| **AC16（编译与运行通过）** | `cd android && ./gradlew assembleDebug` 必须成功；安装到模拟器后：复制任意非空字符串 → 杀掉 App → 重新打开 → 输入框必须填入该字符串 + 蓝色 Card 提示 3 秒后消失。再次按 home 切到后台，复制同样的字符串，回到 App 必须 no-op（无提示、无填入变化）。 |

## 实施上下文（Dev Context）

### 要修改的文件清单（绝对路径）

1. `/Users/maxiao/Desktop/videoPick/android/app/src/main/java/com/demo/videopick/viewmodel/DownloadViewModel.kt`
   - 在 `UiState` 中新增 `val clipboardHint: String? = null`
   - 新增 `private var lastClipboardContent: String? = null`
   - 新增 `private var clipboardHintDismissJob: Job? = null`
   - 新增 `fun checkClipboardOnForeground()` 公共方法
   - 新增 `private fun showClipboardHint(message: String)`（cancel-and-restart 3s timer）
   - **不**修改 `clearInput()`（AC14）

2. `/Users/maxiao/Desktop/videoPick/android/app/src/main/java/com/demo/videopick/MainActivity.kt`
   - 在 `VideoPickApp` Composable 顶部添加：
     - `val lifecycleOwner = androidx.lifecycle.compose.LocalLifecycleOwner.current`
     - `DisposableEffect(lifecycleOwner) { ... ON_RESUME -> viewModel.checkClipboardOnForeground() ... }`

3. `/Users/maxiao/Desktop/videoPick/android/app/src/main/java/com/demo/videopick/ui/screen/DownloadScreen.kt`
   - 在 `StatusSection(state, viewModel)` Composable 内新增 `state.clipboardHint?.let { ... }` 分支，渲染蓝色 `Card` + `Icons.Default.ContentPaste`

### 架构决策引用（章节锚点）

- 决策 A1（Lifecycle 机制）：见 `docs/superpowers/architecture/2026-05-25-story-8.1-architecture.md` §2 Decision A1
- 决策 A2（缓存放在 VM）：§2 Decision A2
- 决策 A3（Clipboard API + coerceToText）：§2 Decision A3
- 决策 A4（内联 Card 而非 Snackbar）：§2 Decision A4
- 接口契约：§3 "Android — DownloadViewModel additions" 与 "MainActivity.kt::VideoPickApp addition"
- 跨端一致性 11 条：§4（已逐条复述到本 Story AC 中）
- 风险与回退：§5（`lifecycle-runtime-compose` import 路径、`primaryClip` 可能为 null、3s 内切后台的 hint 残留行为）

### 复用的现有接口 / 类（方法签名）

- `DownloadViewModel(application: Application) : AndroidViewModel(application)` — 复用现有 ctor，无需新增构造参数
- `_state: MutableStateFlow<UiState>` — 通过 `_state.value = _state.value.copy(...)` 更新 `inputText` 和 `clipboardHint`
- `viewModelScope: CoroutineScope` — 复用，启动 3s `delay` Job
- `getApplication<Application>().applicationContext: Context` — 获取 `ClipboardManager`
- Compose: `androidx.lifecycle.compose.LocalLifecycleOwner` / `androidx.lifecycle.LifecycleEventObserver` / `androidx.lifecycle.Lifecycle.Event.ON_RESUME` / `androidx.compose.runtime.DisposableEffect`
- UI: `androidx.compose.material3.Card` / `androidx.compose.material.icons.filled.ContentPaste`（`material-icons-extended` 已在依赖中：`android/app/build.gradle.kts:73`）

### 跨端一致性条款（Dev 必读，与 iOS Story 7.1 完全一致）

1. **触发频率：** Android 用 `ON_RESUME`（对齐 iOS `scenePhase == .active`），每次前台切换触发一次。
2. **缓存范围：** 仅内存，**禁止**持久化。
3. **比较逻辑：** 三条件 AND（非 null、非空、与缓存不同）。
4. **缓存更新时机：** 在填入前立即写入；用户后续编辑不影响缓存；同字符串重复复制是 no-op。
5. **输入填入行为：** **替换** `inputText`，不是追加。
6. **提示时长：** 恰好 3 秒；cancel-and-restart，不堆叠。
7. **提示视觉：** 状态区内联蓝色 Card，**不是** Snackbar / Toast / Overlay。图标 = `Icons.Default.ContentPaste`。
8. **提示文案：** `已识别到剪贴板内容，已自动填入`（与 iOS 完全相同的常量字符串）。
9. **不做 URL 校验：** 任何非空差异文本都触发。
10. **接受系统横幅：** Android 12+ 系统 toast 不规避。
11. **Share-Intent 优先：** 首次 `ON_RESUME` 前 `inputText` 可能已被 share intent 填入；VM 必须识别这种"已被 share 填入"的情况并 no-op（AC13 实现策略）。

### 已知陷阱（来自 Architecture §5 Risks）

- `LocalLifecycleOwner` 导入位置：**正确**导入路径是 `androidx.lifecycle.compose.LocalLifecycleOwner`（不是 `androidx.compose.ui.platform.LocalLifecycleOwner` —— 后者在新版 Compose 已被弃用为 typealias，回退方案）。
- `primaryClip` 可能为 `null`（焦点未授予 / 剪贴板为空）→ 静默 no-op，不报错。
- 用户在 3 秒内切到后台又回来：iOS 行为是 hint 隐式继续存活 3s 然后消失；Android 实现接受相同行为。
- 3s 内连续触发（罕见但可能）：必须 cancel-and-restart，不允许堆叠多个 Job。

## Out of Scope

- 不修改 iOS / Flutter 代码（Flutter 由 Story 8.1.2 承接）。
- 不修改现有 `pasteFromClipboard`（手动粘贴按钮）行为；新功能与手动粘贴并存。
- 不做 URL 合法性校验、不做自动解析、不做自动下载。
- 不重构 `StatusSection`（仅新增分支，不改 errorMessage / successMessage / loading 现有渲染）。
- 不新增 `androidx.lifecycle.*` 依赖（`lifecycle-runtime-compose:2.8.7` 已存在）。
- 不修改 `clearInput()` 行为（缓存不重置）。
- 不持久化 `lastClipboardContent` 到 `SharedPreferences`。

## QA Hint

QA Agent 后续可基于以下验收路径设计验证步骤：

1. **冷启动触发：** 设备上复制字符串 `https://v.douyin.com/test1/` → 杀掉 App（从最近任务划掉）→ 打开 App → 输入框出现该字符串 + 蓝色 Card "已识别到剪贴板内容，已自动填入" → 等待 3 秒 → Card 自动消失，输入框文本保留。
2. **背景→前台触发：** App 在前台 → 按 home → 复制字符串 `https://v.douyin.com/test2/` → 回到 App → 输入框出现该字符串 + 提示。
3. **重复字符串 no-op：** 在场景 2 后再次按 home → 不复制（剪贴板仍为 test2）→ 回到 App → **无**提示、输入框保持 test2 不变。
4. **空剪贴板 no-op：** 清空剪贴板（或剪贴板为空启动模拟器）→ 打开 App → 无提示、输入框为空、无 crash。
5. **Share intent 不冲突：** 从其他 App 用"分享到 VideoPick" 发送一段文本 → App 启动后输入框应只被填入一次（要么 share intent 要么 clipboard，二者不重复触发提示）。建议测试场景：剪贴板字符串与 share intent 字符串相同时，**不应**显示蓝色提示 Card。
6. **3 秒内连续触发：** 复制 A → 回到 App（出现提示 1s 后）→ 立刻按 home → 复制 B → 回到 App → 旧 timer 取消，新 timer 重新计时 3 秒，提示文本一致。
7. **系统横幅：** Android 12+ 模拟器上场景 1 期间应同时观察到系统 toast "VideoPick 已读取你的剪贴板"，这是预期行为，不算 bug。
8. **进程被杀 cache 重置：** 场景 2 后杀掉 App（系统杀进程，不是用户从最近任务划掉以保证 `viewModelScope` 真正释放）→ 重新打开 → 剪贴板仍是 test2 → 必须再次触发填入和提示（因为 cache 已释放）。
9. **clearInput 不重置 cache：** 场景 2 后点击输入框的 Clear (X) 图标清空 → 不切后台 → 此时 cache 仍是 test2，无前台切换事件，无提示 —— 符合预期。再切后台不复制再回前台 → 仍 no-op。

## Estimated LoC

约 60-90 行代码增量：
- `DownloadViewModel.kt`：+25 行（`UiState` 新字段、两个 private 字段、`checkClipboardOnForeground()`、`showClipboardHint()`、必要的 import）
- `MainActivity.kt`：+15 行（`DisposableEffect` 块 + import）
- `DownloadScreen.kt`：+20 行（`StatusSection` 内新增 `Card` 分支 + import）
- 单 PR 可完成，无新增文件、无新增依赖。
