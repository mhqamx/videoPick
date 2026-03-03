//
//  DouyinVideoInfo.swift
//  DouyinDownLoad
//
//  Created by 马霄 on 2026/2/2.
//

import Foundation

/// 抖音视频信息
struct DouyinVideoInfo {
    /// 视频 ID
    let id: String

    /// 下载链接
    let downloadURL: URL

    /// 本地文件路径
    var localURL: URL?

    /// 视频标题
    let title: String?

    /// 封面图链接
    let coverURL: String?
}
