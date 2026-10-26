import SwiftUI
import WebKit
import Combine

struct YuanbaoLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var login = YuanbaoLoginModel()
    let onAuthenticated: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("登录一次，即可直接下载视频号").font(.headline)
                    Text("请在元宝官方页面登录，可选择手机号登录。完成后会自动继续下载。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let message = login.message {
                        Text(message).font(.footnote).foregroundStyle(.orange)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding()
                Divider()
                YuanbaoWebView(webView: login.webView)
                Divider()
                Button {
                    Task { await login.checkSession(showErrors: true) }
                } label: {
                    HStack {
                        if login.isChecking { ProgressView() }
                        Text(login.isChecking ? "正在确认登录…" : "我已登录，继续")
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).padding().disabled(login.isChecking)
            }
            .navigationTitle("登录元宝")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { login.stop(); dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("刷新") { login.webView.reload() }
                }
            }
        }
        .task { await login.start() }
        .onChange(of: login.authenticated) { _, authenticated in
            if authenticated { onAuthenticated(); dismiss() }
        }
        .onDisappear { login.stop() }
    }
}

@MainActor
final class YuanbaoLoginModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    @Published var isChecking = false
    @Published var authenticated = false
    @Published var message: String?
    private var active = false

    override init() {
        let config = WKWebViewConfiguration()
        // The Keychain is the only persistent source of this session.
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        webView.allowsBackForwardNavigationGestures = true
    }

    func start() async {
        active = true
        // Explicit login always starts fresh. Keep the existing Keychain session
        // untouched until a newly authenticated account replaces it.
        guard active, !Task.isCancelled else { return }
        webView.load(URLRequest(url: URL(string: "https://yuanbao.tencent.com/chat/naQivTmsDa")!))
        while active, !Task.isCancelled, !authenticated {
            try? await Task.sleep(for: .seconds(3))
            guard active, !Task.isCancelled else { return }
            await checkSession(showErrors: false)
        }
    }

    func stop() { active = false; webView.stopLoading() }

    func checkSession(showErrors: Bool) async {
        guard active, !isChecking, !authenticated else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            let header = WeChatChannelsParser.cookieHeader(cookies)
            try await WeChatChannelsService.shared.validateSession(cookie: header)
            guard active, !Task.isCancelled else { return }
            try YuanbaoSessionStore.shared.save(cookies)
            authenticated = true
        } catch {
            guard active, !Task.isCancelled else { return }
            if showErrors {
                message = (error as? WeChatChannelsError) == .loginRequired
                    ? "尚未检测到登录，请先在页面中完成登录。" : "确认登录失败，请检查网络后重试。"
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // OAuth may visit WeChat/QQ. Keep web navigation on their official HTTPS domains.
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let host = url.host?.lowercased() ?? ""
        let allowed = ["tencent.com", "qq.com", "weixin.com"].contains { host == $0 || host.hasSuffix("." + $0) }
        decisionHandler(url.scheme == "https" && allowed || url.absoluteString == "about:blank" ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { message = "登录页面加载失败，请检查网络后点刷新。" }
    }
}

private struct YuanbaoWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
