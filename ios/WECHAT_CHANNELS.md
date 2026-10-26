# 视频号下载（iPhone 独立运行）

## 使用

1. 粘贴 `https://weixin.qq.com/sph/...` 或 `https://channels.weixin.qq.com/finder-preview/pages/sph?id=...` 链接，点“解析下载”。
2. 首次使用会打开元宝官方登录页。在页面中完成手机号或微信等登录；App 检测成功后继续下载。也可点“我已登录，继续”手动确认。
3. 下载完成后使用原来的预览和保存相册功能。剪贴板自动模式会继续自动保存。

设置顶部的“视频号”区域可以登录、重新登录、退出。登录过期时会再次打开登录页。取消登录不会下载，也不会覆盖原有账号；重新登录从空网页会话开始，成功后才替换保存的会话。

日常使用不需要运行 Mac 服务，不需要代理、证书或填写 Cookie。请在自己的 iPhone App 内完成首次登录，Mac 浏览器的登录态不会自动同步到手机。

## 实现

- `WeChatChannelsParser`：严格识别分享链接，解析播放引用和视频信息，优先 H.264。
- `WeChatChannelsService`：手机直接请求元宝解析接口及微信视频信息接口，独立校验官方账号接口的非匿名登录状态。
- `YuanbaoSessionStore`：相关会话保存在本机 Keychain，仅本设备解锁时可读；不进入原 CookieStore/backend 请求。
- `YuanbaoLoginView`：临时 WKWebView 登录会话，验证通过才保存；取消不保存。
- 复用原下载服务、进度、预览和相册流程。视频号请求不回退到公共后端；元宝 Cookie 不发给微信视频接口或 CDN。API/CDN 不跟随重定向。
- 视频下载后使用 AVFoundation 校验可播放性与时长，不将错误页面或不支持的加密数据当作成功视频。

协议参考：[wx_channels_download](https://github.com/ltaoo/wx_channels_download)，本机参考版本 v260907 / d3a59ed5909a332fdd61b3c49bd49442db9c687f。此处使用原生 Swift 实现其元宝解析请求链路，没有嵌入 Go 程序或抓包代理。

## 验证

在仓库根目录，先启动一个 iOS 模拟器，再运行：

```sh
ios/Tests/run-wechat-channels-tests.sh booted
xcodebuild -project ios/DouyinDownLoad.xcodeproj -scheme DouyinDownLoad \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/videopick-ios-channels CODE_SIGNING_ALLOWED=NO build
```

测试脚本包含解析与凭据边界、网络请求、真实 ViewModel 的登录恢复/取消/重复点击/自动保存、真实 WKWebView 的重新登录隔离，以及原有剪贴板、小红书回归。服务替身仅用于独立测试，不包含真实登录态。

2026-10-26 验证记录：

- 使用本机已授权账号，独立编译本次 Swift 解析服务，直接请求目标链接 `ADKbu5wdF8` 并下载成功；官方账号验证接口也通过。
- 下载视频为“秀场直击 SIUF文化周”，H.264 + AAC，576×1024，7.731995 秒，1,083,125 字节；ffmpeg 全文件解码无错误。
- iOS Simulator 构建成功；模拟器可运行，视频号入口与元宝官方手机号/微信登录页面正常显示。
- 已通过模拟器独立测试验证登录后恢复原链接、取消后忽略迟到结果、重新登录不复用旧 Cookie、自动保存及快速重复点击。
- 用户于 2026-10-26 确认 iPhone 真机可以下载视频号分享链接；保存相册未单独反馈验收结果。此前 Mac Swift 与模拟器测试仍作为不同层次的验证记录。

## 限制

当前支持普通视频分享；不支持直播、主页、无播放权限及需要额外解密的资源。视频清晰度取决于分享接口，不保证原画。上游非公开接口可能变化，失效时需更新解析逻辑。若重新登录后仍解析失败，会显示错误而不反复弹出登录。

## 本地私有配置

签名密钥、个人签名信息、GPX 样例、IDE 用户状态不纳入版本控制。克隆后的代码不包含个人后端地址；视频号使用手机直接解析，其他需要后端的平台请配置自己的服务。
复制 `Config/Signing.local.xcconfig.example` 为 `Config/Signing.local.xcconfig`，填写自己的签名团队、Bundle ID 和可选后端地址。模拟器无签名构建可使用公开默认配置。
