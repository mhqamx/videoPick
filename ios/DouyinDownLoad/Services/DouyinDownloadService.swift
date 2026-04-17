//
//  DouyinDownloadService.swift
//  DouyinDownLoad
//
//  Created by 马霄 on 2026/2/2.
//

import Foundation

#if canImport(Photos)
import Photos
#endif

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 抖音视频下载服务 (线程安全)
actor DouyinDownloadService {
    static let shared = DouyinDownloadService()
    private let backendResolveURLs: [URL] = [
//        URL(string: "http://127.0.0.1:8000/resolve")!,
        URL(string: "https://jv4mmmmt3fw4hq7qdmqmszohbi0jrvhc.lambda-url.ap-northeast-1.on.aws/resolve")!,
    ]

    private init() {}

    private func log(_ message: String) {
        print("[DouyinDownloadService] \(message)")
    }

    // MARK: - 公共 API

    /// 一步完成:解析并下载视频
    func parseAndDownload(_ text: String, progress: @Sendable (Double) -> Void = { _ in }) async throws -> DouyinVideoInfo {
        log("parseAndDownload start, input length: \(text.count)")
        var videoInfo: DouyinVideoInfo

        // 提取 URL 判断平台，抖音/小红书/Instagram/X 链接优先本地解析
        let extractedURL = try? extractURL(from: text)
        let isDouyin = extractedURL.map { isDouyinURL($0) } ?? false
        let isXiaohongshu = extractedURL.map { isXiaohongshuURL($0) } ?? false
        let isInstagram = extractedURL.map { isInstagramURL($0) } ?? false
        let isX = extractedURL.map { isXURL($0) } ?? false
        let isKuaishou = extractedURL.map { isKuaishouURL($0) } ?? false

        if isInstagram {
            log("detected instagram URL, local only (requires cookie)")
            videoInfo = try await resolveInstagramLocally(extractedURL!)
            log("local instagram resolve success")
        } else if isX {
            log("detected X URL, local only (requires cookie)")
            videoInfo = try await resolveXLocally(extractedURL!)
            log("local X resolve success")
        } else if isKuaishou {
            log("detected kuaishou URL, try local parser first")
            do {
                videoInfo = try await resolveKuaishouLocally(extractedURL!)
                log("local kuaishou resolve success")
            } catch {
                log("local kuaishou resolve failed: \(error.localizedDescription), fallback to backend")
                do {
                    videoInfo = try await resolveViaBackend(text: text)
                    log("resolve via backend success")
                } catch let backendError {
                    throw DouyinDownloadError.backendResolveFailed(
                        reason: "快手本地解析失败: \(error.localizedDescription)；服务端解析失败: \(backendError.localizedDescription)"
                    )
                }
            }
        } else if isDouyin {
            log("detected douyin URL, local only (no backend fallback)")
            videoInfo = try await resolveDouyinShortURL(extractedURL!)
            log("local douyin resolve success")
        } else if isXiaohongshu {
            log("detected xiaohongshu URL, try local parser first")
            do {
                videoInfo = try await resolveXiaohongshuLocally(extractedURL!)
                log("local xiaohongshu resolve success")
            } catch {
                log("local xiaohongshu resolve failed: \(error.localizedDescription), fallback to backend")
                do {
                    videoInfo = try await resolveViaBackend(text: text)
                    log("resolve via backend success")
                } catch let backendError {
                    throw DouyinDownloadError.backendResolveFailed(
                        reason: "小红书本地解析失败: \(error.localizedDescription)；服务端解析失败: \(backendError.localizedDescription)"
                    )
                }
            }
        } else {
            do {
                videoInfo = try await resolveViaBackend(text: text)
                log("resolve via backend success")
            } catch {
                log("resolve via backend failed: \(error.localizedDescription)")
                throw DouyinDownloadError.backendResolveFailed(reason: "当前链接仅支持服务端解析，请检查 backend 服务是否可用")
            }
        }

        log("resolved media id: \(videoInfo.id), type: \(videoInfo.mediaType.rawValue), download url: \(videoInfo.downloadURL.absoluteString)")

        switch videoInfo.mediaType {
        case .video:
            let localURL = try await downloadVideo(from: videoInfo.downloadURL, id: videoInfo.id, progress: progress)
            videoInfo.localURL = localURL
            log("parseAndDownload video success, local file: \(localURL.path)")
        case .images:
            let localImages = try await downloadImages(urls: videoInfo.imageURLs, id: videoInfo.id, progress: progress)
            videoInfo.localImageURLs = localImages
            log("parseAndDownload images success, count: \(localImages.count)")
        }

        return videoInfo
    }

    /// 保存视频到相册 (iOS) 或下载目录 (macOS/Mac Catalyst)
    func saveVideo(videoURL: URL) async throws -> URL? {
        #if targetEnvironment(macCatalyst)
        return try saveToDownloads(videoURL: videoURL)
        #elseif os(iOS)
        try await saveToAlbum(videoURL: videoURL)
        return nil
        #else
        return try saveToDownloads(videoURL: videoURL)
        #endif
    }

    /// 保存多张图片到相册
    func saveImages(imageURLs: [URL]) async throws {
        #if !targetEnvironment(macCatalyst)
        log("saveImages start, count: \(imageURLs.count)")
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw DouyinDownloadError.noPermission
        }

        for (index, imageURL) in imageURLs.enumerated() {
            guard let imageData = try? Data(contentsOf: imageURL),
                  let image = UIImage(data: imageData) else {
                log("saveImages[\(index)] failed to load image data")
                continue
            }

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                } completionHandler: { success, error in
                    if success {
                        self.log("saveImages[\(index)] success")
                        continuation.resume()
                    } else {
                        let errorMsg = error?.localizedDescription ?? "未知错误"
                        self.log("saveImages[\(index)] failed: \(errorMsg)")
                        continuation.resume(throwing: DouyinDownloadError.saveFailed(reason: errorMsg))
                    }
                }
            }
        }
        log("saveImages all done")
        #else
        // macOS: 保存到下载目录
        for imageURL in imageURLs {
            _ = try saveToDownloads(videoURL: imageURL)
        }
        #endif
    }

    #if !targetEnvironment(macCatalyst)
    private func saveToAlbum(videoURL: URL) async throws {
        log("saveToAlbum start: \(videoURL.path)")
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        log("photo permission status: \(status.rawValue)")
        guard status == .authorized || status == .limited else {
            throw DouyinDownloadError.noPermission
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
            } completionHandler: { success, error in
                if success {
                    self.log("saveToAlbum success")
                    continuation.resume()
                } else {
                    let errorMsg = error?.localizedDescription ?? "未知错误"
                    self.log("saveToAlbum failed: \(errorMsg)")
                    continuation.resume(throwing: DouyinDownloadError.saveFailed(reason: errorMsg))
                }
            }
        }
    }
    #endif

    private func saveToDownloads(videoURL: URL) throws -> URL {
        log("saveToDownloads start: \(videoURL.path)")
        guard let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw DouyinDownloadError.saveFailed(reason: "无法访问下载目录")
        }
        let destURL = downloadsDir.appendingPathComponent(videoURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: videoURL, to: destURL)
        log("saveToDownloads success: \(destURL.path)")
        return destURL
    }

    // MARK: - 内部方法

    /// 从文本中提取 URL
    func extractURL(from text: String) throws -> URL {
        let pattern = #"https?://[^\s]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else {
            throw DouyinDownloadError.invalidURL
        }

        let urlString = String(text[range])
        log("extractURL matched: \(urlString)")
        guard let url = URL(string: urlString) else {
            throw DouyinDownloadError.invalidURL
        }

        return url
    }

    /// 解析抖音短链接
    func resolveDouyinShortURL(_ url: URL) async throws -> DouyinVideoInfo {
        log("resolveDouyinShortURL start: \(url.absoluteString)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.addValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.addValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.addValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.addValue("https://www.douyin.com/", forHTTPHeaderField: "Referer")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DouyinDownloadError.urlResolutionFailed
        }
        log("resolve response status: \(httpResponse.statusCode), final url: \(httpResponse.url?.absoluteString ?? "nil"), bytes: \(data.count)")

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DouyinDownloadError.downloadFailed(statusCode: httpResponse.statusCode)
        }

        guard let htmlString = String(data: data, encoding: .utf8) else {
            throw DouyinDownloadError.videoDataNotFound
        }

        do {
            return try parseVideoInfo(from: htmlString)
        } catch {
            if let finalURL = httpResponse.url,
               finalURL.path.contains("/share/slides/"),
               let rewritten = rewriteSlidesToVideo(finalURL) {
                log("slides share page missing JSON, retry with /share/video/: \(rewritten.absoluteString)")
                return try await fetchAndParseIesdouyin(rewritten)
            }
            throw error
        }
    }

    private func rewriteSlidesToVideo(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.path = components.path.replacingOccurrences(of: "/share/slides/", with: "/share/video/")
        return components.url
    }

    private func fetchAndParseIesdouyin(_ url: URL) async throws -> DouyinVideoInfo {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.addValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.addValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.addValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.addValue("https://www.douyin.com/", forHTTPHeaderField: "Referer")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let htmlString = String(data: data, encoding: .utf8) else {
            throw DouyinDownloadError.videoDataNotFound
        }
        log("slides retry response bytes: \(data.count)")
        return try parseVideoInfo(from: htmlString)
    }

    private func resolveViaBackend(text: String) async throws -> DouyinVideoInfo {
        struct BackendRequest: Codable {
            let text: String
            let cookies: [String: [String: String]]?
        }

        struct BackendFormat: Codable {
            let format_id: String?
            let ext: String?
            let width: Int?
            let height: Int?
        }

        struct BackendResponse: Codable {
            let input_url: String
            let webpage_url: String?
            let title: String?
            let uploader: String?
            let duration: Double?
            let video_id: String?
            let download_url: String
            let formats: [BackendFormat]?
            let media_type: String?
            let image_urls: [String]?
        }

        struct BackendError: Codable {
            let detail: String
        }

        var lastError: String = "unknown"

        for backendResolveURL in backendResolveURLs {
            do {
                log("resolveViaBackend start: \(backendResolveURL.absoluteString)")
                var request = URLRequest(url: backendResolveURL)
                request.httpMethod = "POST"
                request.timeoutInterval = 30
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                let clientCookies = CookieStore.shared.allCookies()
                request.httpBody = try JSONEncoder().encode(
                    BackendRequest(text: text, cookies: clientCookies.isEmpty ? nil : clientCookies)
                )

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastError = "invalid response"
                    continue
                }

                log("resolveViaBackend status: \(http.statusCode), bytes: \(data.count)")

                guard (200..<300).contains(http.statusCode) else {
                    let backendError = try? JSONDecoder().decode(BackendError.self, from: data)
                    lastError = backendError?.detail ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                    continue
                }

                let decoded = try JSONDecoder().decode(BackendResponse.self, from: data)
                guard let resolvedDownloadURL = normalizeBackendDownloadURL(
                    rawDownloadURL: decoded.download_url,
                    backendResolveURL: backendResolveURL
                ) else {
                    lastError = "invalid download_url"
                    continue
                }

                let resolvedID = (decoded.video_id?.isEmpty == false ? decoded.video_id : nil)
                    ?? extractVideoIDFromURL(decoded.webpage_url)
                    ?? "unknown_\(Int(Date().timeIntervalSince1970))"

                let mediaType: MediaType = (decoded.media_type == "image") ? .images : .video
                let imageURLs: [URL] = (decoded.image_urls ?? []).compactMap { urlStr in
                    normalizeBackendDownloadURL(rawDownloadURL: urlStr, backendResolveURL: backendResolveURL)
                }

                let info = DouyinVideoInfo(
                    id: resolvedID,
                    downloadURL: resolvedDownloadURL,
                    localURL: nil,
                    title: decoded.title,
                    coverURL: nil,
                    mediaType: mediaType,
                    imageURLs: imageURLs
                )
                return info
            } catch {
                lastError = error.localizedDescription
                log("resolveViaBackend request error: \(lastError)")
            }
        }

        throw DouyinDownloadError.backendResolveFailed(reason: lastError)
    }

    private func normalizeBackendDownloadURL(rawDownloadURL: String, backendResolveURL: URL) -> URL? {
        // 有些反向代理场景下后端会返回 localhost 下载地址,这里替换为当前 backend 域名
        if var components = URLComponents(string: rawDownloadURL) {
            let host = components.host?.lowercased()
            if host == "localhost" || host == "127.0.0.1" || host == "::1" {
                if let backendComponents = URLComponents(url: backendResolveURL, resolvingAgainstBaseURL: false) {
                    components.scheme = backendComponents.scheme
                    components.host = backendComponents.host
                    components.port = backendComponents.port
                    return components.url
                }
            }
            if components.host != nil {
                return components.url
            }
        }

        // 如果返回的是相对路径,拼到 backend 域名上
        if rawDownloadURL.hasPrefix("/") {
            return URL(string: rawDownloadURL, relativeTo: backendResolveURL.deletingLastPathComponent())?.absoluteURL
        }

        return URL(string: rawDownloadURL)
    }

    private func extractVideoIDFromURL(_ urlString: String?) -> String? {
        guard let urlString,
              let regex = try? NSRegularExpression(pattern: #"/video/(\d+)"#),
              let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
              let range = Range(match.range(at: 1), in: urlString) else {
            return nil
        }
        return String(urlString[range])
    }

    private func isDouyinURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }
        return host.contains("douyin.com") || host.contains("iesdouyin.com")
    }

    private func isXiaohongshuURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("xiaohongshu.com") || host.contains("xhslink.com")
    }

    private func isInstagramURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("instagram.com")
    }

    private func isXURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("x.com") || host.contains("twitter.com")
    }

    private func isKuaishouURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("kuaishou.com")
    }

    /// 从 HTML 中解析视频信息 (使用增强的 JSON 解析)
    private func parseVideoInfo(from html: String) throws -> DouyinVideoInfo {
        log("parseVideoInfo start, html bytes: \(html.utf8.count)")
        // 支持多种 JSON 数据模式
        let patterns = [
            #"window\._ROUTER_DATA\s*=\s*(\{.*?\})(?:\s*</script>|\s*;)"#,
            #"window\._SSR_HYDRATED_DATA\s*=\s*(\{.*?\})(?:\s*</script>|\s*;)"#,
            #"<script[^>]*id=\"RENDER_DATA\"[^>]*>(.*?)</script>"#
        ]

        var jsonString: String?
        var isRenderData = false

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
                let range = NSRange(location: 0, length: html.utf16.count)
                if let match = regex.firstMatch(in: html, options: [], range: range) {
                    if let range1 = Range(match.range(at: 1), in: html) {
                        jsonString = String(html[range1]).trimmingCharacters(in: .whitespacesAndNewlines)
                        isRenderData = pattern.contains("RENDER_DATA")
                        log("matched data pattern: \(pattern)")
                        break
                    }
                }
            }
        }

        // Fallback: 直接从 HTML 提取播放链接
        if jsonString == nil {
            log("no json matched, fallback to raw html")
            if let fallbackInfo = parseFromRawHTML(html) {
                log("fallback raw html parse success: \(fallbackInfo.downloadURL.absoluteString)")
                return fallbackInfo
            }
            throw DouyinDownloadError.videoDataNotFound
        }

        guard var jsonStr = jsonString else {
            throw DouyinDownloadError.videoDataNotFound
        }

        // RENDER_DATA 通常是 URL 编码 JSON
        if isRenderData {
            jsonStr = jsonStr.removingPercentEncoding ?? jsonStr
            log("decoded RENDER_DATA")
        }

        // 处理 JavaScript 中的 undefined
        jsonStr = jsonStr.replacingOccurrences(of: "undefined", with: "null")

        guard let jsonData = jsonStr.data(using: .utf8),
              let dataObj = try? JSONSerialization.jsonObject(with: jsonData) else {
            throw DouyinDownloadError.videoDataNotFound
        }

        if let info = parseFromJSON(dataObj) {
            log("parseFromJSON success: \(info.downloadURL.absoluteString)")
            return info
        }

        if let fallbackInfo = parseFromRawHTML(html) {
            log("parseFromJSON failed, fallback raw html success: \(fallbackInfo.downloadURL.absoluteString)")
            return fallbackInfo
        }

        log("parseVideoInfo failed: no video link found")
        throw DouyinDownloadError.noVideoLinkFound
    }

    private func parseFromJSON(_ root: Any) -> DouyinVideoInfo? {
        if let dict = root as? [String: Any],
           let loaderData = dict["loaderData"] as? [String: Any] {
            for value in loaderData.values {
                if let data = value as? [String: Any],
                   let videoInfoRes = data["videoInfoRes"] as? [String: Any],
                   let itemList = videoInfoRes["item_list"] as? [[String: Any]],
                   let firstItem = itemList.first {
                    // 图文作品优先检测
                    if isDouyinImagePost(firstItem), let parsed = buildImageInfo(from: firstItem) {
                        return parsed
                    }
                    if let parsed = buildVideoInfo(from: firstItem) {
                        return parsed
                    }
                }
            }
        }

        // 先尝试图文
        if let aweme = findFirstDictionary(containing: "images", in: root),
           isDouyinImagePost(aweme),
           let parsed = buildImageInfo(from: aweme) {
            return parsed
        }

        if let aweme = findFirstDictionary(containing: "video", in: root),
           let parsed = buildVideoInfo(from: aweme) {
            return parsed
        }

        if let url = findBestVideoURL(in: root) {
            return buildFallbackVideoInfo(with: url, title: findFirstString(forKey: "desc", in: root))
        }

        return nil
    }

    /// 判断一个抖音 item 是否为图文作品
    private func isDouyinImagePost(_ item: [String: Any]) -> Bool {
        if let awemeType = item["aweme_type"] as? Int, awemeType == 2 { return true }
        if let awemeType = item["aweme_type"] as? String, awemeType == "2" { return true }
        if let images = item["images"] as? [Any], !images.isEmpty { return true }
        return false
    }

    /// 从图文作品 item 中提取图片 URL 列表
    private func buildImageInfo(from item: [String: Any]) -> DouyinVideoInfo? {
        guard let images = item["images"] as? [[String: Any]], !images.isEmpty else { return nil }

        var imageURLs: [URL] = []
        for img in images {
            guard let urlList = img["url_list"] as? [String], !urlList.isEmpty else { continue }
            // 优先选 jpeg/jpg，其次任意可用 URL
            var chosen: String?
            for u in urlList where !u.isEmpty {
                if chosen == nil { chosen = u }
                let lower = u.lowercased()
                if lower.contains("jpeg") || lower.contains("jpg") {
                    chosen = u
                    break
                }
            }
            if let chosen, let url = URL(string: chosen) {
                imageURLs.append(url)
            }
        }

        guard !imageURLs.isEmpty else { return nil }

        let awemeId = item["aweme_id"] as? String ?? "unknown_\(Int(Date().timeIntervalSince1970))"
        let title = item["desc"] as? String

        log("buildImageInfo success, awemeId: \(awemeId), imageCount: \(imageURLs.count)")

        return DouyinVideoInfo(
            id: awemeId,
            downloadURL: imageURLs[0],
            title: title,
            mediaType: .images,
            imageURLs: imageURLs
        )
    }

    private func buildVideoInfo(from item: [String: Any]) -> DouyinVideoInfo? {
        guard let video = item["video"] as? [String: Any],
              let playAddr = video["play_addr"] as? [String: Any],
              let urlList = playAddr["url_list"] as? [String],
              let firstUrl = urlList.first else {
            return nil
        }

        let awemeId = item["aweme_id"] as? String ?? "unknown_\(Int(Date().timeIntervalSince1970))"
        let title = item["desc"] as? String

        // 将有水印链接转换为无水印链接
        let finalUrlStr = normalizeVideoURL(firstUrl)

        guard let downloadURL = URL(string: finalUrlStr) else {
            return nil
        }

        log("buildVideoInfo success, awemeId: \(awemeId), rawUrl: \(firstUrl), normalized: \(finalUrlStr)")

        return DouyinVideoInfo(
            id: awemeId,
            downloadURL: downloadURL,
            localURL: nil,
            title: title,
            coverURL: nil
        )
    }

    private func parseFromRawHTML(_ html: String) -> DouyinVideoInfo? {
        let patterns = [
            #"(https?:\\/\\/[^\"']+aweme\\/v1\\/playwm?\\/[^\"']*)"#,
            #"(https?:\\/\\/[^\"']+\\.mp4[^\"']*)"#,
            #"(https?://[^\"']+aweme/v1/playwm?/[^\"']*)"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: html.utf16.count)
                if let match = regex.firstMatch(in: html, options: [], range: range),
                   let matchRange = Range(match.range(at: 1), in: html) {
                    let escaped = String(html[matchRange])
                        .replacingOccurrences(of: "\\/", with: "/")
                    let normalized = normalizeVideoURL(escaped)
                    if let url = URL(string: normalized) {
                        log("parseFromRawHTML hit, raw: \(escaped), normalized: \(normalized)")
                        return buildFallbackVideoInfo(with: url, title: nil)
                    }
                }
            }
        }

        return nil
    }

    private func buildFallbackVideoInfo(with url: URL, title: String?) -> DouyinVideoInfo {
        return DouyinVideoInfo(
            id: "unknown_\(Int(Date().timeIntervalSince1970))",
            downloadURL: url,
            localURL: nil,
            title: title,
            coverURL: nil
        )
    }

    private func normalizeVideoURL(_ raw: String) -> String {
        var url = raw.replacingOccurrences(of: "playwm", with: "play")
        if var components = URLComponents(string: url) {
            components.queryItems = components.queryItems?.filter { !["watermark", "logo_name"].contains($0.name) }
            url = components.url?.absoluteString ?? url
        }
        if url != raw {
            log("normalizeVideoURL: \(raw) -> \(url)")
        }
        return url
    }

    private func findFirstDictionary(containing key: String, in value: Any, maxDepth: Int = 15) -> [String: Any]? {
        guard maxDepth > 0 else { return nil }
        if let dict = value as? [String: Any] {
            if dict[key] != nil { return dict }
            for child in dict.values {
                if let found = findFirstDictionary(containing: key, in: child, maxDepth: maxDepth - 1) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = findFirstDictionary(containing: key, in: child, maxDepth: maxDepth - 1) {
                    return found
                }
            }
        }
        return nil
    }

    private func findFirstString(forKey targetKey: String, in value: Any, maxDepth: Int = 15) -> String? {
        guard maxDepth > 0 else { return nil }
        if let dict = value as? [String: Any] {
            if let v = dict[targetKey] as? String { return v }
            for child in dict.values {
                if let found = findFirstString(forKey: targetKey, in: child, maxDepth: maxDepth - 1) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = findFirstString(forKey: targetKey, in: child, maxDepth: maxDepth - 1) {
                    return found
                }
            }
        }
        return nil
    }

    private func findBestVideoURL(in value: Any) -> URL? {
        var candidates: [String] = []
        collectVideoURLCandidates(from: value, into: &candidates)
        if let best = candidates.first(where: { $0.contains("aweme/v1/play") || $0.contains(".mp4") }) {
            return URL(string: normalizeVideoURL(best))
        }
        if let first = candidates.first {
            return URL(string: normalizeVideoURL(first))
        }
        return nil
    }

    private func collectVideoURLCandidates(from value: Any, into candidates: inout [String], maxDepth: Int = 15) {
        guard maxDepth > 0 else { return }
        if let dict = value as? [String: Any] {
            for (key, child) in dict {
                if key == "url_list", let arr = child as? [String] {
                    candidates.append(contentsOf: arr)
                } else if let str = child as? String,
                          str.hasPrefix("http"),
                          (str.contains("play") || str.contains("video") || str.contains(".mp4")) {
                    candidates.append(str)
                } else {
                    collectVideoURLCandidates(from: child, into: &candidates, maxDepth: maxDepth - 1)
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectVideoURLCandidates(from: child, into: &candidates, maxDepth: maxDepth - 1)
            }
        }
    }


    /// 下载多张图片，返回本地路径列表
    func downloadImages(urls: [URL], id: String, progress: @Sendable (Double) -> Void = { _ in }) async throws -> [URL] {
        guard !urls.isEmpty else { return [] }
        log("downloadImages start, id: \(id), count: \(urls.count)")

        var localURLs: [URL] = []
        let total = Double(urls.count)

        for (index, url) in urls.enumerated() {
            try Task.checkCancellation()

            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.addValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            request.addValue("*/*", forHTTPHeaderField: "Accept")

            // 根据图片域名设置对应 Referer 和 headers
            applyPlatformDownloadHeaders(to: &request, targetURL: url)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  !data.isEmpty else {
                log("downloadImages[\(index)] failed, status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                continue
            }

            // 根据 content-type 确定扩展名
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            let ext: String
            if contentType.contains("webp") {
                ext = "webp"
            } else if contentType.contains("png") {
                ext = "png"
            } else {
                ext = "jpeg"
            }

            let fileName = "douyin_\(id)_\(index).\(ext)"
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try data.write(to: fileURL)
            localURLs.append(fileURL)

            progress(Double(index + 1) / total)
            log("downloadImages[\(index)] saved: \(fileURL.lastPathComponent), bytes: \(data.count)")
        }

        guard !localURLs.isEmpty else {
            throw DouyinDownloadError.videoDataNotFound
        }

        return localURLs
    }

    /// 下载视频（流式写入，支持进度回调）
    func downloadVideo(from url: URL, id: String, progress: @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        let candidates = candidateDownloadURLs(from: url)
        log("downloadVideo start, id: \(id), candidates: \(candidates.map(\.absoluteString))")

        var lastStatusCode = -1
        var lastError: Error?

        for (index, candidate) in candidates.enumerated() {
            let fileName = "douyin_\(id).mp4"
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
            }
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)

            var receivedBytes: Int64 = 0
            var totalBytes: Int64 = -1
            let maxResumeAttempts = 4
            var resumeAttempt = 0

            while resumeAttempt < maxResumeAttempts {
                var request = URLRequest(url: candidate)
                // 大文件下载与弱网下给足超时
                request.timeoutInterval = 180
                request.addValue("*/*", forHTTPHeaderField: "Accept")
                request.addValue("bytes=\(max(receivedBytes, 0))-", forHTTPHeaderField: "Range")
                applyPlatformDownloadHeaders(to: &request, targetURL: candidate)

                do {
                    let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        log("download attempt[\(index).\(resumeAttempt)] invalid response")
                        break
                    }

                    lastStatusCode = httpResponse.statusCode
                    log("download attempt[\(index).\(resumeAttempt)] status: \(httpResponse.statusCode), expectedLength: \(httpResponse.expectedContentLength), url: \(candidate.absoluteString)")

                    guard (200..<300).contains(httpResponse.statusCode) else {
                        break
                    }

                    // 某些 CDN 会忽略 Range，返回 200 全量，此时重置本地进度避免重复写入
                    if httpResponse.statusCode == 200 && receivedBytes > 0 {
                        receivedBytes = 0
                        totalBytes = -1
                        try? FileManager.default.removeItem(at: fileURL)
                        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
                    }

                    if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range"),
                       let slashIdx = contentRange.lastIndex(of: "/") {
                        let totalPart = contentRange[contentRange.index(after: slashIdx)...]
                        if let parsedTotal = Int64(totalPart) {
                            totalBytes = parsedTotal
                        }
                    } else if httpResponse.statusCode == 200, httpResponse.expectedContentLength > 0 {
                        totalBytes = httpResponse.expectedContentLength
                    }

                    let fileHandle = try FileHandle(forWritingTo: fileURL)
                    defer { try? fileHandle.close() }
                    try? fileHandle.seekToEnd()

                    let bufferSize = 65_536 // 64 KB
                    var buffer = Data(capacity: bufferSize)

                    for try await byte in asyncBytes {
                        try Task.checkCancellation()
                        buffer.append(byte)
                        if buffer.count >= bufferSize {
                            fileHandle.write(buffer)
                            receivedBytes += Int64(buffer.count)
                            buffer.removeAll(keepingCapacity: true)
                            if totalBytes > 0 {
                                progress(min(1.0, Double(receivedBytes) / Double(totalBytes)))
                            }
                        }
                    }

                    if !buffer.isEmpty {
                        fileHandle.write(buffer)
                        receivedBytes += Int64(buffer.count)
                    }

                    guard receivedBytes > 0 else { break }

                    if totalBytes > 0 && receivedBytes < totalBytes {
                        resumeAttempt += 1
                        log("download attempt[\(index).\(resumeAttempt)] incomplete: \(receivedBytes)/\(totalBytes), retry resume")
                        continue
                    }

                    progress(1.0)
                    log("downloadVideo success, file written: \(fileURL.path), bytes: \(receivedBytes)")
                    return fileURL
                } catch is CancellationError {
                    log("download cancelled by user")
                    throw CancellationError()
                } catch {
                    lastError = error
                    log("download attempt[\(index).\(resumeAttempt)] error: \(error.localizedDescription), received: \(receivedBytes)")
                    if isRetriableNetworkError(error), receivedBytes > 0 {
                        resumeAttempt += 1
                        continue
                    }
                    break
                }
            }
        }

        if let lastError {
            throw lastError
        }
        throw DouyinDownloadError.downloadFailed(statusCode: lastStatusCode)
    }

    private func isRetriableNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .networkConnectionLost, .timedOut, .cannotConnectToHost, .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    private func candidateDownloadURLs(from url: URL) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []

        func append(_ str: String) {
            guard let u = URL(string: str) else { return }
            let key = u.absoluteString
            guard !seen.contains(key) else { return }
            seen.insert(key)
            result.append(u)
        }

        let original = url.absoluteString
        append(original)

        // backend 代理地址优先尝试原始 source，避免对 source 参数做二次拼接导致 URL 损坏
        if let sourceURL = extractBackendProxySourceURL(from: url) {
            append(sourceURL.absoluteString)
            return result
        }

        // 回退到有水印地址(部分视频仅该地址可用)
        append(original.replacingOccurrences(of: "/play/", with: "/playwm/"))

        // 去掉 line 参数重试
        if var comps = URLComponents(string: original), let queryItems = comps.queryItems {
            comps.queryItems = queryItems.filter { $0.name != "line" }
            if let stripped = comps.url?.absoluteString {
                append(stripped)
                append(stripped.replacingOccurrences(of: "/play/", with: "/playwm/"))
            }
        }

        return result
    }

    private func extractBackendProxySourceURL(from url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.path.hasSuffix("/download"),
              let source = components.queryItems?.first(where: { $0.name == "source" })?.value,
              !source.isEmpty else {
            return nil
        }

        if let direct = URL(string: source) {
            return direct
        }
        if let decoded = source.removingPercentEncoding,
           let direct = URL(string: decoded) {
            return direct
        }
        return nil
    }

    // MARK: - Instagram 本地解析

    private static let instagramDesktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    private struct InstagramResolveResult {
        var title: String?
        var videoId: String?
        var videoCandidates: [String] = []
        var imageURLs: [String] = []
        var webpageURL: String?
    }

    private func resolveInstagramLocally(_ url: URL) async throws -> DouyinVideoInfo {
        log("resolveInstagramLocally start: \(url.absoluteString)")

        let cookies = CookieStore.shared.cookies(for: "instagram")
        guard !cookies.isEmpty else {
            throw DouyinDownloadError.backendResolveFailed(reason: "未配置 Instagram Cookie，请在设置中填写 sessionid")
        }
        guard let sessionid = cookies["sessionid"], !sessionid.isEmpty else {
            throw DouyinDownloadError.backendResolveFailed(reason: "Instagram Cookie 缺少 sessionid")
        }

        let normalizedURL = url.absoluteString.hasPrefix("http://")
            ? "https://" + url.absoluteString.dropFirst("http://".count)
            : url.absoluteString
        let shortcode = extractInstagramShortcode(from: normalizedURL)

        // 第一步: 通过 Private API 解析
        var apiResult = await resolveInstagramViaPrivateAPI(normalizedURL: normalizedURL, cookies: cookies)
        var title = apiResult.title
        var videoId = apiResult.videoId
        var videoCandidates = apiResult.videoCandidates
        var imageURLs = apiResult.imageURLs
        var webpageURL = apiResult.webpageURL ?? normalizedURL
        var encounteredChallenge = false

        // 第二步: API 失败时回退到网页解析
        if videoCandidates.isEmpty && imageURLs.isEmpty {
            log("instagram API returned no media, fallback to webpage")
            var page = try await fetchInstagramWebpage(url: normalizedURL, cookies: cookies)
            if isInstagramChallengePage(finalURL: page.0, html: page.1) {
                encounteredChallenge = true
                log("instagram webpage challenged, retry without cookie")
                do {
                    page = try await fetchInstagramWebpage(url: normalizedURL, cookies: [:])
                } catch {
                    log("instagram webpage guest retry failed: \(error.localizedDescription)")
                }
            }

            webpageURL = page.0
            var fallback = parseInstagramHTML(page.1)
            if fallback.videoCandidates.isEmpty,
               fallback.imageURLs.isEmpty,
               let shortcode,
               let embedPage = await fetchInstagramEmbedWebpage(shortcode: shortcode) {
                webpageURL = embedPage.0
                fallback = parseInstagramHTML(embedPage.1)
            }
            if title == nil || title!.isEmpty { title = fallback.title }
            videoCandidates.append(contentsOf: fallback.videoCandidates)
            imageURLs.append(contentsOf: fallback.imageURLs)
        }

        guard !videoCandidates.isEmpty || !imageURLs.isEmpty else {
            if encounteredChallenge {
                throw DouyinDownloadError.backendResolveFailed(reason: "Instagram触发风控挑战，请更新完整Cookie（sessionid/csrftoken/ds_user_id）后重试")
            }
            throw DouyinDownloadError.noVideoLinkFound
        }

        let resolvedId = videoId
            ?? extractInstagramShortcode(from: webpageURL)
            ?? extractInstagramShortcode(from: normalizedURL)
            ?? "ig_\(Int(Date().timeIntervalSince1970))"

        // 图文帖子（仅图片无视频）
        if !imageURLs.isEmpty && videoCandidates.isEmpty {
            let urls = imageURLs.compactMap { URL(string: $0) }
            guard !urls.isEmpty else { throw DouyinDownloadError.videoDataNotFound }
            log("resolveInstagramLocally success: image, id=\(resolvedId), count=\(urls.count)")
            return DouyinVideoInfo(
                id: resolvedId,
                downloadURL: urls[0],
                title: title,
                mediaType: .images,
                imageURLs: urls
            )
        }

        guard let videoURL = URL(string: videoCandidates[0]) else {
            throw DouyinDownloadError.noVideoLinkFound
        }
        log("resolveInstagramLocally success: video, id=\(resolvedId)")
        return DouyinVideoInfo(
            id: resolvedId,
            downloadURL: videoURL,
            title: title
        )
    }

    /// 通过 Instagram Private API (oembed + media info) 获取媒体信息
    private func resolveInstagramViaPrivateAPI(normalizedURL: String, cookies: [String: String]) async -> InstagramResolveResult {
        let headers = buildInstagramHeaders(referer: normalizedURL, cookies: cookies, jsonAPI: true)
        let shortcode = extractInstagramShortcode(from: normalizedURL)

        var fallbackTitle: String?
        var mediaId: String?

        // 1) oembed API
        if let encodedURL = normalizedURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let oembedURL = URL(string: "https://www.instagram.com/api/v1/oembed/?url=\(encodedURL)"),
           let payload = await requestInstagramJSON(url: oembedURL, headers: headers, logTag: "oembed") {
            fallbackTitle = payload["title"] as? String
            mediaId = payload["media_id"] as? String
        }

        // 2) media id info API
        if let mediaId, !mediaId.isEmpty,
           let infoURL = URL(string: "https://www.instagram.com/api/v1/media/\(mediaId)/info/"),
           let infoPayload = await requestInstagramJSON(url: infoURL, headers: headers, logTag: "mediaInfo") {
            var result = extractInstagramFromMediaInfo(infoPayload, fallbackTitle: fallbackTitle)
            if result.videoId == nil { result.videoId = mediaId }
            if !result.videoCandidates.isEmpty || !result.imageURLs.isEmpty {
                return result
            }
            log("instagram mediaInfo no media candidates")
        }

        // 3) shortcode info API 回退（避免 oembed/media_id 失效）
        if let shortcode, !shortcode.isEmpty {
            let shortcodeResult = await resolveInstagramViaShortcodeAPI(shortcode: shortcode, headers: headers, fallbackTitle: fallbackTitle)
            if !shortcodeResult.videoCandidates.isEmpty || !shortcodeResult.imageURLs.isEmpty {
                var result = shortcodeResult
                if result.videoId == nil { result.videoId = mediaId ?? shortcode }
                return result
            }
            var result = shortcodeResult
            if result.videoId == nil { result.videoId = mediaId ?? shortcode }
            return result
        }

        return InstagramResolveResult(title: fallbackTitle, videoId: mediaId)
    }

    private func requestInstagramJSON(url: URL, headers: [String: String], logTag: String) async -> [String: Any]? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        applyHeaders(headers, to: &request)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                log("instagram \(logTag) invalid response")
                return nil
            }
            guard (200..<300).contains(http.statusCode) else {
                log("instagram \(logTag) failed: status=\(http.statusCode)")
                return nil
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                log("instagram \(logTag) invalid json")
                return nil
            }
            return json
        } catch {
            log("instagram \(logTag) error: \(error.localizedDescription)")
            return nil
        }
    }

    private func resolveInstagramViaShortcodeAPI(shortcode: String, headers: [String: String], fallbackTitle: String?) async -> InstagramResolveResult {
        let endpoints = [
            "https://www.instagram.com/api/v1/media/\(shortcode)/info/",
            "https://www.instagram.com/api/v1/media/shortcode/\(shortcode)/info/",
        ]

        for (index, endpoint) in endpoints.enumerated() {
            guard let url = URL(string: endpoint),
                  let payload = await requestInstagramJSON(url: url, headers: headers, logTag: "shortcodeInfo[\(index)]") else {
                continue
            }

            var result = extractInstagramFromMediaInfo(payload, fallbackTitle: fallbackTitle)
            if result.videoId == nil { result.videoId = shortcode }
            if !result.videoCandidates.isEmpty || !result.imageURLs.isEmpty {
                log("instagram shortcode info success: try[\(index)], shortcode=\(shortcode)")
                return result
            }
            log("instagram shortcode info no candidates: try[\(index)]")
        }

        return InstagramResolveResult(title: fallbackTitle, videoId: shortcode)
    }

    private func extractInstagramFromMediaInfo(_ payload: [String: Any], fallbackTitle: String?) -> InstagramResolveResult {
        guard let items = payload["items"] as? [[String: Any]], let item = items.first else {
            return InstagramResolveResult(title: fallbackTitle)
        }

        let videoId = item["id"] as? String ?? item["pk"] as? String
        let mediaType = item["media_type"] as? String ?? "\(item["media_type"] ?? "")"
        let code = item["code"] as? String

        let webpageURL: String? = code.map {
            "https://www.instagram.com/\(mediaType == "2" ? "reel" : "p")/\($0)/"
        }

        var title = fallbackTitle
        if let caption = item["caption"] as? [String: Any],
           let captionText = caption["text"] as? String, !captionText.isEmpty {
            title = captionText
        }

        var videoCandidates: [String] = []
        var imageURLs: [String] = []

        // 轮播（carousel）
        if let carousel = item["carousel_media"] as? [[String: Any]], !carousel.isEmpty {
            for mediaObj in carousel {
                videoCandidates.append(contentsOf: extractInstagramVideoVersions(mediaObj["video_versions"]))
                imageURLs.append(contentsOf: extractInstagramImageVersions(mediaObj["image_versions2"]))
            }
        } else {
            videoCandidates.append(contentsOf: extractInstagramVideoVersions(item["video_versions"]))
            imageURLs.append(contentsOf: extractInstagramImageVersions(item["image_versions2"]))
        }

        return InstagramResolveResult(
            title: title,
            videoId: videoId,
            videoCandidates: dedupe(videoCandidates),
            imageURLs: dedupe(imageURLs),
            webpageURL: webpageURL
        )
    }

    private func extractInstagramVideoVersions(_ videoVersions: Any?) -> [String] {
        guard let array = videoVersions as? [[String: Any]] else { return [] }
        var candidates: [String] = []
        for item in array {
            guard let raw = item["url"] as? String,
                  let normalized = normalizeInstagramVideoCandidate(raw) else { continue }
            candidates.append(normalized)
        }
        return dedupe(candidates)
    }

    private func extractInstagramImageVersions(_ imageVersions2: Any?) -> [String] {
        guard let root = imageVersions2 as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]] else { return [] }

        var bestURL: String?
        var bestArea: Int64 = -1
        for item in candidates {
            guard let raw = item["url"] as? String,
                  let normalized = normalizeInstagramImageCandidate(raw) else { continue }
            let width = (item["width"] as? Int64) ?? Int64(item["width"] as? Int ?? 0)
            let height = (item["height"] as? Int64) ?? Int64(item["height"] as? Int ?? 0)
            let area = width * height
            if area > bestArea || bestURL == nil {
                bestArea = area
                bestURL = normalized
            }
        }
        return bestURL.map { [$0] } ?? []
    }

    /// 请求 Instagram 网页（回退策略）
    private func fetchInstagramWebpage(url: String, cookies: [String: String]) async throws -> (String, String) {
        let headers = buildInstagramHeaders(referer: url, cookies: cookies, jsonAPI: false)

        guard let requestURL = URL(string: url) else {
            throw DouyinDownloadError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 15
        applyHeaders(headers, to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DouyinDownloadError.downloadFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw DouyinDownloadError.videoDataNotFound
        }

        let finalURL = http.url?.absoluteString ?? url
        log("instagram webpage status=\(http.statusCode), finalUrl=\(finalURL), htmlBytes=\(data.count)")
        return (finalURL, html)
    }

    private func fetchInstagramEmbedWebpage(shortcode: String) async -> (String, String)? {
        let endpoints = [
            "https://www.instagram.com/reel/\(shortcode)/embed/",
            "https://www.instagram.com/p/\(shortcode)/embed/",
            "https://www.instagram.com/tv/\(shortcode)/embed/",
        ]

        for (index, endpoint) in endpoints.enumerated() {
            do {
                let page = try await fetchInstagramWebpage(url: endpoint, cookies: [:])
                if !isInstagramChallengePage(finalURL: page.0, html: page.1) {
                    log("instagram embed success: try[\(index)], finalUrl=\(page.0)")
                    return page
                }
                log("instagram embed challenged: try[\(index)], finalUrl=\(page.0)")
            } catch {
                log("instagram embed failed: try[\(index)], error=\(error.localizedDescription)")
            }
        }

        return nil
    }

    private func isInstagramChallengePage(finalURL: String, html: String) -> Bool {
        let finalLower = finalURL.lowercased()
        let htmlLower = html.lowercased()
        return finalLower.contains("/challenge/")
            || finalLower.contains("__coig_challenged=1")
            || htmlLower.contains("__coig_challenged")
            || htmlLower.contains("challenge_required")
            || htmlLower.contains("/challenge/")
    }

    /// 从 Instagram 网页 HTML 中解析视频链接
    private func parseInstagramHTML(_ html: String) -> InstagramResolveResult {
        var videoCandidates: [String] = []

        let patterns = [
            #""video_url":"(https:[^"]+)""#,
            #""contentUrl":"(https:[^"]+)""#,
            #""url":"(https:[^"]+\.mp4[^"]*)""#,
            #"<meta[^>]+property="og:video(?::secure_url|:url)?"[^>]+content="(https:[^"]+)""#,
            #"<meta[^>]+content="(https:[^"]+)"[^>]+property="og:video(?::secure_url|:url)?""#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(location: 0, length: html.utf16.count)
            regex.enumerateMatches(in: html, range: range) { match, _, _ in
                guard let match, let r = Range(match.range(at: 1), in: html) else { return }
                if let normalized = normalizeInstagramVideoCandidate(String(html[r])) {
                    videoCandidates.append(normalized)
                }
            }
        }

        // video_versions 块匹配
        if let blockRegex = try? NSRegularExpression(pattern: #""video_versions":\[(.*?)\]"#, options: [.caseInsensitive, .dotMatchesLineSeparators]),
           let urlRegex = try? NSRegularExpression(pattern: #""url":"(https:[^"]+)""#, options: .caseInsensitive) {
            let fullRange = NSRange(location: 0, length: html.utf16.count)
            blockRegex.enumerateMatches(in: html, range: fullRange) { blockMatch, _, _ in
                guard let blockMatch, let blockRange = Range(blockMatch.range(at: 1), in: html) else { return }
                let block = String(html[blockRange])
                let blockNSRange = NSRange(location: 0, length: block.utf16.count)
                urlRegex.enumerateMatches(in: block, range: blockNSRange) { urlMatch, _, _ in
                    guard let urlMatch, let urlRange = Range(urlMatch.range(at: 1), in: block) else { return }
                    if let normalized = normalizeInstagramVideoCandidate(String(block[urlRange])) {
                        videoCandidates.append(normalized)
                    }
                }
            }
        }

        return InstagramResolveResult(
            title: extractInstagramOgTitle(from: html),
            videoCandidates: dedupe(videoCandidates)
        )
    }

    private func extractInstagramOgTitle(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<meta[^>]+property="og:title"[^>]+content="([^"]+)""#, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: html.utf16.count)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let raw = String(html[range])
        return decodeInstagramEscapes(raw).isEmpty ? nil : decodeInstagramEscapes(raw)
    }

    private func extractInstagramShortcode(from urlString: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"/(?:reel|p|tv)/([A-Za-z0-9_-]+)"#),
              let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
              let range = Range(match.range(at: 1), in: urlString) else {
            return nil
        }
        return String(urlString[range])
    }

    private func buildInstagramHeaders(referer: String, cookies: [String: String], jsonAPI: Bool) -> [String: String] {
        var headers: [String: String] = [
            "User-Agent": Self.instagramDesktopUA,
            "Accept-Language": "en-US,en;q=0.9,zh-CN;q=0.8",
            "Referer": referer,
            "Origin": "https://www.instagram.com",
        ]
        if !cookies.isEmpty {
            headers["Cookie"] = cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        }
        if jsonAPI {
            headers["Accept"] = "application/json, text/plain, */*"
            headers["X-IG-App-ID"] = "936619743392459"
            headers["X-Requested-With"] = "XMLHttpRequest"
        } else {
            headers["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        }
        return headers
    }

    private func applyHeaders(_ headers: [String: String], to request: inout URLRequest) {
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    private func normalizeInstagramVideoCandidate(_ value: String) -> String? {
        let url = decodeInstagramEscapes(value)
        guard url.hasPrefix("http") else { return nil }
        guard let host = URL(string: url)?.host?.lowercased() else { return nil }
        let allowed = host == "instagram.com" || host.hasSuffix(".instagram.com")
            || host == "cdninstagram.com" || host.hasSuffix(".cdninstagram.com")
            || host == "fbcdn.net" || host.hasSuffix(".fbcdn.net")
        guard allowed else { return nil }
        let lower = url.lowercased()
        guard lower.contains(".mp4") || lower.contains("bytestart") || lower.contains("video") else { return nil }
        return url
    }

    private func normalizeInstagramImageCandidate(_ value: String) -> String? {
        let url = decodeInstagramEscapes(value)
        guard url.hasPrefix("http") else { return nil }
        guard let host = URL(string: url)?.host?.lowercased() else { return nil }
        let allowed = host == "instagram.com" || host.hasSuffix(".instagram.com")
            || host == "cdninstagram.com" || host.hasSuffix(".cdninstagram.com")
            || host == "fbcdn.net" || host.hasSuffix(".fbcdn.net")
        return allowed ? url : nil
    }

    private func decodeInstagramEscapes(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: - X (Twitter) 本地解析

    /// 缓存 X graphql metadata (queryId, bearerToken, timestamp)
    private var xMetadataCache: (queryId: String, bearer: String, timestamp: Date)?

    private func resolveXLocally(_ url: URL) async throws -> DouyinVideoInfo {
        log("resolveXLocally start: \(url.absoluteString)")

        let cookies = CookieStore.shared.cookies(for: "x")
        guard !cookies.isEmpty else {
            throw DouyinDownloadError.backendResolveFailed(reason: "未配置 X Cookie，请在设置中填写 auth_token 和 ct0")
        }
        guard let authToken = cookies["auth_token"], !authToken.isEmpty else {
            throw DouyinDownloadError.backendResolveFailed(reason: "X Cookie 缺少 auth_token")
        }
        guard let ct0 = cookies["ct0"], !ct0.isEmpty else {
            throw DouyinDownloadError.backendResolveFailed(reason: "X Cookie 缺少 ct0")
        }

        let normalized = url.absoluteString.replacingOccurrences(of: "http://", with: "https://")
        guard let tweetId = extractXTweetId(from: normalized) else {
            throw DouyinDownloadError.backendResolveFailed(reason: "无法从链接中提取 tweet id")
        }

        let (queryId, bearer) = try await loadXGraphqlMetadata(tweetId: tweetId, cookies: cookies)
        let result = try await resolveXMedia(tweetId: tweetId, queryId: queryId, bearer: bearer, cookies: cookies)

        // 视频推文
        if let firstVideo = result.videoCandidates.first, let videoURL = URL(string: firstVideo) {
            log("resolveXLocally success: video, id=\(tweetId), candidates=\(result.videoCandidates.count)")
            return DouyinVideoInfo(
                id: tweetId,
                downloadURL: videoURL,
                title: result.title
            )
        }

        // 图片推文
        if !result.imageURLs.isEmpty {
            let urls = result.imageURLs.compactMap { URL(string: $0) }
            guard !urls.isEmpty else { throw DouyinDownloadError.noVideoLinkFound }
            log("resolveXLocally success: image, id=\(tweetId), count=\(urls.count)")
            return DouyinVideoInfo(
                id: tweetId,
                downloadURL: urls[0],
                title: result.title,
                mediaType: .images,
                imageURLs: urls
            )
        }

        throw DouyinDownloadError.noVideoLinkFound
    }

    /// X 解析结果（视频或图片）
    private struct XResolveResult {
        var title: String?
        var videoCandidates: [String] = []
        var imageURLs: [String] = []
    }

    /// 通过 GraphQL API 获取视频/图片
    private func resolveXMedia(tweetId: String, queryId: String, bearer: String, cookies: [String: String]) async throws -> XResolveResult {
        let variables = #"{"tweetId":"\#(tweetId)","withCommunity":false,"includePromotedContent":false,"withVoice":true}"#
        let features = #"{"responsive_web_graphql_exclude_directive_enabled":true,"longform_notetweets_inline_media_enabled":true,"responsive_web_media_download_video_enabled":true,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":true}"#

        guard let encodedVars = variables.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedFeats = features.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let endpoint = URL(string: "https://x.com/i/api/graphql/\(queryId)/TweetResultByRestId?variables=\(encodedVars)&features=\(encodedFeats)") else {
            throw DouyinDownloadError.backendResolveFailed(reason: "X graphql URL 构建失败")
        }

        let headers = buildXGraphqlHeaders(tweetId: tweetId, bearerToken: bearer, cookies: cookies)

        var lastError = "unknown error"
        for attempt in 0..<3 {
            log("x graphql attempt[\(attempt)]")
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 20
            applyHeaders(headers, to: &request)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastError = "invalid response"
                    continue
                }

                if http.statusCode == 401 {
                    lastError = "unauthorized, cookie 可能已过期"
                    log("x graphql attempt[\(attempt)] 401")
                    continue
                }

                guard (200..<300).contains(http.statusCode) else {
                    lastError = "HTTP \(http.statusCode)"
                    log("x graphql attempt[\(attempt)] status=\(http.statusCode)")
                    continue
                }

                guard let payload = try? JSONSerialization.jsonObject(with: data) else {
                    lastError = "json parse failed"
                    continue
                }

                if let unavailable = extractXTweetUnavailableReason(payload) {
                    lastError = unavailable
                    log("x graphql attempt[\(attempt)] unavailable: \(unavailable)")
                    if unavailable.lowercased().contains("tweet unavailable") { break }
                    continue
                }

                let (title, videoCandidates, imageURLs) = extractXMediaFromGraphql(payload)
                if !videoCandidates.isEmpty || !imageURLs.isEmpty {
                    log("x graphql attempt[\(attempt)] success, videos=\(videoCandidates.count), images=\(imageURLs.count)")
                    return XResolveResult(title: title, videoCandidates: videoCandidates, imageURLs: imageURLs)
                }
                lastError = "推文中未找到可下载媒体"
                log("x graphql attempt[\(attempt)] no media")
            } catch {
                lastError = error.localizedDescription
                log("x graphql attempt[\(attempt)] error: \(lastError)")
            }
        }

        throw DouyinDownloadError.backendResolveFailed(reason: "X 解析失败: \(lastError)")
    }

    /// 加载 X graphql 所需的 queryId 和 bearer token（从 main.js 中提取）
    private func loadXGraphqlMetadata(tweetId: String, cookies: [String: String]) async throws -> (String, String) {
        // 检查缓存（30 分钟有效期）
        if let cached = xMetadataCache, Date().timeIntervalSince(cached.timestamp) < 30 * 60 {
            log("x meta cache hit")
            return (cached.queryId, cached.bearer)
        }

        let pageHeaders = buildXPageHeaders(cookies: cookies)

        // 1. 请求 X 页面获取 main.js URL
        guard let pageURL = URL(string: "https://x.com/i/status/\(tweetId)") else {
            throw DouyinDownloadError.backendResolveFailed(reason: "X page URL 构建失败")
        }

        var pageReq = URLRequest(url: pageURL)
        pageReq.timeoutInterval = 15
        applyHeaders(pageHeaders, to: &pageReq)

        let (pageData, pageResponse) = try await URLSession.shared.data(for: pageReq)
        guard let pageHttp = pageResponse as? HTTPURLResponse, (200..<300).contains(pageHttp.statusCode),
              let html = String(data: pageData, encoding: .utf8) else {
            throw DouyinDownloadError.backendResolveFailed(reason: "X 页面加载失败")
        }

        guard let mainJsURL = extractXMainJsURL(from: html), let jsURL = URL(string: mainJsURL) else {
            throw DouyinDownloadError.backendResolveFailed(reason: "无法找到 X main.js 地址")
        }
        log("x meta mainJs: \(mainJsURL)")

        // 2. 请求 main.js 提取 queryId 和 bearer
        var jsReq = URLRequest(url: jsURL)
        jsReq.timeoutInterval = 20
        applyHeaders(pageHeaders, to: &jsReq)

        let (jsData, jsResponse) = try await URLSession.shared.data(for: jsReq)
        guard let jsHttp = jsResponse as? HTTPURLResponse, (200..<300).contains(jsHttp.statusCode),
              let js = String(data: jsData, encoding: .utf8) else {
            throw DouyinDownloadError.backendResolveFailed(reason: "X main.js 加载失败")
        }

        guard let queryId = extractXQueryId(from: js), let bearer = extractXBearerToken(from: js) else {
            throw DouyinDownloadError.backendResolveFailed(reason: "无法从 main.js 中提取 graphql 参数")
        }

        xMetadataCache = (queryId, bearer, Date())
        log("x meta success: queryId=\(queryId), bearerLen=\(bearer.count)")
        return (queryId, bearer)
    }

    private func buildXPageHeaders(cookies: [String: String]) -> [String: String] {
        [
            "User-Agent": "Mozilla/5.0",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
            "Referer": "https://x.com/",
            "Cookie": cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; "),
        ]
    }

    private func buildXGraphqlHeaders(tweetId: String, bearerToken: String, cookies: [String: String]) -> [String: String] {
        [
            "User-Agent": "Mozilla/5.0",
            "Authorization": "Bearer \(bearerToken)",
            "X-CSRF-Token": cookies["ct0"] ?? "",
            "X-Twitter-Active-User": "yes",
            "X-Twitter-Auth-Type": "OAuth2Session",
            "Referer": "https://x.com/i/status/\(tweetId)",
            "Origin": "https://x.com",
            "Accept": "*/*",
            "Accept-Language": "en-US,en;q=0.9",
            "Cookie": cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; "),
        ]
    }

    private func extractXTweetId(from urlString: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"/status/(\d+)"#),
              let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
              let range = Range(match.range(at: 1), in: urlString) else {
            return nil
        }
        return String(urlString[range])
    }

    private func extractXMainJsURL(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"https://abs\.twimg\.com/responsive-web/client-web/main\.[^"']+\.js"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: html.utf16.count)),
              let range = Range(match.range, in: html) else {
            return nil
        }
        return String(html[range])
    }

    private func extractXQueryId(from js: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"queryId:"([A-Za-z0-9_-]{20,})",operationName:"TweetResultByRestId""#, options: .caseInsensitive),
              let match = regex.firstMatch(in: js, range: NSRange(location: 0, length: js.utf16.count)),
              let range = Range(match.range(at: 1), in: js) else {
            return nil
        }
        return String(js[range])
    }

    private func extractXBearerToken(from js: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"AAAAAAAAAAAAAAAAAAAAA[A-Za-z0-9%_=-]{40,}"#),
              let match = regex.firstMatch(in: js, range: NSRange(location: 0, length: js.utf16.count)),
              let range = Range(match.range, in: js) else {
            return nil
        }
        return String(js[range])
    }

    /// 从 GraphQL 响应中提取视频/图片候选链接
    private func extractXMediaFromGraphql(_ payload: Any) -> (title: String?, videoCandidates: [String], imageURLs: [String]) {
        var title: String?
        var mp4s: [(bitrate: Int, url: String)] = []
        var others: [String] = []
        var imageURLs: [String] = []

        func walk(_ node: Any?) {
            if let dict = node as? [String: Any] {
                if let fullText = dict["full_text"] as? String, !fullText.isEmpty, title == nil {
                    title = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                if let variants = dict["variants"] as? [[String: Any]] {
                    for variant in variants {
                        guard let url = variant["url"] as? String, url.contains("video.twimg.com") else { continue }
                        let contentType = variant["content_type"] as? String
                        let bitrate = variant["bitrate"] as? Int ?? 0
                        if contentType == "video/mp4" {
                            mp4s.append((bitrate, url))
                        } else if url.lowercased().contains(".m3u8") {
                            others.append(url)
                        }
                    }
                }

                // 图片推文: media 数组中 type == "photo" 的 media_url_https
                if let mediaType = dict["type"] as? String, mediaType == "photo",
                   let mediaURL = dict["media_url_https"] as? String,
                   mediaURL.contains("pbs.twimg.com") {
                    imageURLs.append(mediaURL)
                }

                // unified_card 内嵌 JSON
                if dict["key"] as? String == "unified_card",
                   let value = dict["value"] as? [String: Any],
                   let stringValue = value["string_value"] as? String,
                   stringValue.hasPrefix("{"),
                   let cardData = stringValue.data(using: .utf8),
                   let cardObj = try? JSONSerialization.jsonObject(with: cardData) {
                    walk(cardObj)
                }

                for child in dict.values { walk(child) }
            } else if let array = node as? [Any] {
                for child in array { walk(child) }
            }
        }

        walk(payload)
        let sorted = mp4s.sorted { $0.bitrate > $1.bitrate }.map(\.url)
        return (title, dedupe(sorted + others), dedupe(imageURLs))
    }

    private func extractXTweetUnavailableReason(_ payload: Any) -> String? {
        guard let root = payload as? [String: Any],
              let data = root["data"] as? [String: Any],
              let tweetResult = data["tweetResult"] as? [String: Any],
              let result = tweetResult["result"] as? [String: Any],
              result["__typename"] as? String == "TweetUnavailable" else {
            return nil
        }
        let reason = result["reason"] as? String ?? "unknown"
        return "tweet unavailable: \(reason)"
    }

    // MARK: - 小红书本地解析

    /// 请求小红书页面并解析视频/图文信息
    private func resolveXiaohongshuLocally(_ url: URL) async throws -> DouyinVideoInfo {
        log("resolveXiaohongshuLocally start: \(url.absoluteString)")

        // 统一 http -> https
        let normalizedURL: URL
        if url.scheme == "http" {
            normalizedURL = URL(string: "https://" + url.absoluteString.dropFirst("http://".count))!
        } else {
            normalizedURL = url
        }

        var request = URLRequest(url: normalizedURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.addValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.addValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.addValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.addValue("https://www.xiaohongshu.com/", forHTTPHeaderField: "Referer")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw DouyinDownloadError.downloadFailed(statusCode: code)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw DouyinDownloadError.videoDataNotFound
        }

        let webpageURL = httpResponse.url?.absoluteString ?? normalizedURL.absoluteString
        let noteId = extractXiaohongshuNoteId(from: webpageURL) ?? "xhs_\(Int(Date().timeIntervalSince1970))"

        log("resolveXiaohongshuLocally response status: \(httpResponse.statusCode), finalUrl: \(webpageURL), htmlBytes: \(data.count)")

        let parsed = parseXiaohongshuHTML(html)
        log("resolveXiaohongshuLocally parsed: videoCandidates=\(parsed.videoCandidates.count), imageUrls=\(parsed.imageURLs.count), mediaType=\(parsed.mediaType.rawValue)")

        if parsed.mediaType == .images && !parsed.imageURLs.isEmpty {
            let urls = parsed.imageURLs.compactMap { URL(string: $0) }
            guard !urls.isEmpty else { throw DouyinDownloadError.videoDataNotFound }
            return DouyinVideoInfo(
                id: noteId,
                downloadURL: urls[0],
                title: parsed.title,
                mediaType: .images,
                imageURLs: urls
            )
        }

        guard let firstVideo = parsed.videoCandidates.first, let videoURL = URL(string: firstVideo) else {
            throw DouyinDownloadError.noVideoLinkFound
        }

        return DouyinVideoInfo(
            id: noteId,
            downloadURL: videoURL,
            title: parsed.title
        )
    }

    private struct XiaohongshuParsedMedia {
        var title: String?
        var videoCandidates: [String] = []
        var mediaType: MediaType = .video
        var imageURLs: [String] = []
    }

    private func parseXiaohongshuHTML(_ html: String) -> XiaohongshuParsedMedia {
        let initial = parseXiaohongshuInitialState(html)
        if !initial.videoCandidates.isEmpty || !initial.imageURLs.isEmpty {
            return initial
        }

        // 回退: 正则匹配 xhscdn 链接
        let rawCandidates = parseXiaohongshuRawHTML(html)
        return XiaohongshuParsedMedia(
            title: initial.title,
            videoCandidates: rawCandidates,
            mediaType: .video
        )
    }

    private func parseXiaohongshuInitialState(_ html: String) -> XiaohongshuParsedMedia {
        guard let jsonStr = extractJSONAssignment(from: html, varName: "window.__INITIAL_STATE__")?
                .replacingOccurrences(of: "undefined", with: "null"),
              let jsonData = jsonStr.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return XiaohongshuParsedMedia()
        }

        // 收集所有 note 对象
        var notes: [[String: Any]] = []

        if let noteData = (root["noteData"] as? [String: Any])?["data"] as? [String: Any],
           let nd = noteData["noteData"] as? [String: Any] {
            notes.append(nd)
        }

        if let noteDetailMap = (root["note"] as? [String: Any])?["noteDetailMap"] as? [String: Any] {
            for (_, entry) in noteDetailMap {
                if let entryDict = entry as? [String: Any],
                   let note = entryDict["note"] as? [String: Any] {
                    notes.append(note)
                }
            }
        }

        var title: String?
        var candidates: [String] = []
        var imageURLs: [String] = []

        for note in notes {
            let noteType = note["type"] as? String
            if title == nil {
                title = note["title"] as? String ?? note["desc"] as? String
            }

            // 图文笔记
            if noteType == "normal" {
                if let imageList = note["imageList"] as? [[String: Any]] {
                    for img in imageList {
                        var imgUrl: String?
                        if let infoList = img["infoList"] as? [[String: Any]] {
                            for info in infoList {
                                if info["imageScene"] as? String == "H5_DTL" {
                                    imgUrl = info["url"] as? String
                                    break
                                }
                            }
                        }
                        if imgUrl == nil || imgUrl!.isEmpty {
                            imgUrl = img["url"] as? String
                        }
                        if let u = imgUrl, !u.isEmpty {
                            imageURLs.append(normalizeXiaohongshuMediaURL(u))
                        }
                    }
                }
                if !imageURLs.isEmpty {
                    return XiaohongshuParsedMedia(
                        title: title,
                        mediaType: .images,
                        imageURLs: dedupe(imageURLs)
                    )
                }
            }

            // 视频笔记
            if noteType == "video" {
                if let stream = ((note["video"] as? [String: Any])?["media"] as? [String: Any])?["stream"] as? [String: Any] {
                    for codec in ["h264", "h265", "av1"] {
                        if let streams = stream[codec] as? [[String: Any]] {
                            for item in streams {
                                if let masterUrl = item["masterUrl"] as? String,
                                   !masterUrl.isEmpty,
                                   masterUrl.hasPrefix("http") {
                                    candidates.append(normalizeXiaohongshuMediaURL(masterUrl))
                                }
                            }
                        }
                    }
                }
            }
        }

        return XiaohongshuParsedMedia(
            title: title,
            videoCandidates: dedupe(candidates)
        )
    }

    private func parseXiaohongshuRawHTML(_ html: String) -> [String] {
        let patterns = [
            #"(https?:\\/\\/[^"']+xhscdn\.(?:com|net)[^"']*\.mp4[^"']*)"#,
            #"(https?://[^"']+xhscdn\.(?:com|net)[^"']*\.mp4[^"']*)"#,
            #"(https?:\\/\\/[^"']+xhscdn\.(?:com|net)[^"']*)"#,
            #"(https?://[^"']+xhscdn\.(?:com|net)[^"']*)"#,
        ]

        var results: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(location: 0, length: html.utf16.count)
            regex.enumerateMatches(in: html, range: range) { match, _, _ in
                guard let match, let r = Range(match.range(at: 1), in: html) else { return }
                let raw = String(html[r]).replacingOccurrences(of: "\\/", with: "/")
                if raw.contains("/stream/") || raw.contains("/video/") || raw.contains("masterUrl") || raw.contains(".mp4") {
                    results.append(normalizeXiaohongshuMediaURL(raw))
                }
            }
        }
        return dedupe(results)
    }

    /// 从 HTML 中提取 `varName = {...}` 赋值语句中的 JSON 对象（括号匹配）
    private func extractJSONAssignment(from html: String, varName: String) -> String? {
        guard let varRange = html.range(of: varName) else { return nil }
        guard let eqRange = html.range(of: "=", range: varRange.upperBound..<html.endIndex) else { return nil }
        guard let braceStart = html.range(of: "{", range: eqRange.upperBound..<html.endIndex) else { return nil }

        var depth = 0
        var inString = false
        var escape = false
        var idx = braceStart.lowerBound

        while idx < html.endIndex {
            let c = html[idx]
            if escape { escape = false; idx = html.index(after: idx); continue }
            if c == "\\" && inString { escape = true; idx = html.index(after: idx); continue }
            if c == "\"" { inString = !inString; idx = html.index(after: idx); continue }
            if !inString {
                if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(html[braceStart.lowerBound...idx])
                    }
                }
            }
            idx = html.index(after: idx)
        }
        return nil
    }

    private func extractXiaohongshuNoteId(from urlString: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"/(?:explore|discovery/item)/([a-zA-Z0-9_\-]+)"#),
              let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
              let range = Range(match.range(at: 1), in: urlString) else {
            return nil
        }
        return String(urlString[range])
    }

    private func normalizeXiaohongshuMediaURL(_ url: String) -> String {
        if url.hasPrefix("http://") {
            return "https://" + url.dropFirst("http://".count)
        }
        return url
    }

    private func dedupe(_ urls: [String]) -> [String] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0).inserted }
    }

    // MARK: - 快手本地解析

    private func resolveKuaishouLocally(_ url: URL) async throws -> DouyinVideoInfo {
        log("resolveKuaishouLocally start: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.addValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.addValue("https://www.kuaishou.com/", forHTTPHeaderField: "Referer")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw DouyinDownloadError.downloadFailed(statusCode: code)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw DouyinDownloadError.videoDataNotFound
        }

        let webpageURL = httpResponse.url?.absoluteString ?? url.absoluteString
        let videoId = extractKuaishouVideoId(from: webpageURL)
        let photoId = extractKuaishouPhotoId(from: webpageURL)

        log("resolveKuaishouLocally response status: \(httpResponse.statusCode), finalUrl: \(webpageURL), htmlBytes: \(data.count), videoId: \(videoId ?? "nil"), photoId: \(photoId ?? "nil")")

        // 策略 1: API 解析（需要 photoId）
        if let pid = photoId {
            if let apiResult = try? await resolveKuaishouViaAPI(photoId: pid) {
                log("resolveKuaishouLocally API success, mediaType: \(apiResult.mediaType.rawValue)")
                let id = videoId ?? pid
                return apiResult.toVideoInfo(id: id)
            }
            log("resolveKuaishouLocally API failed, fallback to HTML")
        }

        // 策略 2-4: HTML 解析（多级回退）
        let parsed = parseKuaishouHTML(html)
        let id = videoId ?? photoId ?? "ks_\(Int(Date().timeIntervalSince1970))"

        if parsed.mediaType == .images && !parsed.imageURLs.isEmpty {
            let urls = parsed.imageURLs.compactMap { URL(string: $0) }
            guard !urls.isEmpty else { throw DouyinDownloadError.videoDataNotFound }
            return DouyinVideoInfo(
                id: id,
                downloadURL: urls[0],
                title: parsed.title,
                mediaType: .images,
                imageURLs: urls
            )
        }

        guard let firstVideo = parsed.videoCandidates.first, let videoURL = URL(string: firstVideo) else {
            throw DouyinDownloadError.noVideoLinkFound
        }

        return DouyinVideoInfo(
            id: id,
            downloadURL: videoURL,
            title: parsed.title
        )
    }

    // MARK: 快手 API 解析

    private struct KuaishouAPIResult {
        var title: String?
        var mediaType: MediaType
        var videoCandidates: [String]
        var imageURLs: [String]

        func toVideoInfo(id: String) -> DouyinVideoInfo {
            if mediaType == .images && !imageURLs.isEmpty {
                let urls = imageURLs.compactMap { URL(string: $0) }
                return DouyinVideoInfo(
                    id: id,
                    downloadURL: urls.first ?? URL(string: imageURLs[0])!,
                    title: title,
                    mediaType: .images,
                    imageURLs: urls
                )
            }
            return DouyinVideoInfo(
                id: id,
                downloadURL: URL(string: videoCandidates.first ?? "")!,
                title: title
            )
        }
    }

    private static let kuaishouAtlasPhotoTypes: Set<String> = [
        "VERTICAL_ATLAS", "HORIZONTAL_ATLAS", "MULTI_IMAGE"
    ]

    private func resolveKuaishouViaAPI(photoId: String) async throws -> KuaishouAPIResult {
        let apiURL = URL(string: "https://v.m.chenzhongtech.com/rest/wd/ugH5App/photo/simple/info")!
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.addValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.addValue("https://www.kuaishou.com/", forHTTPHeaderField: "Referer")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["photoId": photoId, "kpn": "KUAISHOU"]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DouyinDownloadError.videoDataNotFound
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? Int, result == 1 else {
            throw DouyinDownloadError.videoDataNotFound
        }

        let photo = root["photo"] as? [String: Any] ?? [:]
        let title = photo["caption"] as? String
        let photoType = photo["photoType"] as? String ?? ""

        // 图集检测
        let atlas = root["atlas"] as? [String: Any] ?? [:]
        let cdnList = atlas["cdnList"] as? [[String: Any]] ?? []
        let imgList = atlas["list"] as? [String] ?? []

        if Self.kuaishouAtlasPhotoTypes.contains(photoType),
           let cdn = cdnList.first?["cdn"] as? String,
           !imgList.isEmpty {
            let imageURLs = imgList.compactMap { path -> String? in
                guard !path.isEmpty else { return nil }
                return "https://\(cdn)\(path)"
            }
            if !imageURLs.isEmpty {
                return KuaishouAPIResult(
                    title: title,
                    mediaType: .images,
                    videoCandidates: [],
                    imageURLs: imageURLs
                )
            }
        }

        // 视频：从 mainMvUrls 提取
        let mainMvUrls = photo["mainMvUrls"] as? [[String: Any]] ?? []
        var videoCandidates: [String] = []
        for item in mainMvUrls {
            if let urlStr = item["url"] as? String, urlStr.hasPrefix("http") {
                videoCandidates.append(urlStr)
            }
        }

        guard !videoCandidates.isEmpty else {
            throw DouyinDownloadError.videoDataNotFound
        }

        return KuaishouAPIResult(
            title: title,
            mediaType: .video,
            videoCandidates: videoCandidates,
            imageURLs: []
        )
    }

    // MARK: 快手 HTML 解析

    private struct KuaishouParsedMedia {
        var title: String?
        var videoCandidates: [String] = []
        var mediaType: MediaType = .video
        var imageURLs: [String] = []
    }

    private func parseKuaishouHTML(_ html: String) -> KuaishouParsedMedia {
        // 策略 2: window.__APOLLO_STATE__
        let apollo = parseKuaishouApolloState(html)
        if !apollo.videoCandidates.isEmpty {
            return apollo
        }

        // 策略 3: window.__INITIAL_STATE__
        let initial = parseKuaishouInitialState(html)
        if !initial.videoCandidates.isEmpty {
            return initial
        }

        // 策略 4: 正则匹配 CDN URL
        let rawCandidates = parseKuaishouRawHTML(html)
        return KuaishouParsedMedia(
            title: apollo.title ?? initial.title,
            videoCandidates: rawCandidates,
            mediaType: .video
        )
    }

    private func parseKuaishouApolloState(_ html: String) -> KuaishouParsedMedia {
        guard let jsonStr = extractJSONAssignment(from: html, varName: "window.__APOLLO_STATE__"),
              let jsonData = jsonStr.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return KuaishouParsedMedia()
        }

        var title: String?
        var candidates: [String] = []

        for (key, value) in root {
            guard let dict = value as? [String: Any] else { continue }
            guard key.contains("Photo") || key.contains("Work") || key.contains("Video") else { continue }
            let videoUrl = dict["videoUrl"] as? String ?? dict["video_url"] as? String
            if let url = videoUrl, url.hasPrefix("http") {
                if title == nil {
                    title = dict["caption"] as? String ?? dict["title"] as? String
                }
                candidates.append(url)
            }
        }

        return KuaishouParsedMedia(
            title: title,
            videoCandidates: dedupe(candidates)
        )
    }

    private func parseKuaishouInitialState(_ html: String) -> KuaishouParsedMedia {
        guard let jsonStr = extractJSONAssignment(from: html, varName: "window.__INITIAL_STATE__")?
                .replacingOccurrences(of: "undefined", with: "null"),
              let jsonData = jsonStr.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? Any else {
            return KuaishouParsedMedia()
        }

        var title: String?
        var candidates: [String] = []

        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                for (k, v) in dict {
                    if (k == "videoUrl" || k == "video_url" || k == "mp4Url"),
                       let str = v as? String, str.hasPrefix("http") {
                        candidates.append(str)
                    } else if (k == "caption" || k == "title"),
                              let str = v as? String, title == nil {
                        title = str
                    } else {
                        walk(v)
                    }
                }
            } else if let arr = node as? [Any] {
                for item in arr {
                    walk(item)
                }
            }
        }

        walk(root)

        return KuaishouParsedMedia(
            title: title,
            videoCandidates: dedupe(candidates)
        )
    }

    private func parseKuaishouRawHTML(_ html: String) -> [String] {
        let patterns = [
            #"(https?:\\/\\/[^"']+kwimgs\.com[^"']*\.mp4[^"']*)"#,
            #"(https?:\\/\\/[^"']+kwai\.net[^"']*\.mp4[^"']*)"#,
            #"(https?://[^"']+kwimgs\.com[^"']*\.mp4[^"']*)"#,
            #"(https?://[^"']+kwai\.net[^"']*\.mp4[^"']*)"#,
        ]
        var candidates: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let nsHTML = html as NSString
            let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
            for match in matches {
                if let range = Range(match.range(at: 1), in: html) {
                    let url = String(html[range]).replacingOccurrences(of: "\\/", with: "/")
                    candidates.append(url)
                }
            }
        }
        return dedupe(candidates)
    }

    // MARK: 快手 ID 提取

    private func extractKuaishouVideoId(from urlString: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"/(?:short-video|video)/([a-zA-Z0-9_\-]+)"#),
              let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
              let range = Range(match.range(at: 1), in: urlString) else {
            return nil
        }
        return String(urlString[range])
    }

    private func extractKuaishouPhotoId(from urlString: String) -> String? {
        // /photo/{id} 或 /fw/photo/{id}
        if let regex = try? NSRegularExpression(pattern: #"/(?:fw/)?photo/([a-zA-Z0-9_\-]+)"#),
           let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
           let range = Range(match.range(at: 1), in: urlString) {
            return String(urlString[range])
        }
        // photoId= 查询参数
        if let regex = try? NSRegularExpression(pattern: #"photoId=([a-zA-Z0-9_\-]+)"#),
           let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
           let range = Range(match.range(at: 1), in: urlString) {
            return String(urlString[range])
        }
        return nil
    }

    private func applyPlatformDownloadHeaders(to request: inout URLRequest, targetURL: URL) {
        let host = targetURL.host?.lowercased() ?? ""

        // 默认值
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://www.douyin.com/", forHTTPHeaderField: "Referer")

        // B站/UPOS 直链
        if host.contains("bilibili") || host.contains("bilivideo") || host.contains("upos") || host.hasSuffix(".akamaized.net") {
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
            return
        }

        // Instagram 直链
        if host.contains("instagram.com") || host.contains("cdninstagram.com") || host.contains("fbcdn.net") {
            request.setValue("https://www.instagram.com/", forHTTPHeaderField: "Referer")
            let cookies = CookieStore.shared.cookies(for: "instagram")
            if !cookies.isEmpty {
                request.setValue(cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
            }
            return
        }

        // X 直链
        if host.contains("x.com") || host.contains("twitter.com") || host.contains("twimg.com") {
            request.setValue("https://x.com/", forHTTPHeaderField: "Referer")
            let cookies = CookieStore.shared.cookies(for: "x")
            if !cookies.isEmpty {
                request.setValue(cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
            }
            return
        }

        // 小红书直链
        if host.contains("xhscdn") || host.contains("xiaohongshu") {
            request.setValue("https://www.xiaohongshu.com/", forHTTPHeaderField: "Referer")
            return
        }

        // 快手直链
        if host.contains("kwimgs.com") || host.contains("kwai.net") || host.contains("kuaishou.com") || host.contains("yximgs.com") {
            request.setValue("https://www.kuaishou.com/", forHTTPHeaderField: "Referer")
        }
    }
}
