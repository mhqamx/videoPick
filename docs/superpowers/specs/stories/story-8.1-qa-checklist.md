# Story 8.1 QA Checklist — Android + Flutter Clipboard Auto-Read

> **QA Agent · 2026-05-25**
> Covers: Story 8.1.1 (Android) + Story 8.1.2 (Flutter)
> Upstream: Story 7.1 (iOS, already shipped) · Architecture: `docs/superpowers/architecture/2026-05-25-story-8.1-architecture.md`
> Dev's implementation is **not yet committed** (working-tree files only).

---

## 0. Files Reviewed (Static)

### Story 8.1.1 — Android
- `/Users/maxiao/Desktop/videoPick/android/app/src/main/java/com/demo/videopick/viewmodel/DownloadViewModel.kt`
- `/Users/maxiao/Desktop/videoPick/android/app/src/main/java/com/demo/videopick/MainActivity.kt`
- `/Users/maxiao/Desktop/videoPick/android/app/src/main/java/com/demo/videopick/ui/screen/DownloadScreen.kt`

### Story 8.1.2 — Flutter
- `/Users/maxiao/Desktop/videoPick/flutter/lib/viewmodels/download_viewmodel.dart`
- `/Users/maxiao/Desktop/videoPick/flutter/lib/widgets/status_section.dart`

---

## 1. Static Verification (Code Review against AC)

Legend: ✅ Satisfied · ⚠️ Concern · ❌ Violation · ⏸ Cannot verify statically

### 1.1 Story 8.1.1 (Android)

| AC | Verdict | Evidence (file:line) | Notes |
|---|---|---|---|
| **AC1** Trigger on ON_RESUME via `DisposableEffect(lifecycleOwner)` | ✅ | `MainActivity.kt:67-76` | Uses `LocalLifecycleOwner.current`, registers `LifecycleEventObserver`, gates on `Lifecycle.Event.ON_RESUME`, removes observer in `onDispose`. Matches contract exactly. |
| **AC2** API + cache; uses `coerceToText` | ✅ | `DownloadViewModel.kt:110-114` | Uses `clipboard.primaryClip ?: return`, then `primaryClip.itemCount == 0 → return`, then `getItemAt(0).coerceToText(context).toString()`. Correct. |
| **AC3** Three-condition AND (non-null, non-empty, ≠ cache); no `trim` | ✅ | `DownloadViewModel.kt:117-118` | `if (clipboardString.isEmpty()) return` then `if (clipboardString == lastClipboardContent) return`. No `trim()`. |
| **AC4** Cache is in-memory only | ✅ | `DownloadViewModel.kt:40` | `private var lastClipboardContent: String? = null`. No SharedPreferences / DataStore writes added. |
| **AC5** Cache + dismiss-job stay in VM, NOT in UiState | ✅ | `DownloadViewModel.kt:40-41` | Both are private VM fields. `UiState` only adds `clipboardHint`. |
| **AC6** Cache written **before** UI update | ✅ | `DownloadViewModel.kt:121-122` | `lastClipboardContent = clipboardString` precedes `_state.value = _state.value.copy(inputText = ...)`. |
| **AC7** Replace (not append) `inputText` | ✅ | `DownloadViewModel.kt:122` | Direct `copy(inputText = clipboardString)`. |
| **AC8** `UiState.clipboardHint: String?` (not Boolean) | ✅ | `DownloadViewModel.kt:30` | `val clipboardHint: String? = null`. |
| **AC9** Exactly 3 seconds; cancel-and-restart Job | ✅ | `DownloadViewModel.kt:126-134` | `clipboardHintDismissJob?.cancel()` then `viewModelScope.launch { delay(3000); … = null }`. Stored back to `clipboardHintDismissJob`. |
| **AC10** Inline `Card` inside `StatusSection`; `Icons.Default.ContentPaste`; correct colors; not Snackbar | ✅ | `DownloadScreen.kt:162-186` | `Card` with `Color(0xFFE3F2FD)` background, `Color(0xFF1565C0)` foreground, `Icons.Default.ContentPaste`, rendered inside `StatusSection` Composable. Position is **above** errorMessage / successMessage (AC10 says "before or after" is acceptable). |
| **AC11** No URL validation, no trim | ✅ | `DownloadViewModel.kt:104-124` | No `http`/`https` check, no `trim()`. |
| **AC12** Accept system banner | ✅ | n/a | Code does not attempt to suppress system toast. |
| **AC13** Share-Intent prime: sync `inputText` → cache on first call | ✅ | `DownloadViewModel.kt:106-108` | `if (lastClipboardContent == null && _state.value.inputText.isNotEmpty()) lastClipboardContent = _state.value.inputText`. Exactly the prescribed pattern. |
| **AC14** `clearInput()` must NOT reset `lastClipboardContent` | ⚠️ | `DownloadViewModel.kt:47-49` | `clearInput()` does `_state.value = UiState()` which wipes `clipboardHint` and `inputText`, but does **not** touch `lastClipboardContent` — so the AC's hard requirement is satisfied. Minor concern: it also doesn't `cancel()` the still-running `clipboardHintDismissJob`, which would set `clipboardHint = null` 3s later — harmless because it's already null, but worth noting. Acceptable per the AC's explicit phrasing. |
| **AC15** Lifecycle dependency confirmation; import path `androidx.lifecycle.compose.LocalLifecycleOwner` | ✅ | `MainActivity.kt:16`, `app/build.gradle.kts:79` | Import is `androidx.lifecycle.compose.LocalLifecycleOwner`. Dependency `androidx.lifecycle:lifecycle-runtime-compose:2.8.7` confirmed present. |
| **AC16** Compile + runtime: `./gradlew assembleDebug` + manual flow | ⏸ | n/a | Cannot verify — `ANDROID_HOME` not configured on this machine. Static review of all imports passes; final answer requires user-side compile + emulator run (see §2). |

