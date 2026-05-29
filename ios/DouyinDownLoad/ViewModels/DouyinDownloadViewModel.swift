//
//  DouyinDownloadViewModel.swift
//  DouyinDownLoad
//
//  Created by 马霄 on 2026/2/2.
//

import Foundation
import SwiftUI
import Combine
import UIKit

@MainActor
class DouyinDownloadViewModel: ObservableObject {
    // MARK: - 发布属性

    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var videoInfo: DouyinVideoInfo?
    @Published var saveResult: String?
    @Published var showPreview: Bool = false
    @Published var downloadProgress: Double?

    // MARK: - 私有属性

    private let service = DouyinDownloadService.shared
    private var downloadTask: Task<Void, Never>?
    /// 最近一次自动粘贴消费过的剪贴板内容，避免重复回填
    private var lastAutoPastedClipboard: String?

    /// 用户偏好：下载完成后是否自动保存到相册
    private var autoSaveEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppSettings.autoSaveKey)
    }

    // MARK: - 公共方法

    /// 处理输入并下载视频
    func processInput() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "请输入分享链接"
            return
        }

        downloadTask = Task {
            await downloadVideo()
        }
    }

    /// 取消下载
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isLoading = false
        downloadProgress = nil
    }

    /// 下载视频
    func downloadVideo() async {
        isLoading = true
        errorMessage = nil
        saveResult = nil
        videoInfo = nil
        showPreview = false
        downloadProgress = nil

        do {
            let info = try await service.parseAndDownload(inputText) { [weak self] p in
                Task { @MainActor in
                    self?.downloadProgress = p
                }
            }
            videoInfo = info
            showPreview = true
            isLoading = false
            downloadProgress = nil
            // 用户开启了自动保存，则下载完毕直接归档到相册
            if autoSaveEnabled {
                await saveMedia()
            }
            return
        } catch is CancellationError {
            // 用户主动取消，不显示错误
        } catch let error as DouyinDownloadError {
            errorMessage = error.errorDescription
        } catch let urlError as URLError {
            errorMessage = networkErrorDescription(urlError)
        } catch {
            errorMessage = "未知错误: \(error.localizedDescription) (\(type(of: error)))"
        }

        isLoading = false
        downloadProgress = nil
    }

    /// 保存媒体到相册（根据 mediaType 保存视频或图片）
    func saveMedia() async {
        guard let info = videoInfo else {
            errorMessage = "没有可保存的内容"
            return
        }

        isLoading = true
        errorMessage = nil
        saveResult = nil

        do {
            switch info.mediaType {
            case .video:
                guard let localURL = info.localURL else {
                    errorMessage = "没有可保存的视频"
                    isLoading = false
                    return
                }
                let savedURL = try await service.saveVideo(videoURL: localURL)
                #if targetEnvironment(macCatalyst)
                if let url = savedURL {
                    saveResult = "视频已保存到: \(url.lastPathComponent)"
                } else {
                    saveResult = "视频已保存"
                }
                #elseif os(iOS)
                saveResult = "视频已保存到相册"
                #else
                if let url = savedURL {
                    saveResult = "视频已保存到: \(url.lastPathComponent)"
                } else {
                    saveResult = "视频已保存"
                }
                #endif

            case .images:
                guard !info.localImageURLs.isEmpty else {
                    errorMessage = "没有可保存的图片"
                    isLoading = false
                    return
                }
                try await service.saveImages(imageURLs: info.localImageURLs)
                saveResult = "\(info.localImageURLs.count) 张图片已保存到相册"
            }
        } catch let error as DouyinDownloadError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "保存失败: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// 从剪贴板粘贴（Mac Catalyst 下 UIPasteboard 自动桥接 macOS 剪贴板）
    /// 手动点击粘贴按钮：填入剪贴板内容后立即触发下载
    func pasteFromClipboard() {
        guard let clipboardString = UIPasteboard.general.string else { return }
        let trimmed = clipboardString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = trimmed
        lastAutoPastedClipboard = trimmed
        if trimmed.range(of: #"https?://"#, options: .regularExpression) != nil {
            processInput()
        }
    }

    /// App 进入前台时尝试自动回填剪贴板里的分享链接，并直接触发下载
    /// 规则：1) 必须包含 http(s) 链接；2) 与当前输入或上次自动粘贴的内容不同；3) 没有正在下载
    func autoPasteFromClipboardIfNeeded() {
        guard !isLoading else { return }
        guard UIPasteboard.general.hasStrings else { return }
        guard let raw = UIPasteboard.general.string else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed.range(of: #"https?://"#, options: .regularExpression) != nil else { return }
        if trimmed == lastAutoPastedClipboard { return }
        if trimmed == inputText.trimmingCharacters(in: .whitespacesAndNewlines) { return }

        inputText = trimmed
        lastAutoPastedClipboard = trimmed
        errorMessage = nil
        saveResult = nil
        processInput()
    }

    /// 清空输入
    func clearInput() {
        inputText = ""
        errorMessage = nil
        saveResult = nil
        videoInfo = nil
        showPreview = false
    }

    /// 关闭预览
    func dismissPreview() {
        showPreview = false
    }

    private func networkErrorDescription(_ error: URLError) -> String {
        switch error.code {
        case .cannotFindHost, .dnsLookupFailed:
            return "网络错误: 无法解析域名，请检查网络或 DNS"
        case .notConnectedToInternet:
            return "网络错误: 当前设备未连接互联网"
        case .timedOut:
            return "网络错误: 请求超时，请稍后重试"
        case .cannotConnectToHost:
            return "网络错误: 无法连接到服务器"
        default:
            return "网络错误: \(error.localizedDescription) (\(error.code.rawValue))"
        }
    }
}
