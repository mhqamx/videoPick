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
        URL(string: "http://127.0.0.1:8000/resolve")!,
        URL(string: "http://192.168.1.100:8000/resolve")!,
        URL(string: "https://super-halibut-r4r59wg9qw93pv6p-8000.app.github.dev/resolve")!,
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

        do {
            videoInfo = try await resolveViaBackend(text: text)
            log("resolve via backend success")
        } catch {
            let backendErrorMessage = error.localizedDescription
            log("resolve via backend failed: \(backendErrorMessage), fallback to local parser")
            let url = try extractURL(from: text)
            log("extracted url: \(url.absoluteString)")
            guard isDouyinURL(url) else {
                throw DouyinDownloadError.backendResolveFailed(reason: "当前链接仅支持服务端解析，请检查 backend 服务是否可用")
            }
            videoInfo = try await resolveDouyinShortURL(url)
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

        return try parseVideoInfo(from: htmlString)
    }

    private func resolveViaBackend(text: String) async throws -> DouyinVideoInfo {
        struct BackendRequest: Codable {
            let text: String
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
                request.httpBody = try JSONEncoder().encode(BackendRequest(text: text))

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
                   let firstItem = itemList.first,
                   let parsed = buildVideoInfo(from: firstItem) {
                    return parsed
                }
            }
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
            request.addValue("https://www.douyin.com/", forHTTPHeaderField: "Referer")

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

        for (index, candidate) in candidates.enumerated() {
            var request = URLRequest(url: candidate)
            request.timeoutInterval = 60
            request.addValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            request.addValue("*/*", forHTTPHeaderField: "Accept")
            request.addValue("bytes=0-", forHTTPHeaderField: "Range")
            request.addValue("https://www.douyin.com/", forHTTPHeaderField: "Referer")

            do {
                let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    log("download attempt[\(index)] invalid response")
                    continue
                }

                lastStatusCode = httpResponse.statusCode
                log("download attempt[\(index)] status: \(httpResponse.statusCode), expectedLength: \(httpResponse.expectedContentLength), url: \(candidate.absoluteString)")

                guard (200..<300).contains(httpResponse.statusCode) else {
                    continue
                }

                let fileName = "douyin_\(id).mp4"
                let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
                let fileHandle = try FileHandle(forWritingTo: fileURL)
                defer { try? fileHandle.close() }

                let totalBytes = httpResponse.expectedContentLength
                var receivedBytes: Int64 = 0
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
                            progress(Double(receivedBytes) / Double(totalBytes))
                        }
                    }
                }

                // 写入剩余 buffer
                if !buffer.isEmpty {
                    fileHandle.write(buffer)
                    receivedBytes += Int64(buffer.count)
                }

                if totalBytes > 0 {
                    progress(1.0)
                }

                guard receivedBytes > 0 else { continue }

                log("downloadVideo success, file written: \(fileURL.path), bytes: \(receivedBytes)")
                return fileURL
            } catch is CancellationError {
                log("download cancelled by user")
                throw CancellationError()
            } catch {
                log("download attempt[\(index)] error: \(error.localizedDescription)")
            }
        }

        throw DouyinDownloadError.downloadFailed(statusCode: lastStatusCode)
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
}
