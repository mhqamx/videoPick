import Foundation

nonisolated enum WeChatChannelsError: LocalizedError, Equatable {
    case loginRequired, invalidResponse, noMedia, unsupportedMedia
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .loginRequired: return "请登录元宝后继续下载视频号"
        case .invalidResponse: return "视频号解析响应不完整，请稍后重试"
        case .noMedia: return "此内容没有可下载的视频地址"
        case .unsupportedMedia: return "暂不支持此内容类型或加密格式，请使用普通视频分享链接"
        case .unavailable(let message): return message
        }
    }
}

nonisolated struct WeChatChannelsReference: Sendable {
    let token: String
    let exportID: String
}

nonisolated struct WeChatChannelsMedia: Sendable {
    let id: String
    let videoURL: URL
    let title: String?
    let coverURL: String?
}

/// Protocol parsing kept separate from networking and account storage.
nonisolated enum WeChatChannelsParser {
    static func normalizedShareURL(_ url: URL) -> URL? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return nil }
        let host = url.host?.lowercased()
        let id: String?
        if host == "weixin.qq.com", url.path.hasPrefix("/sph/") {
            id = String(url.path.dropFirst(5)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else if host == "channels.weixin.qq.com", url.path == "/finder-preview/pages/sph" {
            id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "id" }?.value
        } else { return nil }
        guard let id, !id.isEmpty, id.count <= 256,
              id.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "https://weixin.qq.com/sph/\(id)")
    }

    static func parsePlayableReference(_ data: Data) throws -> WeChatChannelsReference {
        let root = try dictionary(data)
        let code = integer(root["code"])
        if let code, code != 0 {
            let message = plainText(root["msg"] as? String ?? "")
            if code == 401 || code == 403 || isLoginMessage(message) { throw WeChatChannelsError.loginRequired }
            throw WeChatChannelsError.unavailable(message.isEmpty ? "元宝暂时无法解析此链接（\(code)）" : message)
        }
        guard code == 0, let body = root["data"] as? [String: Any],
              let raw = body["playable_url"] as? String,
              let url = URLComponents(string: raw), url.scheme == "https",
              url.host?.lowercased() == "channels.weixin.qq.com", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              url.path == "/finder-preview/pages/feed",
              let token = url.queryItems?.first(where: { $0.name == "token" })?.value, !token.isEmpty,
              let eid = url.queryItems?.first(where: { $0.name == "eid" })?.value, !eid.isEmpty else {
            throw WeChatChannelsError.invalidResponse
        }
        return WeChatChannelsReference(token: token, exportID: eid)
    }

    static func parseFeed(_ data: Data, id: String) throws -> WeChatChannelsMedia {
        let root = try dictionary(data)
        guard let code = integer(root["errCode"]) else { throw WeChatChannelsError.invalidResponse }
        if code != 0 {
            let message = plainText(root["errMsg"] as? String ?? "")
            if code == 401 || code == 403 || isLoginMessage(message) { throw WeChatChannelsError.loginRequired }
            throw WeChatChannelsError.unavailable(message.isEmpty ? "视频号解析失败（\(code)）" : message)
        }
        guard let body = root["data"] as? [String: Any] else { throw WeChatChannelsError.invalidResponse }
        if let error = body["errMsg"] as? [String: Any] {
            let message = [error["title"], error["content"]].compactMap { $0 as? String }.map(plainText).filter { !$0.isEmpty }.joined(separator: "：")
            if (integer(error["type"]) ?? 0) != 0 || !message.isEmpty {
                if isLoginMessage(message) { throw WeChatChannelsError.loginRequired }
                throw WeChatChannelsError.unavailable(message.isEmpty ? "此视频暂时无法播放" : message)
            }
        }
        guard let feed = body["feedInfo"] as? [String: Any] else { throw WeChatChannelsError.noMedia }
        if let type = integer(feed["mediaType"]), type != 4 { throw WeChatChannelsError.unsupportedMedia }
        let h264 = feed["h264VideoInfo"] as? [String: Any] ?? [:]
        let h265 = feed["h265VideoInfo"] as? [String: Any] ?? [:]
        for source in [feed, h264, h265] {
            if let key = source["decodeKey"], String(describing: key) != "0", String(describing: key) != "" {
                throw WeChatChannelsError.unsupportedMedia
            }
        }
        guard let videoURL = [h264["videoUrl"], h265["videoUrl"], feed["videoUrl"]]
            .compactMap({ $0 as? String }).compactMap(mediaURL).first else { throw WeChatChannelsError.noMedia }
        return WeChatChannelsMedia(id: id, videoURL: videoURL, title: feed["description"] as? String, coverURL: feed["coverUrl"] as? String)
    }

    static func mediaURL(_ value: String) -> URL? {
        guard var url = URLComponents(string: value), ["http", "https"].contains(url.scheme ?? ""),
              let host = url.host?.lowercased(), host == "finder.video.qq.com" || host.hasSuffix(".video.qq.com"),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return nil }
        url.scheme = "https"
        return url.url
    }

    static func eligibleCookies(_ cookies: [HTTPCookie], now: Date = Date()) -> [HTTPCookie] {
        cookies.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let path = cookie.path
            let target = "/api/weixin/get_parse_result"
            let pathMatches = target == path || (target.hasPrefix(path) && (path.hasSuffix("/") || target.dropFirst(path.count).hasPrefix("/")))
            return ["tencent.com", "yuanbao.tencent.com"].contains(domain)
                && (cookie.expiresDate.map { $0 > now } ?? true) && pathMatches
                && !cookie.name.isEmpty && !cookie.value.isEmpty
                && !cookie.value.contains("\r") && !cookie.value.contains("\n")
        }.sorted { $0.path.count > $1.path.count }
    }

    static func cookieHeader(_ cookies: [HTTPCookie], now: Date = Date()) -> String {
        eligibleCookies(cookies, now: now).map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    static func isAuthenticatedUser(_ data: Data) -> Bool {
        guard let root = try? dictionary(data), integer(root["status"]) == 2,
              let id = root["userId"] as? String, !id.isEmpty,
              let anon = root["anonUser"] as? [String: Any],
              let isAnonymous = anon["isAnon"] as? Bool else { return false }
        return !isAnonymous
    }

    private static func dictionary(_ data: Data) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw WeChatChannelsError.invalidResponse }
        return root
    }
    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        return (value as? String).flatMap(Int.init)
    }
    private static func isLoginMessage(_ message: String) -> Bool {
        message.contains("登录") || message.lowercased().contains("login") || message.contains("凭证过期")
    }
    private static func plainText(_ value: String) -> String {
        String(value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ").trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
    }
}
