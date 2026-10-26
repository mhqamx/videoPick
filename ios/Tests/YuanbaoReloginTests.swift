// Standalone simulator test. The fixture supplies an already saved account.
import Foundation
import WebKit

@MainActor final class YuanbaoSessionStore {
    static let shared = YuanbaoSessionStore()
    private(set) var saves = 0
    func cookies() -> [HTTPCookie] {
        [HTTPCookie(properties: [.name: "previous_account", .value: "sample", .domain: "yuanbao.tencent.com", .path: "/"])!]
    }
    func save(_ cookies: [HTTPCookie]) throws { saves += 1 }
}
actor WeChatChannelsService {
    static let shared = WeChatChannelsService()
    func validateSession(cookie: String) async throws { throw WeChatChannelsError.loginRequired }
}
@main struct YuanbaoReloginTests {
    @MainActor static func main() async throws {
        let login = YuanbaoLoginModel()
        let operation = Task { await login.start() }
        try await Task.sleep(for: .milliseconds(300))
        let cookies = await login.webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        login.stop()
        operation.cancel()
        guard !cookies.contains(where: { $0.name == "previous_account" }) else {
            print("FAIL: relogin silently reuses the previous account")
            exit(1)
        }
        guard YuanbaoSessionStore.shared.saves == 0 else {
            print("FAIL: cancel relogin changed the saved session")
            exit(1)
        }
        print("PASS: fresh relogin does not seed old credentials or overwrite them on cancel")
    }
}