**Android static summary:** 14 ✅ · 1 ⚠️ · 0 ❌ · 1 ⏸

### 1.2 Story 8.1.2 (Flutter)

| AC | Verdict | Evidence (file:line) | Notes |
|---|---|---|---|
| **AC1** `WidgetsBindingObserver` lifecycle; resumed-only | ✅ | `download_viewmodel.dart:9, 28-30, 32-37, 39-44` | Class mixes `WidgetsBindingObserver`; ctor calls `addObserver(this)`; `dispose()` calls `removeObserver(this)` then cancels timer then `super.dispose()`; `didChangeAppLifecycleState` only acts on `AppLifecycleState.resumed`. |
| **AC2** `Clipboard.getData(Clipboard.kTextPlain)`; null-safe | ✅ | `download_viewmodel.dart:53-55` | `final data = await Clipboard.getData(Clipboard.kTextPlain); final text = data?.text; if (text == null || text.isEmpty) return;`. |
| **AC3** Three-condition AND; no trim | ✅ | `download_viewmodel.dart:55-56` | Combines null+empty in one guard then `if (text == _lastClipboardContent) return;`. No `trim()`. |
| **AC4** In-memory cache only | ✅ | `download_viewmodel.dart:25` | `String? _lastClipboardContent;`. No shared_preferences usage added. |
| **AC5** Visibility: `_lastClipboardContent` private, `clipboardHint` public, `_clipboardHintDismissTimer` private | ✅ | `download_viewmodel.dart:21, 25, 26` | Correct underscore prefixes / lack thereof. |
| **AC6** Cache written **before** `inputText` + `notifyListeners()` | ✅ | `download_viewmodel.dart:59-61` | `_lastClipboardContent = text;` precedes `inputText = text; notifyListeners();`. |
| **AC7** Replace `inputText`; `notifyListeners()` | ✅ | `download_viewmodel.dart:60-61` | Direct assignment + notify. |
| **AC8** `String? clipboardHint` (not `bool`) | ✅ | `download_viewmodel.dart:21` | Declared as `String? clipboardHint;`. |
| **AC9** Exactly 3 s `Timer`; cancel-and-restart; dispose cancels | ✅ | `download_viewmodel.dart:35, 65-74` | `_clipboardHintDismissTimer?.cancel()` then assign new `Timer(const Duration(seconds: 3), …)`. `dispose()` cancels timer before `super.dispose()`. |
| **AC10** Inline blue `_StatusCard` inside `StatusSection` Column; reuses existing `_StatusCard`; no SnackBar | ✅ | `status_section.dart:15-22` | Reuses `_StatusCard` widget; colors `Colors.blue.shade50` / `Colors.blue.shade800`; icon `Icons.content_paste`. Placed at top of Column (before errorMessage). Position-contract comment is present. |
| **AC11** No URL validation, no trim | ✅ | `download_viewmodel.dart:47-63` | No URL parsing or trim performed. |
| **AC12** Accept system banner | ✅ | n/a | No suppression attempted. |
| **AC13** Initial inputText sync to cache on first call | ✅ | `download_viewmodel.dart:49-51` | `if (_lastClipboardContent == null && inputText.isNotEmpty) { _lastClipboardContent = inputText; }`. |
| **AC14** `clearInput()` must NOT reset `_lastClipboardContent` | ✅ | `download_viewmodel.dart:81-89` | `clearInput()` resets `inputText`, `errorMessage`, `successMessage`, `videoInfo`, `showPreview`, `downloadProgress`, but does **not** touch `_lastClipboardContent` or `clipboardHint` or the timer. Compliant. (Note: `clipboardHint` is preserved on `clearInput()` — explicitly allowed by AC14 "可以选择是否清空".) |
| **AC15** Provider registration unchanged | ⏸ | n/a (file not modified) | The story says `download_page.dart` is not to be touched; need to confirm by inspection that the Provider tree still constructs `DownloadViewModel()`. Likely fine — no evidence of regression in modified files. |
| **AC16** `flutter analyze` clean + manual flow | ⏸ | n/a | Cannot verify — `flutter` CLI not in PATH on this machine. Requires user-side run (see §2). |

