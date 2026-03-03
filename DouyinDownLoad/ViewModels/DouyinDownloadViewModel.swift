//
//  DouyinDownloadViewModel.swift
//  DouyinDownLoad
//
//  Created by 马霄 on 2026/2/2.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class DouyinDownloadViewModel: ObservableObject {
    // MARK: - 发布属性

    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var videoInfo: DouyinVideoInfo?
    @Published var saveResult: String?
    @Published var showPreview: Bool = false

    // MARK: - 私有属性

    private let service = DouyinDownloadService.shared

    // MARK: - 公共方法

    /// 处理输入并下载视频
    func processInput() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "请输入抖音链接"
            return
        }

        Task {
            await downloadVideo()
        }
    }

    /// 下载视频
    func downloadVideo() async {
        isLoading = true
        errorMessage = nil
        saveResult = nil
        videoInfo = nil
        showPreview = false

        do {
            let info = try await service.parseAndDownload(inputText)
            videoInfo = info
            showPreview = true
        } catch let error as DouyinDownloadError {
            errorMessage = error.errorDescription
        } catch let urlError as URLError {
            errorMessage = networkErrorDescription(urlError)
        } catch {
            errorMessage = "未知错误: \(error.localizedDescription) (\(type(of: error)))"
        }

        isLoading = false
    }

    /// 保存到相册
    func saveToAlbum() async {
        guard let localURL = videoInfo?.localURL else {
            errorMessage = "没有可保存的视频"
            return
        }

        isLoading = true
        errorMessage = nil
        saveResult = nil

        do {
            try await service.saveToAlbum(videoURL: localURL)
            saveResult = "视频已保存到相册"
        } catch let error as DouyinDownloadError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "保存失败: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// 从剪贴板粘贴
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
            return "网络错误: 无法解析抖音域名，请检查网络或 DNS"
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
