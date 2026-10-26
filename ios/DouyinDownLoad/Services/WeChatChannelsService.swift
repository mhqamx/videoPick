import Foundation

/// Direct Tencent requests only. Credentials never enter the app's backend cookie map.
actor WeChatChannelsService {
    static let shared = WeChatChannelsService()
    private let session: URLSession
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36"

    init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        self.session = session ?? URLSession(configuration: config, delegate: ChannelsRedirectGuard(), delegateQueue: nil)
    }

    func validateSession(cookie: String) async throws {
        guard !cookie.isEmpty, !cookie.contains("\r"), !cookie.contains("\n") else { throw WeChatChannelsError.loginRequired }
        var request = request("https://yuanbao.tencent.com/api/getuserinfo")
        request.httpMethod = "GET"
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("https://yuanbao.tencent.com/", forHTTPHeaderField: "Referer")
        guard try WeChatChannelsParser.isAuthenticatedUser(await send(request)) else { throw WeChatChannelsError.loginRequired }
    }

    func resolve(_ url: URL, cookie: String) async throws -> WeChatChannelsMedia {
        guard !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WeChatChannelsError.loginRequired }
        guard !cookie.contains("\r"), !cookie.contains("\n"),
              let shareURL = WeChatChannelsParser.normalizedShareURL(url) else { throw WeChatChannelsError.invalidResponse }
        try Task.checkCancellation()
        var parseRequest = request("https://yuanbao.tencent.com/api/weixin/get_parse_result")
        parseRequest.setValue(cookie, forHTTPHeaderField: "Cookie")
        parseRequest.setValue("https://yuanbao.tencent.com", forHTTPHeaderField: "Origin")
        parseRequest.setValue("https://yuanbao.tencent.com/chat/naQivTmsDa", forHTTPHeaderField: "Referer")
        parseRequest.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        parseRequest.httpBody = try JSONSerialization.data(withJSONObject: ["type": "video_channel_url", "url": shareURL.absoluteString, "scene": 1])
        let reference = try WeChatChannelsParser.parsePlayableReference(await send(parseRequest))
        try Task.checkCancellation()
        var endpoint = URLComponents(string: "https://channels.weixin.qq.com/finder-preview/api/feed/get_feed_info")!
        endpoint.queryItems = [
            URLQueryItem(name: "_rid", value: "\(String(Int(Date().timeIntervalSince1970), radix: 16))-\(UUID().uuidString.prefix(8).lowercased())"),
            URLQueryItem(name: "_pageUrl", value: "https://channels.weixin.qq.com/finder-preview/pages/feed")
        ]
        var feedRequest = request(endpoint.url!.absoluteString)
        feedRequest.setValue("https://channels.weixin.qq.com", forHTTPHeaderField: "Origin")
        var referer = URLComponents(string: "https://channels.weixin.qq.com/finder-preview/pages/feed")!
        referer.queryItems = [URLQueryItem(name: "token", value: reference.token), URLQueryItem(name: "eid", value: reference.exportID), URLQueryItem(name: "appid", value: "0"), URLQueryItem(name: "entry_card_type", value: "48"), URLQueryItem(name: "comment_scene", value: "39"), URLQueryItem(name: "entry_scene", value: "0")]
        feedRequest.setValue(referer.url!.absoluteString, forHTTPHeaderField: "Referer")
        feedRequest.httpBody = try JSONSerialization.data(withJSONObject: ["baseReq": ["generalToken": reference.token], "exportId": reference.exportID])
        return try WeChatChannelsParser.parseFeed(await send(feedRequest), id: shareURL.lastPathComponent)
    }

    private func request(_ url: String) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WeChatChannelsError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 || (300..<400).contains(http.statusCode) { throw WeChatChannelsError.loginRequired }
        guard (200..<300).contains(http.statusCode) else { throw WeChatChannelsError.unavailable("视频号服务暂时不可用（HTTP \(http.statusCode)）") }
        return data
    }
}

/// API endpoints must not redirect an authenticated request to a different origin.
nonisolated final class ChannelsRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