**Flutter static summary:** 14 ✅ · 0 ⚠️ · 0 ❌ · 2 ⏸

---

## 2. Manual Verification Steps

> The user must run these on a real device or emulator/simulator because automated compile + runtime tools aren't available in the parent agent's environment.

### 2.1 Android — Setup

1. Open `/Users/maxiao/Desktop/videoPick/android/` in Android Studio (or a shell where `ANDROID_HOME` is set).
2. Connect a device or start an emulator with **API 31+** (so we can also observe the Android 12+ clipboard toast — AC12).
3. Build & install: `cd android && ./gradlew assembleDebug && ./gradlew installDebug`.
4. Confirm the app launches without crash.

### 2.2 Android Test Cases

| # | Maps to AC | Action | Expected Result |
|---|---|---|---|
| **A-T1** | AC1, AC2, AC6, AC7, AC8, AC10, AC16 | Cold start: kill VideoPick from recents. From another app copy text `https://v.douyin.com/test1/`. Re-launch VideoPick from launcher. | Input field is populated with `https://v.douyin.com/test1/`. A blue card with paste icon and the **exact** text `已识别到剪贴板内容，已自动填入` appears inside the status section. |
| **A-T2** | AC9 | Watch the blue card from A-T1 with a stopwatch. | Card disappears between 2.8 s and 3.3 s after first appearing. Input field text **remains**. |
| **A-T3** | AC1 (background→foreground) | While app is foreground, press Home. Copy `https://v.douyin.com/test2/` from another app. Return to VideoPick (recents or launcher icon). | Input field updates to `test2/`; blue card reappears for 3 s with the exact constant text. |
| **A-T4** | AC3, AC6 (repeat no-op) | After A-T3, press Home (do NOT copy anything new). Return to VideoPick. | **No** blue card. Input field still shows `test2/`. No flicker. |
| **A-T5** | AC2, AC3 (empty clipboard) | On a fresh emulator (no clipboard content), or run `adb shell service call clipboard ...` to clear, then cold-launch VideoPick. | No crash. No blue card. Input field empty. |
| **A-T6** | AC9 (cancel-and-restart) | Copy `A`. Open app (card appears). Within ~1 s press Home, copy `B`. Return to app. | Card shows `已识别到剪贴板内容，已自动填入` again, persists a fresh 3 s window from this latest return (not 5 s nor 2 s). Only one card visible. |
| **A-T7** | AC13 (share intent) | From a browser, select text `https://v.douyin.com/share-test/`, choose Share → VideoPick. | Input field is filled by share intent. The **same** content in the clipboard should NOT trigger a second blue card on the first `ON_RESUME`. (Pre-set the clipboard to identical text to force the conflict.) |
| **A-T8** | AC14 | After A-T3, tap the input field's Clear (X) icon. Then press Home (do NOT copy). Return. | No blue card. Input remains empty. (Cache still equals `test2/`, suppressing re-trigger.) |
| **A-T9** | AC16, AC12 | During A-T1 watch for the Android 12+ system toast `VideoPick 已读取你的剪贴板` or "VideoPick pasted from clipboard". | Toast appears. This is **expected**, not a bug. |
| **A-T10** | AC15 (regression) | Use the manual `粘贴` button (existing). | Still works identically: pulls current clipboard into input. |

