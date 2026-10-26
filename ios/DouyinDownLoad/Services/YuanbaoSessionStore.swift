import Foundation
import Combine
import Security

/// Kept outside CookieStore: this account must never be included in backend requests.
@MainActor
final class YuanbaoSessionStore: ObservableObject {
    static let shared = YuanbaoSessionStore()
    @Published private(set) var hasSession = false
    private var records: [CookieRecord] = []
    private let service = (Bundle.main.bundleIdentifier ?? "VideoPick") + ".yuanbao"

    private struct CookieRecord: Codable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let expires: Date?
        let secure: Bool

        init(_ cookie: HTTPCookie) {
            name = cookie.name; value = cookie.value; domain = cookie.domain
            path = cookie.path; expires = cookie.expiresDate; secure = cookie.isSecure
        }
        var cookie: HTTPCookie? {
            var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path]
            if let expires { properties[.expires] = expires }
            if secure { properties[.secure] = "TRUE" }
            return HTTPCookie(properties: properties)
        }
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "session"]
    }

    private init() {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let saved = try? JSONDecoder().decode([CookieRecord].self, from: data) {
            records = saved
        }
        hasSession = !cookieHeader().isEmpty
    }

    func cookies() -> [HTTPCookie] {
        WeChatChannelsParser.eligibleCookies(records.compactMap(\.cookie))
    }

    func cookieHeader() -> String { WeChatChannelsParser.cookieHeader(records.compactMap(\.cookie)) }

    /// Call only after the official account endpoint confirms a non-anonymous user.
    func save(_ cookies: [HTTPCookie]) throws {
        let newRecords = WeChatChannelsParser.eligibleCookies(cookies).map(CookieRecord.init)
        guard !newRecords.isEmpty else { throw WeChatChannelsError.loginRequired }
        let data = try JSONEncoder().encode(newRecords)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw WeChatChannelsError.unavailable("无法保存登录状态，请重试（\(status)）") }
        records = newRecords
        hasSession = true
    }

    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw WeChatChannelsError.unavailable("无法清除登录状态，请重试（\(status)）")
        }
        records = []
        hasSession = false
    }
}
