//
//  DouyinDownloadService.swift
//  DouyinDownLoad
//
//  Created by 马霄 on 2026/2/2.
//

import Foundation
import Photos
import UIKit

/// 抖音视频下载服务 (线程安全)
actor DouyinDownloadService {
    static let shared = DouyinDownloadService()

    private init() {}

    private func log(_ message: String) {
        print("[DouyinDownloadService] \(message)")
    }

    // MARK: - 公共 API

    /// 一步完成:解析并下载视频
    func parseAndDownload(_ text: String) async throws -> DouyinVideoInfo {
        log("parseAndDownload start, input length: \(text.count)")
        let url = try extractURL(from: text)
        log("extracted url: \(url.absoluteString)")
        var videoInfo = try await resolveDouyinShortURL(url)
        log("resolved video id: \(videoInfo.id), download url: \(videoInfo.downloadURL.absoluteString)")
        let localURL = try await downloadVideo(from: videoInfo.downloadURL, id: videoInfo.id)
        videoInfo.localURL = localURL
        log("parseAndDownload success, local file: \(localURL.path)")
        return videoInfo
    }

    /// 保存视频到相册
    func saveToAlbum(videoURL: URL) async throws {
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
                    continuation.resume(throwing: DouyinDownloadError.saveToAlbumFailed(reason: errorMsg))
                }
            }
        }
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

    private func findFirstDictionary(containing key: String, in value: Any) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            if dict[key] != nil { return dict }
            for child in dict.values {
                if let found = findFirstDictionary(containing: key, in: child) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = findFirstDictionary(containing: key, in: child) {
                    return found
                }
            }
        }
        return nil
    }

    private func findFirstString(forKey targetKey: String, in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if let v = dict[targetKey] as? String { return v }
            for child in dict.values {
                if let found = findFirstString(forKey: targetKey, in: child) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = findFirstString(forKey: targetKey, in: child) {
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

    private func collectVideoURLCandidates(from value: Any, into candidates: inout [String]) {
        if let dict = value as? [String: Any] {
            for (key, child) in dict {
                if key == "url_list", let arr = child as? [String] {
                    candidates.append(contentsOf: arr)
                } else if let str = child as? String,
                          str.hasPrefix("http"),
                          (str.contains("play") || str.contains("video") || str.contains(".mp4")) {
                    candidates.append(str)
                } else {
                    collectVideoURLCandidates(from: child, into: &candidates)
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectVideoURLCandidates(from: child, into: &candidates)
            }
        }
    }


    /// 下载视频
    func downloadVideo(from url: URL, id: String) async throws -> URL {
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
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    log("download attempt[\(index)] invalid response")
                    continue
                }

                lastStatusCode = httpResponse.statusCode
                log("download attempt[\(index)] status: \(httpResponse.statusCode), bytes: \(data.count), url: \(candidate.absoluteString)")

                if (200..<300).contains(httpResponse.statusCode), !data.isEmpty {
                    let fileName = "douyin_\(id).mp4"
                    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                    try data.write(to: fileURL)
                    log("downloadVideo success, file written: \(fileURL.path)")
                    return fileURL
                }
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
