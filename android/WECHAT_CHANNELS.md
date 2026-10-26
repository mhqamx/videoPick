# Android 视频号下载

与已经通过 iPhone 真机验证的流程对应：**粘贴视频号链接 → 首次在 App 内登录元宝 → 自动继续下载 → 预览 / 保存相册**。剪贴板自动模式会在登录后继续下载并保存。

## 使用

- 支持 `https://weixin.qq.com/sph/...` 和 `https://channels.weixin.qq.com/finder-preview/pages/sph?id=...`。
- 首次下载或登录过期时打开元宝官方网页登录；可使用页面提供的手机号/微信等登录方式。完成后自动继续，也可点“我已登录，继续”。
- 设置顶部的“视频号”区域提供登录、重新登录和退出。
- 取消登录保留以前保存的账号；重新登录使用新的网页会话，验证成功后才替换已保存账号。
- 不需要 Mac 本地服务、代理、证书或手动填写 Cookie。Android 需要在本机登录，iPhone 的账号状态不会自动同步。

## 实现和边界

`channels/` 下新增 Kotlin 解析、直接请求服务、登录 Activity、加密会话存储与登录恢复状态。下载在其他平台识别/后端请求之前独立完成，不会将视频号请求回退到后端。

元宝会话使用 Android Keystore AES-256-GCM 加密，写入不参与备份的私有目录，不进入现有 CookieStore。登录 WebView 位于不可导出的内部 Activity 和独立进程；Android 9+ 使用独立 WebView 数据目录。Android 8.x 尚无该 API，使用该专用登录进程的默认 WebView 目录，当前工程没有其他 WebView。WebView 登录数据在关闭时清理，并从云备份和设备迁移中排除。重新登录不注入旧 Cookie。官方账号接口确认非匿名用户后才保存会话。

元宝 Cookie 仅发往元宝 API，不发送到微信视频信息接口或 CDN；所有这些原生请求均不跟随重定向。优先 H.264，HTTPS 下载，文件长度及视频轨道/时长校验通过后才进入预览。取消会取消网络请求并删除不完整临时文件；迟到结果不会重新打开登录或覆盖后来的任务。

支持普通视频分享，不保证原画，不支持直播、主页、无播放权限或需要额外解密的资源。上游接口变化可能需要维护。

协议依据：[wx_channels_download](https://github.com/ltaoo/wx_channels_download) v260907，以及本工程已验证的 Swift 实现。平台 API 依据：[WebView 数据目录](https://developer.android.com/reference/android/webkit/WebView#setDataDirectorySuffix(java.lang.String))、[Android 加密与 Keystore](https://developer.android.com/privacy-and-security/cryptography)。

## 构建与测试

```sh
cd android
JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ./gradlew \
  :app:testDebugUnitTest :app:assembleDebug --console=plain
```

Debug 安装包：`app/build/outputs/apk/debug/app-debug.apk`。

`WeChatChannelsLiveTest` 默认跳过，只有显式提供 `VIDEOPICK_YUANBAO_COOKIE_FILE` 时执行。文件应是本机私有临时文件，内容为已授权元宝会话；不写进源码或命令参数，测试后删除。该测试在 JVM 运行生产 Kotlin 服务，不会向 App 导入会话。

## 2026-10-26 验证记录

- 基线及功能完成后的单元测试、Debug APK 构建通过。
- 常规回归：24 项通过；1 项真实账号测试默认跳过。覆盖两种分享地址、恶意域名、非法 ID、H.264 优先、加密/无媒体、非匿名账号判断、凭据隔离、登录恢复、取消、重复回调、主页面重建恢复及原剪贴板/小红书/定位测试。
- 另行运行真实账号测试通过：直接验证元宝账号，解析 `ADKbu5wdF8`，下载“秀场直击 SIUF文化周”。
- Kotlin 下载结果：H.264 + AAC，576×1024，7.731995 秒，1,083,125 字节，ffmpeg 完整解码无错误。
- 全量 lintDebug 未通过：既有 MockLocationService.kt:146 的两个 WrongConstant 错误；该文件与 HEAD 相同，本次未修改。其余 26 条为现有 SDK/依赖/资源等警告，未报告视频号新增代码错误。
- 当前没有连接 Android 设备，也没有已安装模拟器镜像；尚未在 Android 设备上验证 WebView 登录、Keystore 持久化、实际播放和保存相册。JVM 真实网络通过与 APK 编译通过，不代替装机验收。
- iOS 真机视频号分享下载已由用户确认通过；本次保留原 iOS 功能。

装机检查建议：首次登录并下载 → 保存相册 → 重启 App 再次下载 → 设置重新登录并取消 → 退出登录后再次下载。不要仅凭出现预览卡片判断相册保存成功。

## 本地私有配置

签名密钥、个人签名信息、GPX 样例、IDE 用户状态不纳入版本控制。克隆后的代码不包含个人后端地址；视频号使用手机直接解析，其他需要后端的平台请配置自己的服务。
复制 `backend.local.properties.example` 为 `backend.local.properties`，填写自己的可选后端地址。Release 签名通过被忽略的 `keystore.properties` 和本机密钥配置；Debug 构建不需要 Release 密钥。
