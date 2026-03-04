//
//  DouyinDownloadView.swift
//  DouyinDownLoad
//
//  Created by 马霄 on 2026/2/2.
//

import SwiftUI
import AVKit
import Combine

final class StableAVPlayerStore: ObservableObject {
    let player: AVPlayer

    init(url: URL) {
        self.player = AVPlayer(url: url)
        self.player.actionAtItemEnd = .pause
    }

    deinit {
        player.pause()
    }
}

private struct StableVideoPlayerView: View {
    @StateObject private var store: StableAVPlayerStore

    init(url: URL) {
        _store = StateObject(wrappedValue: StableAVPlayerStore(url: url))
    }

    var body: some View {
        VideoPlayer(player: store.player)
            .onDisappear {
                store.player.pause()
            }
    }
}

struct DouyinDownloadView: View {
    @StateObject private var viewModel = DouyinDownloadViewModel()

    #if targetEnvironment(macCatalyst)
    private let isMac = true
    #else
    private let isMac = false
    #endif

    var body: some View {
        Group {
            if isMac {
                macLayout
            } else {
                phoneLayout
            }
        }
    }

    // MARK: - iOS 布局（保持原样）

    private var phoneLayout: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    headerView
                    inputSection
                    statusSection
                    if viewModel.showPreview, let videoInfo = viewModel.videoInfo {
                        videoPreviewSection(videoInfo)
                    }
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("短视频下载")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Mac 布局（双栏填充）

    private var macLayout: some View {
        HStack(spacing: 0) {
            // 左栏：输入 + 控制
            VStack(spacing: 24) {
                headerView

                inputSection

                statusSection

                Spacer()
            }
            .padding(28)
            .frame(minWidth: 340, idealWidth: 400, maxWidth: 460)
            .background(Color(white: 0.14))

            // 右栏：视频预览
            ZStack {
                Color(white: 0.10)

                if viewModel.showPreview, let videoInfo = viewModel.videoInfo {
                    macPreviewSection(videoInfo)
                } else {
                    emptyPreviewPlaceholder
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - 公共子视图

    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "video.circle.fill")
                .font(.system(size: isMac ? 48 : 60))
                .foregroundColor(.blue)

            Text("短视频无水印下载")
                .font(isMac ? .title3 : .title2)
                .fontWeight(.bold)

            Text("支持抖音、TikTok、B站、快手、小红书分享链接")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, isMac ? 12 : 16)
    }

    private var inputSection: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("粘贴分享链接...", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

                if !viewModel.inputText.isEmpty {
                    Button(action: viewModel.clearInput) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }

            HStack(spacing: 12) {
                Button(action: viewModel.pasteFromClipboard) {
                    Label("粘贴", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: viewModel.processInput) {
                    Label("下载", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.inputText.isEmpty || viewModel.isLoading)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var statusSection: some View {
        if let error = viewModel.errorMessage {
            errorView(error)
        }

        if let result = viewModel.saveResult {
            successView(result)
        }

        if viewModel.isLoading {
            VStack(spacing: 8) {
                if let progress = viewModel.downloadProgress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text("下载中 \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ProgressView("解析中...")
                }

                Button(action: viewModel.cancelDownload) {
                    Label("取消", systemImage: "xmark.circle")
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
            }
            .padding()
        }
    }

    // MARK: - Mac 专用预览

    private var emptyPreviewPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 64))
                .foregroundColor(.gray.opacity(0.3))
            Text("视频预览区域")
                .font(.title3)
                .foregroundColor(.gray.opacity(0.4))
            Text("粘贴链接并下载后，视频将在此处播放")
                .font(.subheadline)
                .foregroundColor(.gray.opacity(0.3))
        }
    }

    private func macPreviewSection(_ videoInfo: DouyinVideoInfo) -> some View {
        VStack(spacing: 16) {
            if let title = videoInfo.title {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
            }

            if let localURL = videoInfo.localURL {
                StableVideoPlayerView(url: localURL)
                    .cornerRadius(12)
                    .padding(.horizontal, 24)

                saveButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
            }
        }
    }

    // MARK: - iOS 视频预览

    private func videoPreviewSection(_ videoInfo: DouyinVideoInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("视频信息")
                .font(.headline)

            if let title = videoInfo.title {
                HStack {
                    Text("标题:")
                        .foregroundColor(.secondary)
                    Text(title)
                        .lineLimit(2)
                }
                .font(.subheadline)
            }

            if let localURL = videoInfo.localURL {
                StableVideoPlayerView(url: localURL)
                    .frame(height: 300)
                    .cornerRadius(12)

                saveButton
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - 通用组件

    private var saveButton: some View {
        Button(action: {
            Task { await viewModel.saveVideo() }
        }) {
            #if targetEnvironment(macCatalyst)
            let saveLabel = "保存到下载目录"
            #else
            let saveLabel = "保存到相册"
            #endif
            Label(saveLabel, systemImage: "square.and.arrow.down")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
        }
        .disabled(viewModel.isLoading)
    }

    private func errorView(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.red)
            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }

    private func successView(_ message: String) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.green)
            Spacer()
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    DouyinDownloadView()
}
