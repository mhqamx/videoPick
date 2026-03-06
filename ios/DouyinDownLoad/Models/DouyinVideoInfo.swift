//
//  DouyinVideoInfo.swift
//  DouyinDownLoad
//
//  Created by 马霄 on 2026/2/2.
//

import Foundation

/// 媒体类型
enum MediaType: String {
    case video
    case images = "image"
}

/// 抖音视频/图文信息
struct DouyinVideoInfo {
    /// 视频 ID
    let id: String

    /// 下载链接（视频为视频 URL，图文为第一张图片 URL）
    let downloadURL: URL

    /// 本地文件路径（视频）
    var localURL: URL?

    /// 视频标题
    let title: String?

    /// 封面图链接
    let coverURL: String?

    /// 媒体类型
    let mediaType: MediaType

    /// 图片下载 URL 列表（仅图文作品）
    let imageURLs: [URL]

    /// 下载后的本地图片路径列表
    var localImageURLs: [URL] = []

    init(id: String, downloadURL: URL, localURL: URL? = nil, title: String? = nil,
         coverURL: String? = nil, mediaType: MediaType = .video, imageURLs: [URL] = []) {
        self.id = id
        self.downloadURL = downloadURL
        self.localURL = localURL
        self.title = title
        self.coverURL = coverURL
        self.mediaType = mediaType
        self.imageURLs = imageURLs
    }
}
