//
//  DouyinDownloadError.swift
//  DouyinDownLoad
//
//  Created by 马霄 on 2026/2/2.
//

import Foundation

/// 抖音下载错误类型
enum DouyinDownloadError: LocalizedError {
    case invalidURL
    case urlResolutionFailed
    case videoDataNotFound
    case downloadFailed(statusCode: Int)
    case noVideoLinkFound
    case invalidVideoLink
    case saveToAlbumFailed(reason: String)
    case noPermission

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "未找到有效的抖音链接"
        case .urlResolutionFailed:
            return "链接解析失败"
        case .videoDataNotFound:
            return "未找到视频数据"
        case .downloadFailed(let statusCode):
            return "下载失败 (状态码: \(statusCode))"
        case .noVideoLinkFound:
            return "未找到视频下载链接"
        case .invalidVideoLink:
            return "无效的视频链接"
        case .saveToAlbumFailed(let reason):
            return "保存到相册失败: \(reason)"
        case .noPermission:
            return "需要相册访问权限"
        }
    }
}