### 2.3 Flutter — Setup

1. Ensure `flutter` is in PATH on the user's machine.
2. `cd /Users/maxiao/Desktop/videoPick/flutter`
3. `flutter pub get`
4. `flutter analyze` — should print 0 new errors (warnings about pre-existing code are OK; new code should be clean).
5. Run separately on **both** targets:
   - iOS: `flutter run -d "iPhone 17 Pro"` (or any booted simulator)
   - Android: `flutter run -d emulator-5554` (or a connected device)

### 2.4 Flutter Test Cases (run on BOTH iOS and Android)

| # | Maps to AC | Action | Expected Result |
|---|---|---|---|
| **F-T1** | AC1, AC2, AC6, AC7, AC8, AC10, AC16 | Cold start: kill app. Copy `https://v.douyin.com/test1/` from another app. Launch VideoPick. | Input populated, blue card with text exactly `已识别到剪贴板内容，已自动填入` and clipboard-paste icon shown inside the StatusSection (above any error/success cards). |
| **F-T2** | AC9 | Stopwatch from card-appearance. | Card dismisses between 2.8–3.3 s. Input text retained. |
| **F-T3** | AC1 (background→foreground) | Foreground → home → copy `test2/` from another app → return. | Input replaced with `test2/`, hint reappears 3 s. |
| **F-T4** | AC3 (no-op) | After F-T3, home → return WITHOUT copying. | No hint. Input unchanged. |
| **F-T5** | AC2, AC3 (empty / null) | Boot a fresh simulator with empty clipboard. Cold-launch. | No crash, no hint, input empty. (`Clipboard.getData` may return `null` or empty text — both must be safe.) |
| **F-T6** | AC9 (cancel-and-restart) | Copy `A` → return → ~1 s later home → copy `B` → return. | Only one card visible at any time; latest return restarts a fresh 3 s timer. |
| **F-T7** | AC13 | Pre-fill `inputText` via some external mechanism (or instrument: set `inputText = "X"` via debug build) then return to app with clipboard equal to `X`. | No hint, because first-call sync seeds cache with current `inputText`. |
| **F-T8** | AC14 | After F-T3, tap Clear (X). Without backgrounding, observe. Then home → return without copying. | Input cleared. Hint (if still visible from F-T3) may stay until its timer fires — acceptable. On return-to-foreground, NO new hint (cache still equals `test2/`). |
| **F-T9** | AC12 | During F-T1 on iOS 14+, observe "已粘贴自 …" system banner. On Android 12+, observe system toast. | Both appear — expected, not a bug. |
| **F-T10** | AC15 (regression — Provider tree) | Navigate `DownloadPage` → `CookieSettingsPage` → back. | App does not crash. New VM instance works correctly (cache reset because new VM has `null` cache). Use Flutter DevTools "Memory" tab to confirm the old VM is garbage-collected — optional but recommended. |
| **F-T11** | AC14, AC9 (dispose safety) | Trigger F-T3 then quickly navigate away from `DownloadPage` to `CookieSettingsPage` BEFORE 3 s elapse. | App does not crash with `setState() called after dispose()` or similar. Timer must have been cancelled. |
| **F-T12** | Regression: manual paste | Tap existing manual "粘贴" button. | Still pastes clipboard into `inputText` exactly as before. |

