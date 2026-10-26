//
//  DouyinDownloadViewModel.swift
//  DouyinDownLoad
//
//  Created by VideoPick Contributors on 2026/2/2.
//

import Foundation
import SwiftUI
import Combine
import UIKit

enum ClipboardAutomationState: Equatable {
    case idle
    case watching
    case detecting
    case downloading
    case saving
    case saved
    case failed
}

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
    @Published var showYuanbaoLogin = false
    @Published var clipboardHint: String?
    @Published var isClipboardAutoDownloadEnabled: Bool = ClipboardAutomationStartupPolicy.startsAutomatically
    @Published var clipboardAutomationState: ClipboardAutomationState = ClipboardAutomationStartupPolicy.startsAutomatically ? .watching : .idle

    // MARK: - 私有属性

    private let service = DouyinDownloadService.shared
    private var downloadTask: Task<Void, Never>?
    private var clipboardScanTask: Task<Void, Never>?
    private var lastClipboardContent: String?
    private var lastAutoHandledFingerprint: String?
    private var clipboardHintDismissTask: Task<Void, Never>?
    private var clipboardMonitorTask: Task<Void, Never>?
    private var clipboardObserver: NSObjectProtocol?
    private var activeDownloadID = UUID()
    private var pendingChannelsDownload: (text: String, autoSave: Bool)?

    // MARK: - 公共方法

    /// 处理输入并下载视频
    func processInput() {
        guard !isLoading, !showYuanbaoLogin else { return }
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "请输入分享链接"
            return
        }

        isLoading = true
        downloadTask = Task {
            await downloadVideo()
        }
    }

    /// 取消下载
    func cancelDownload() {
        activeDownloadID = UUID()
        pendingChannelsDownload = nil
        showYuanbaoLogin = false
        downloadTask?.cancel()
        clipboardScanTask?.cancel()
        downloadTask = nil
        clipboardScanTask = nil
        isLoading = false
        downloadProgress = nil
        if isClipboardAutoDownloadEnabled {
            clipboardAutomationState = .watching
        }
    }

    /// 下载视频
    func downloadVideo(autoSaveAfterLogin: Bool = false, didRetryChannelsLogin: Bool = false) async {
        guard !Task.isCancelled else { return }
        let attemptID = UUID()
        activeDownloadID = attemptID
        let requestedText = inputText
        isLoading = true
        errorMessage = nil
        saveResult = nil
        videoInfo = nil
        showPreview = false
        downloadProgress = nil

        do {
            let info = try await service.parseAndDownload(requestedText) { [weak self] p in
                Task { @MainActor [weak self] in
                    guard self?.activeDownloadID == attemptID else { return }
                    self?.downloadProgress = p
                }
            }
            guard activeDownloadID == attemptID, !Task.isCancelled else { return }
            videoInfo = info
            showPreview = true
        } catch {
            guard activeDownloadID == attemptID else { return }
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                // Cancelled operations must not reopen login or replace a newer result.
            } else if let channelsError = error as? WeChatChannelsError {
                if channelsError == .loginRequired, !didRetryChannelsLogin {
                    pendingChannelsDownload = (requestedText, autoSaveAfterLogin)
                    showYuanbaoLogin = true
                } else if channelsError == .loginRequired {
                    errorMessage = "元宝仍无法解析此视频，请稍后重试或在设置中重新登录。"
                } else { errorMessage = channelsError.errorDescription }
            } else if let downloadError = error as? DouyinDownloadError {
                errorMessage = downloadError.errorDescription
            } else if let urlError = error as? URLError {
                errorMessage = networkErrorDescription(urlError)
            } else {
                errorMessage = "下载失败: \(error.localizedDescription)"
            }
        }

        guard activeDownloadID == attemptID else { return }
        isLoading = false
        downloadProgress = nil
    }

    func yuanbaoLoginCompleted() {
        guard let pending = pendingChannelsDownload else { return }
        pendingChannelsDownload = nil
        showYuanbaoLogin = false
        inputText = pending.text
        isLoading = true
        downloadTask = Task {
            await downloadVideo(autoSaveAfterLogin: pending.autoSave, didRetryChannelsLogin: true)
            guard !Task.isCancelled, pending.autoSave, videoInfo != nil, errorMessage == nil else { return }
            clipboardAutomationState = .saving
            await saveMedia()
            clipboardAutomationState = errorMessage == nil ? .saved : .failed
        }
    }

    func yuanbaoLoginDismissed() {
        guard pendingChannelsDownload != nil else { return }
        pendingChannelsDownload = nil
        showYuanbaoLogin = false
        if isClipboardAutoDownloadEnabled { clipboardAutomationState = .watching }
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
    func pasteFromClipboard() {
        if let clipboardString = UIPasteboard.general.string {
            inputText = clipboardString
            lastClipboardContent = clipboardString
        }
    }

    /// 开启剪贴板自动捕获。首次读取剪贴板时，系统会在需要时展示粘贴板授权。
    func authorizeClipboardAndStartAutoDownload() {
        isClipboardAutoDownloadEnabled = true
        clipboardAutomationState = .detecting
        beginClipboardMonitoring()
        scheduleClipboardScan(reason: "手动授权")
    }

    func startClipboardAutoDownloadIfNeeded(reason: String = "自动启动") {
        guard ClipboardAutomationStartupPolicy.startsAutomatically else { return }
        guard !isClipboardAutoDownloadEnabled else {
            beginClipboardMonitoring()
            scheduleClipboardScan(reason: reason)
            return
        }

        isClipboardAutoDownloadEnabled = true
        clipboardAutomationState = .detecting
        beginClipboardMonitoring()
        scheduleClipboardScan(reason: reason)
    }

    func stopClipboardAutoDownload() {
        cancelDownload()
        isClipboardAutoDownloadEnabled = false
        clipboardAutomationState = .idle
        downloadTask?.cancel()
        clipboardMonitorTask?.cancel()
        clipboardScanTask?.cancel()
        downloadTask = nil
        clipboardMonitorTask = nil
        clipboardScanTask = nil
        isLoading = false
        downloadProgress = nil

        if let clipboardObserver {
            NotificationCenter.default.removeObserver(clipboardObserver)
            self.clipboardObserver = nil
        }

        showClipboardHint("剪贴板雷达已关闭")
    }

    /// App 进入前台时调用：自动模式下扫描并尝试下载；手动模式下仅做轻提示。
    func checkClipboardOnForeground() {
        startClipboardAutoDownloadIfNeeded(reason: "前台唤醒")
    }

    func handleAuthorizedPaste(_ text: String) {
        inputText = text
        lastClipboardContent = text
        authorizeClipboardAndStartAutoDownload()
    }

    private func showClipboardHint(_ message: String) {
        clipboardHintDismissTask?.cancel()
        clipboardHint = message

        clipboardHintDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.clipboardHint = nil
        }
    }

    /// 清空输入
    func clearInput() {
        cancelDownload()
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

    private func beginClipboardMonitoring() {
        if clipboardObserver == nil {
            clipboardObserver = NotificationCenter.default.addObserver(
                forName: UIPasteboard.changedNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard self?.isLoading == false else { return }
                    self?.scheduleClipboardScan(reason: "剪贴板变化")
                }
            }
        }

        guard clipboardMonitorTask == nil else { return }
        clipboardMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard let self, self.isClipboardAutoDownloadEnabled, !self.isLoading else { continue }
                self.scheduleClipboardScan(reason: "定时扫描")
            }
        }
    }

    private func scheduleClipboardScan(reason: String) {
        guard !isLoading, !showYuanbaoLogin else { return }
        clipboardScanTask?.cancel()
        clipboardScanTask = Task { @MainActor [weak self] in
            await self?.scanClipboardForAutoDownload(reason: reason)
        }
    }

    private func scanClipboardForAutoDownload(reason: String) async {
        guard isClipboardAutoDownloadEnabled, !isLoading, !showYuanbaoLogin else { return }

        clipboardAutomationState = .detecting
        guard await pasteboardLikelyContainsWebURL() else {
            clipboardAutomationState = .watching
            return
        }
        guard !Task.isCancelled, !isLoading, !showYuanbaoLogin else { return }

        guard let clipboardString = UIPasteboard.general.string,
              let candidate = ClipboardAutoDownloadCandidate.resolve(
                from: clipboardString,
                lastHandledFingerprint: lastAutoHandledFingerprint
              ) else {
            clipboardAutomationState = .watching
            return
        }

        lastClipboardContent = candidate.text
        lastAutoHandledFingerprint = candidate.fingerprint
        inputText = candidate.text
        showClipboardHint("\(reason)捕获到新链接，正在自动下载并保存")

        clipboardAutomationState = .downloading
        await downloadVideo(autoSaveAfterLogin: true)

        guard !Task.isCancelled, !showYuanbaoLogin else { return }

        guard errorMessage == nil, videoInfo != nil else {
            clipboardAutomationState = .failed
            return
        }

        clipboardAutomationState = .saving
        await saveMedia()

        if errorMessage == nil {
            clipboardAutomationState = .saved
            showClipboardHint("已自动下载并保存到相册")
        } else {
            clipboardAutomationState = .failed
        }
    }

    private func pasteboardLikelyContainsWebURL() async -> Bool {
        guard UIPasteboard.general.hasStrings else { return false }

        do {
            let webURLPattern = \UIPasteboard.DetectedValues.probableWebURL
            let patterns = try await UIPasteboard.general.detectedPatterns(for: [webURLPattern])
            return patterns.contains(webURLPattern)
        } catch {
            return true
        }
    }
}
