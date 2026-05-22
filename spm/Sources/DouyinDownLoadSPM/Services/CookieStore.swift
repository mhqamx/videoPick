import Foundation

/// 管理各平台的认证 Cookie（持久化到 UserDefaults）
/// nonisolated 以便从任意隔离域访问（UserDefaults 自身线程安全）
nonisolated final class CookieStore: @unchecked Sendable {
    static let shared = CookieStore()

    private let defaults = UserDefaults.standard
    private let storageKey = "platform_cookies"

    private init() {}

    // MARK: - 平台定义

    struct PlatformCookieConfig {
        let platform: String
        let displayName: String
        let fields: [(key: String, label: String, placeholder: String)]
    }

    static let supportedPlatforms: [PlatformCookieConfig] = [
        PlatformCookieConfig(
            platform: "instagram",
            displayName: "Instagram",
            fields: [
                (key: "sessionid", label: "sessionid", placeholder: "粘贴 sessionid 值"),
                (key: "ds_user_id", label: "ds_user_id", placeholder: "粘贴 ds_user_id 值"),
                (key: "csrftoken", label: "csrftoken", placeholder: "粘贴 csrftoken 值"),
            ]
        ),
        PlatformCookieConfig(
            platform: "x",
            displayName: "X (Twitter)",
            fields: [
                (key: "auth_token", label: "auth_token", placeholder: "粘贴 auth_token 值"),
                (key: "ct0", label: "ct0", placeholder: "粘贴 ct0 值"),
            ]
        ),
    ]

    // MARK: - 读写

    /// 获取所有平台的 cookies，用于发送给 backend
    func allCookies() -> [String: [String: String]] {
        guard let data = defaults.data(forKey: storageKey),
              let dict = try? JSONDecoder().decode([String: [String: String]].self, from: data) else {
            return [:]
        }
        // 过滤掉空值
        return dict.compactMapValues { cookies in
            let filtered = cookies.filter { !$0.value.isEmpty }
            return filtered.isEmpty ? nil : filtered
        }.compactMapValues { $0 }
    }

    /// 获取某平台的 cookies
    func cookies(for platform: String) -> [String: String] {
        allCookies()[platform] ?? [:]
    }

    /// 保存某平台的 cookies
    func saveCookies(for platform: String, cookies: [String: String]) {
        var all = allCookies()
        let filtered = cookies.filter { !$0.value.isEmpty }
        if filtered.isEmpty {
            all.removeValue(forKey: platform)
        } else {
            all[platform] = filtered
        }
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: storageKey)
        }
    }

    /// 清除某平台的 cookies
    func clearCookies(for platform: String) {
        var all = allCookies()
        all.removeValue(forKey: platform)
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: storageKey)
        }
    }

    /// 检查某平台是否已配置 cookie
    func hasCookies(for platform: String) -> Bool {
        let c = cookies(for: platform)
        return !c.isEmpty && c.values.contains(where: { !$0.isEmpty })
    }
}