---

## 3. Edge Cases NOT Covered by AC

These were not enumerated in the story but the user should at least spot-check.

| # | Scenario | Platform | Why it matters | Suggested verification |
|---|---|---|---|---|
| **E1** | Device rotation (portrait → landscape) during the 3 s hint window | Android | Compose `Activity` recreation could re-trigger `ON_RESUME`. The hint is in `UiState` which persists in `ViewModel` (survives config-change), but the dismiss `Job` lives in `viewModelScope` — also survives. **Expect:** hint persists across rotation; timer keeps counting. | Manual: rotate at t=1s; confirm hint disappears at t≈3s, not restarted. |
| **E2** | Lock screen / unlock cycle | Both | Locking + unlocking fires `ON_PAUSE` + `ON_RESUME` on Android. **Expect:** re-read clipboard; if unchanged → no-op; if changed (user copied on lockscreen quick-reply) → fill. | Manual. |
| **E3** | Very long clipboard text (e.g., 50 KB JSON) | Both | `coerceToText` / `Clipboard.getData` may truncate or block. **Expect:** no crash; either fills truncated text or no-op gracefully. | Manual: copy a long string, return to app. |
| **E4** | Non-text clipboard (image, URI list, raw bytes) | Both | Android's `coerceToText` will stringify URIs; Flutter's `Clipboard.kTextPlain` will return `null`. **Expect:** Android may fill a `content://...` URI string into input (acceptable per AC11 — no URL validation); Flutter no-ops. | Manual: copy an image from Photos. |
| **E5** | Multi-line clipboard (with newlines / mixed content) | Both | `inputText` `OutlinedTextField` is `maxLines = 4` on Android. **Expect:** full content stored in VM; UI may scroll/wrap. | Manual. |
| **E6** | Notification panel pull-down (does this trigger `ON_PAUSE`?) | Android | Android 12+ may pause activity. Re-resume triggers another clipboard read + system toast spam. | Manual: pull down then dismiss; confirm only one card if no clipboard change. |
| **E7** | App resumed from share intent twice in a row | Android | Second share intent goes through `onNewIntent` → `setIntent(...)`. Currently `handleShareIntent` is only called in `onCreate` (`MainActivity.kt:34`). New share intent might NOT update inputText. This is **pre-existing behavior**, NOT a Story 8.1.1 regression, but worth noting. | Manual: while app is alive, share text again from another app. |
| **E8** | Background → foreground in <3 s after hint shown | Both | Per Architecture §5, accepted: hint stays visible the original 3 s; timer is NOT restarted unless clipboard changed. Verify implementation matches: with **unchanged** clipboard, second `ON_RESUME` should NOT extend or re-show the hint. | Manual: F-T6 with same clipboard content on both copies. |
| **E9** | Flutter VM disposed mid-hint, then a new `DownloadPage` instance created (Provider rebuild) | Flutter | New VM has fresh `null` cache; same clipboard content will fire a NEW hint immediately, because the new VM never knew about it. May surprise the user. Documented as expected behavior; just confirm no crash. | F-T10/T11. |
| **E10** | iOS system banner blocks the blue Card visually | Flutter on iOS | The "已粘贴自 …" banner is positioned at top of screen on iOS 16+; should NOT cover the blue card (which is inline within Column). | Manual: visual inspection on F-T1 iOS. |

---

## 4. Regression Risk Surface

The diff is small and additive. Specific checks below.

