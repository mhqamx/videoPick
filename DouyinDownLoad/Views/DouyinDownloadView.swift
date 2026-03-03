//
//  DouyinDownloadView.swift
//  DouyinDownLoad
//
//  Created by 马霄 on 2026/2/2.
//

import SwiftUI
import AVKit

struct DouyinDownloadView: View {
    @StateObject private var viewModel = DouyinDownloadViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 标题
                    headerView

                    // 输入区域
                    inputSection

                    // 错误提示
                    if let error = viewModel.errorMessage {
                        errorView(error)
                    }

                    // 成功提示
                    if let result = viewModel.saveResult {
                        successView(result)
                    }

                    // 加载指示器
                    if viewModel.isLoading {
                        ProgressView("处理中...")
                            .padding()
                    }

                    // 视频预览
                    if viewModel.showPreview, let videoInfo = viewModel.videoInfo {
                        videoPreviewSection(videoInfo)
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("抖音视频下载")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - 子视图

    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "video.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("抖音无水印下载")
                .font(.title2)
                .fontWeight(.bold)

            Text("粘贴抖音分享链接即可下载")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical)
    }

    private var inputSection: some View {
        VStack(spacing: 12) {
            // 输入框
            HStack {
                TextField("粘贴抖音链接...", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

                if !viewModel.inputText.isEmpty {
                    Button(action: viewModel.clearInput) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }

            // 按钮组
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

            // 视频播放器
            if let localURL = videoInfo.localURL {
                VideoPlayer(player: AVPlayer(url: localURL))
                    .frame(height: 300)
                    .cornerRadius(12)

                Button(action: {
                    Task { await viewModel.saveToAlbum() }
                }) {
                    Label("保存到相册", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(viewModel.isLoading)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

#Preview {
    DouyinDownloadView()
}
