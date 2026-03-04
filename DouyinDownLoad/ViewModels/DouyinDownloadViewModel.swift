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

    /// 保存视频（iOS 保存到相册，macOS 保存到下载目录）
    func saveVideo() async {
        guard let localURL = videoInfo?.localURL else {
            errorMessage = "没有可保存的视频"
            return
        }

        isLoading = true
        errorMessage = nil
        saveResult = nil

        do {
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
        }
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