| Existing Feature | Risk? | Evidence | Verification |
|---|---|---|---|
| `pasteFromClipboard` (manual paste button, Android `DownloadScreen.kt:131-138`, Flutter `download_viewmodel.dart:91-97`) | **Low.** New auto-read does not touch the manual paste path. Manual paste still uses `.text?.toString()` (Android) / direct assignment (Flutter), separate from the new auto-read which uses `coerceToText`. | Both `pasteFromClipboard` (Flutter) and inline `OutlinedButton` "粘贴" handler (Android) are unmodified. | A-T10, F-T12. |
| `clearInput()` | **Low risk → acceptable.** Android: `clearInput()` resets the entire `UiState` so `clipboardHint` is wiped but `lastClipboardContent` is preserved (in VM, not in UiState) — compliant with AC14. Flutter: `clearInput()` resets fields but preserves `_lastClipboardContent` and `clipboardHint` — also compliant. ⚠ Note: Android's `clearInput()` does NOT call `clipboardHintDismissJob?.cancel()`, so if user clears mid-hint, an inert "set hint=null" runs 3 s later. **Harmless.** | `DownloadViewModel.kt:47-49`, `download_viewmodel.dart:81-89` | A-T8, F-T8. |
| `processInput()` / download flow | **None.** New code is invoked only on lifecycle resume, runs synchronously, finishes before download could be triggered. | `DownloadViewModel.kt:51-101`, `download_viewmodel.dart:99-134` untouched. | Manual: paste a real link and confirm download still works. |
| `StatusSection` layout — does new blue card disrupt error / success card rendering? | **None.** Android renders three independent `?.let` blocks in sequence; Flutter renders three `if` conditionals in a Column. The new clipboard card is purely additive at the **top** of the section; existing cards continue to render below if their state is set. | `DownloadScreen.kt:161-240`, `status_section.dart:12-41` | Manual: trigger an error (paste invalid URL), confirm error card still shows. Trigger a download success, confirm success card shows. Both can coexist with hint if timing overlaps. |
| Compose recomposition cost from new `clipboardHint` field in UiState | **Negligible.** Only one extra `String?` field added; entire `state` is already collected via `collectAsState()`. | `DownloadViewModel.kt:30` | None needed. |
| Flutter Provider rebuild cost from `clipboardHint` notifications | **Negligible.** Only fires on lifecycle resume and hint dismiss. | `download_viewmodel.dart:65-74` | None needed. |
| Existing `WidgetsBindingObserver` consumers in the app | **None found.** `DownloadViewModel` is the first/only consumer. | Verified by grep absence (file diff). | None needed. |
| Cookie settings navigation (Android NavHost) | **None.** Lifecycle observer is registered at app-shell level (`VideoPickApp`), not per-screen; navigating into Cookie settings will not unregister it. | `MainActivity.kt:67-76` | Manual: navigate into Cookie settings, copy something, navigate back to Download — confirm one extra `ON_RESUME` does NOT happen (NavHost should not re-trigger Activity lifecycle). |

---

## 5. Known Unverifiable Items (Environment-Limited)

| Item | Reason | Who must verify |
|---|---|---|
| `./gradlew assembleDebug` compiles cleanly | `ANDROID_HOME` is not set in this shell; parent agent could not run Gradle. | User (in Android Studio or with `ANDROID_HOME` set). |
| `./gradlew installDebug` + runtime smoke test of A-T1..A-T10 | Same as above + needs emulator/device. | User. |
| `flutter analyze` reports 0 new errors | `flutter` CLI is not in PATH. | User. |
| `flutter run` smoke test on iOS and Android (F-T1..F-T12) | Needs Flutter SDK + booted simulators / devices. | User. |
| `xcodebuild` for Flutter iOS target | iOS CocoaPods/Xcode integration was not exercised; only Dart source changed, so iOS build risk is low — but still requires user verification. | User. |
| Whether the Android 12+ clipboard system toast actually appears | Requires emulator at API 31+. | User. |
| Whether the iOS clipboard system banner ("已粘贴自 …") appears on iOS 14+ during Flutter run | Requires iOS Simulator or device. | User. |
| Memory leak check (`_clipboardHintDismissTimer` lifecycle on Flutter VM dispose) | Requires Flutter DevTools session. | User (optional). |

---

## 6. Acceptance Recommendation

### Story 8.1.1 (Android) — **READY (pending user manual verify)**

- Static review: **14 ✅ / 1 ⚠️ / 0 ❌ / 1 ⏸**
- The single ⚠️ is on AC14 and is **non-blocking**: the implementation does satisfy the AC text exactly (it does NOT reset `lastClipboardContent` in `clearInput()`). The minor cosmetic note about not cancelling the dismiss `Job` on `clearInput()` is harmless and within spec ("可以选择是否在 `clearInput()` 中清空 `clipboardHint`").
- Recommendation: **Mark Done after user confirms A-T1..A-T10 pass on a real Android device/emulator with `./gradlew assembleDebug` succeeding.**

### Story 8.1.2 (Flutter) — **READY (pending user manual verify)**

- Static review: **14 ✅ / 0 ⚠️ / 0 ❌ / 2 ⏸**
- All 14 statically-verifiable ACs satisfied. The 2 ⏸ items (AC15, AC16) are pure environment limits.
- Recommendation: **Mark Done after user confirms F-T1..F-T12 pass on BOTH iOS simulator AND Android emulator/device, with `flutter analyze` clean.**

---

## Top 3 Things the User MUST Manually Verify Before Merging

1. **End-to-end clipboard cold-start on a real device (both stories).** Run A-T1 on Android and F-T1 on both iOS and Android via Flutter. Visually confirm: (a) input field is auto-filled, (b) blue card with **exact** Chinese constant text `已识别到剪贴板内容，已自动填入` appears, (c) card dismisses at ~3 s, (d) Android 12+ shows the OS clipboard-access toast and iOS shows the "已粘贴自" banner — both expected.
2. **Repeat-clipboard no-op (AC3+AC6, both stories).** Run A-T4 and F-T4. The cache must suppress re-trigger when clipboard content is unchanged. This is the load-bearing semantic that prevents repeated annoying hints.
3. **Compile cleanly.** `cd android && ./gradlew assembleDebug` (Android) and `cd flutter && flutter analyze` (Flutter). The parent agent could not run either — any unseen import error or analyzer warning surfaces here.

---

## 验收建议

- 通过条件：
  - **Story 8.1.1 (Android):** AC1, AC2, AC3, AC4, AC5, AC6, AC7, AC8, AC9, AC10, AC11, AC12, AC13, AC14, AC15 全部静态通过；AC16 需用户手动验证 `./gradlew assembleDebug` 成功并通过 A-T1..A-T10。
  - **Story 8.1.2 (Flutter):** AC1..AC14 全部静态通过；AC15 + AC16 需用户手动验证 `flutter analyze` 无新增 lint error 并通过 F-T1..F-T12（iOS + Android 双端）。
- 阻塞性问题：无。Android AC14 的 ⚠️ 是观察性注释，不构成阻塞。
- 后续 Story 建议：
  - Story 8.1.3（可选 / 低优先级）：在 `clearInput()` 中显式调用 `clipboardHintDismissJob?.cancel()` / `_clipboardHintDismissTimer?.cancel()`，让 Job/Timer 生命周期更整齐。当前实现无 bug，仅为代码卫生。
  - Story 8.1.4（可选 / 测试覆盖）：为 Flutter VM 添加 widget test，使用 `TestWidgetsFlutterBinding.ensureInitialized()` 包装 + 模拟 `didChangeAppLifecycleState(AppLifecycleState.resumed)`，覆盖 AC3 / AC6 / AC9 / AC13。
  - Story 8.2（独立）：考虑给 Android 端 `onNewIntent` 也接入 share-intent 重新填入逻辑（当前 share intent 只在 `onCreate` 处理一次，二次 share 不会更新 inputText —— 这是 Story 8.1.1 之外的既有行为，不属于本次回归）。
