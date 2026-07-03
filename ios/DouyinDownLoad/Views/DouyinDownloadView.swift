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

// MARK: - 全屏图片查看器（支持缩放 + 左右翻页）

private struct FullscreenImageViewer: View {
    let imageURLs: [URL]
    @Binding var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, url in
                    ZoomableImageView(url: url)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))

            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                            .shadow(radius: 4)
                    }
                    .padding(20)
                }

                Spacer()

                Text("\(currentIndex + 1) / \(imageURLs.count)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 40)
            }
        }
        .statusBarHidden(true)
    }
}

private struct ZoomableImageView: View {
    let url: URL
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            if let data = try? Data(contentsOf: url),
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scale = max(1.0, lastScale * value.magnification)
                            }
                            .onEnded { value in
                                lastScale = scale
                                if scale <= 1.0 {
                                    withAnimation(.spring(duration: 0.3)) {
                                        scale = 1.0
                                        lastScale = 1.0
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                guard scale > 1.0 else { return }
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(duration: 0.3)) {
                            if scale > 1.0 {
                                scale = 1.0
                                lastScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 3.0
                                lastScale = 3.0
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
            } else {
                ProgressView()
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

struct DouyinDownloadView: View {
    @StateObject private var viewModel = DouyinDownloadViewModel()
    @State private var selectedImageIndex: Int = 0
    @State private var showFullscreenImage = false
    @State private var showCookieSettings = false
    @Environment(\.scenePhase) private var scenePhase

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
        .onAppear {
            viewModel.checkClipboardOnForeground()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                viewModel.checkClipboardOnForeground()
            }
        }
    }

    // MARK: - iOS 布局

    private var phoneLayout: some View {
        NavigationView {
            ZStack {
                TechBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        headerView
                        automationPanel
                        inputSection
                        statusSection
                        if viewModel.showPreview, let videoInfo = viewModel.videoInfo {
                            videoPreviewSection(videoInfo)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("VideoPick")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCookieSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(TechPalette.cyan)
                    }
                }
            }
            .sheet(isPresented: $showCookieSettings) {
                CookieSettingsView()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Mac 布局（双栏填充）

    private var macLayout: some View {
        HStack(spacing: 0) {
            // 左栏：输入 + 控制
            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    Button {
                        showCookieSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .sheet(isPresented: $showCookieSettings) {
                        CookieSettingsView()
                    }
                }

                headerView

                automationPanel

                inputSection

                statusSection

                Spacer()
            }
            .padding(28)
            .frame(minWidth: 340, idealWidth: 400, maxWidth: 460)
            .background(TechPalette.void)

            // 右栏：视频预览
            ZStack {
                TechBackground()

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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("VIDEO PICK")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(TechPalette.amber)

                    Text("无水印捕获舱")
                        .font(.system(size: isMac ? 28 : 34, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text("抖音 / TikTok / Instagram / X / B站 / 快手 / 小红书")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(TechPalette.mist)
                        .lineLimit(2)
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(TechPalette.cyan.opacity(0.28), lineWidth: 1)
                        .frame(width: 58, height: 58)
                    Circle()
                        .stroke(TechPalette.amber.opacity(0.55), lineWidth: 2)
                        .frame(width: 42, height: 42)
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(TechPalette.cyan)
                }
                .accessibilityHidden(true)
            }

            HStack(spacing: 10) {
                TechMetric(value: viewModel.isClipboardAutoDownloadEnabled ? "AUTO" : "MANUAL", label: "MODE")
                TechMetric(value: viewModel.videoInfo?.mediaType == .images ? "IMAGE" : "VIDEO", label: "PAYLOAD")
                TechMetric(value: viewModel.isLoading ? "LIVE" : "READY", label: "PIPE")
            }
        }
        .padding(18)
        .techPanel()
    }

    private var automationPanel: some View {
        let status = automationStatus

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(status.color.opacity(0.18), lineWidth: 8)
                        .frame(width: 54, height: 54)
                    Image(systemName: status.icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(status.color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("剪贴板雷达")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(status.detail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(TechPalette.mist)
                        .lineLimit(2)
                }

                Spacer()

                Text(status.title)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(status.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(status.color.opacity(0.12), in: Capsule())
                    .overlay(
                        Capsule().stroke(status.color.opacity(0.35), lineWidth: 1)
                    )
            }

            HStack(spacing: 10) {
                Button {
                    if viewModel.isClipboardAutoDownloadEnabled {
                        viewModel.stopClipboardAutoDownload()
                    } else {
                        viewModel.startClipboardAutoDownloadIfNeeded(reason: "手动恢复")
                    }
                } label: {
                    Label(
                        viewModel.isClipboardAutoDownloadEnabled ? "关闭雷达" : "恢复雷达",
                        systemImage: viewModel.isClipboardAutoDownloadEnabled ? "pause.fill" : "dot.radiowaves.left.and.right"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(TechPrimaryButtonStyle(color: status.color))
                .disabled(viewModel.isLoading && !viewModel.isClipboardAutoDownloadEnabled)

                Button(action: viewModel.pasteFromClipboard) {
                    Image(systemName: "doc.on.clipboard")
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(TechIconButtonStyle())
                .accessibilityLabel("粘贴")
            }
        }
        .padding(16)
        .techPanel(accent: status.color)
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "link.badge.plus")
                    .foregroundStyle(TechPalette.cyan)
                Text("手动链路")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
            }

            ZStack(alignment: .topTrailing) {
                TextField("粘贴分享链接", text: $viewModel.inputText, axis: .vertical)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(3...6)
                    .padding(14)
                    .padding(.trailing, viewModel.inputText.isEmpty ? 0 : 34)
                    .background(TechPalette.panel.opacity(0.86), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(TechPalette.cyan.opacity(0.22), lineWidth: 1)
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !viewModel.inputText.isEmpty {
                    Button(action: viewModel.clearInput) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(TechPalette.mist)
                            .padding(10)
                    }
                    .accessibilityLabel("清空")
                }
            }

            HStack(spacing: 12) {
                Button(action: viewModel.processInput) {
                    Label("解析下载", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TechPrimaryButtonStyle(color: TechPalette.cyan))
                .disabled(viewModel.inputText.isEmpty || viewModel.isLoading)
            }
        }
        .padding(16)
        .techPanel()
    }

    @ViewBuilder
    private var statusSection: some View {
        VStack(spacing: 10) {
            if let hint = viewModel.clipboardHint {
                clipboardHintView(hint)
            }

            if let error = viewModel.errorMessage {
                errorView(error)
            }

            if let result = viewModel.saveResult {
                successView(result)
            }

            if viewModel.isLoading {
                VStack(spacing: 10) {
                    if let progress = viewModel.downloadProgress {
                        ProgressView(value: progress)
                            .tint(TechPalette.cyan)
                        Text("下载中 \(Int(progress * 100))%")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(TechPalette.mist)
                    } else {
                        ProgressView("解析中")
                            .tint(TechPalette.cyan)
                            .foregroundStyle(TechPalette.mist)
                    }

                    Button(action: viewModel.cancelDownload) {
                        Label("取消", systemImage: "xmark.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(TechPalette.warning)
                }
                .padding(14)
                .techPanel(accent: TechPalette.cyan)
            }
        }
    }

    // MARK: - Mac 专用预览

    private var emptyPreviewPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 64))
                .foregroundStyle(TechPalette.cyan.opacity(0.35))
            Text("视频预览区域")
                .font(.title3)
                .foregroundStyle(TechPalette.mist)
            Text("粘贴链接并下载后，视频将在此处播放")
                .font(.subheadline)
                .foregroundStyle(TechPalette.mist.opacity(0.7))
        }
    }

    private func macPreviewSection(_ videoInfo: DouyinVideoInfo) -> some View {
        VStack(spacing: 16) {
            if let title = videoInfo.title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
            }

            switch videoInfo.mediaType {
            case .video:
                if let localURL = videoInfo.localURL {
                    StableVideoPlayerView(url: localURL)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 24)

                    saveButton
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                }
            case .images:
                if !videoInfo.localImageURLs.isEmpty {
                    imageGalleryView(videoInfo.localImageURLs)
                        .padding(.horizontal, 24)

                    Text("共 \(videoInfo.localImageURLs.count) 张图片")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    saveButton
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                }
            }
        }
    }

    // MARK: - iOS 媒体预览

    private func videoPreviewSection(_ videoInfo: DouyinVideoInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: videoInfo.mediaType == .video ? "play.rectangle.fill" : "photo.stack.fill")
                    .foregroundStyle(TechPalette.amber)
                Text(videoInfo.mediaType == .video ? "视频载荷" : "图文载荷")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
            }

            if let title = videoInfo.title {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TechPalette.mist)
                    .lineLimit(3)
            }

            switch videoInfo.mediaType {
            case .video:
                if let localURL = videoInfo.localURL {
                    StableVideoPlayerView(url: localURL)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(TechPalette.cyan.opacity(0.24), lineWidth: 1)
                        )

                    saveButton
                }
            case .images:
                if !videoInfo.localImageURLs.isEmpty {
                    Text("共 \(videoInfo.localImageURLs.count) 张图片")
                        .font(.caption)
                        .foregroundStyle(TechPalette.mist)

                    imageGalleryView(videoInfo.localImageURLs)
                        .frame(height: 300)

                    saveButton
                }
            }
        }
        .padding(16)
        .techPanel(accent: TechPalette.amber)
    }

    // MARK: - 图片缩略图网格

    private let thumbColumns = [
        GridItem(.adaptive(minimum: 80, maximum: 120), spacing: 8)
    ]

    private func imageGalleryView(_ imageURLs: [URL]) -> some View {
        LazyVGrid(columns: thumbColumns, spacing: 8) {
            ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, url in
                Button {
                    selectedImageIndex = index
                    showFullscreenImage = true
                } label: {
                    if let data = try? Data(contentsOf: url),
                       let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(minWidth: 80, minHeight: 80)
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(TechPalette.panel.opacity(0.8))
                            .aspectRatio(1, contentMode: .fill)
                            .overlay(ProgressView())
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showFullscreenImage) {
            FullscreenImageViewer(
                imageURLs: imageURLs,
                currentIndex: $selectedImageIndex
            )
        }
    }

    // MARK: - 通用组件

    private var saveButton: some View {
        Button(action: {
            Task { await viewModel.saveMedia() }
        }) {
            #if targetEnvironment(macCatalyst)
            let saveLabel = "保存到下载目录"
            #else
            let saveLabel = "保存到相册"
            #endif
            Label(saveLabel, systemImage: "square.and.arrow.down")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(TechPrimaryButtonStyle(color: TechPalette.amber))
        .disabled(viewModel.isLoading)
    }

    private func errorView(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(TechPalette.warning)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TechPalette.warning)
                .lineLimit(3)
            Spacer()
        }
        .padding(14)
        .techPanel(accent: TechPalette.warning)
    }

    private func clipboardHintView(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard.fill")
                .foregroundStyle(TechPalette.cyan)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TechPalette.cyan)
                .lineLimit(2)
            Spacer()
        }
        .padding(14)
        .techPanel(accent: TechPalette.cyan)
        .transition(.opacity)
    }

    private func successView(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(TechPalette.mint)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TechPalette.mint)
                .lineLimit(2)
            Spacer()
        }
        .padding(14)
        .techPanel(accent: TechPalette.mint)
    }

    private var automationStatus: (title: String, detail: String, icon: String, color: Color) {
        switch viewModel.clipboardAutomationState {
        case .idle:
            return ("待授权", "手动模式", "dot.radiowaves.left.and.right", TechPalette.mist)
        case .watching:
            return ("监听中", "等待新链接", "waveform.path.ecg", TechPalette.cyan)
        case .detecting:
            return ("扫描", "读取剪贴板信号", "scope", TechPalette.cyan)
        case .downloading:
            return ("下载", "媒体流入站", "arrow.down.circle.fill", TechPalette.amber)
        case .saving:
            return ("保存", "写入相册", "photo.badge.checkmark", TechPalette.amber)
        case .saved:
            return ("完成", "已归档", "checkmark.seal.fill", TechPalette.mint)
        case .failed:
            return ("异常", "等待下一条链接", "exclamationmark.triangle.fill", TechPalette.warning)
        }
    }
}

private enum TechPalette {
    static let void = Color(red: 0.02, green: 0.025, blue: 0.032)
    static let panel = Color(red: 0.055, green: 0.075, blue: 0.085)
    static let cyan = Color(red: 0.23, green: 0.88, blue: 0.93)
    static let mint = Color(red: 0.35, green: 0.95, blue: 0.62)
    static let amber = Color(red: 1.0, green: 0.68, blue: 0.25)
    static let mist = Color(red: 0.70, green: 0.79, blue: 0.82)
    static let warning = Color(red: 1.0, green: 0.34, blue: 0.30)
}

private struct TechBackground: View {
    var body: some View {
        ZStack {
            TechPalette.void.ignoresSafeArea()

            LinearGradient(
                colors: [
                    TechPalette.cyan.opacity(0.16),
                    .clear,
                    TechPalette.amber.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            CircuitGrid()
                .stroke(TechPalette.cyan.opacity(0.11), lineWidth: 0.7)
                .ignoresSafeArea()
        }
    }
}

private struct CircuitGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 28

        var x: CGFloat = 0
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += step
        }

        var y: CGFloat = 0
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += step
        }

        return path
    }
}

private struct TechMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(TechPalette.mist.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(TechPalette.panel.opacity(0.82), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(TechPalette.cyan.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct TechPanelModifier: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .background(TechPalette.panel.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        LinearGradient(
                            colors: [accent.opacity(0.55), TechPalette.mist.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: accent.opacity(0.10), radius: 16, x: 0, y: 8)
    }
}

private extension View {
    func techPanel(accent: Color = TechPalette.cyan) -> some View {
        modifier(TechPanelModifier(accent: accent))
    }
}

private struct TechPrimaryButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(TechPalette.void)
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(color.opacity(configuration.isPressed ? 0.74 : 0.95), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(configuration.isPressed ? 0.18 : 0.35), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct TechIconButtonStyle: ButtonStyle {
    var color: Color = TechPalette.cyan

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(color)
            .background(TechPalette.panel.opacity(configuration.isPressed ? 0.92 : 0.72), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color.opacity(configuration.isPressed ? 0.55 : 0.28), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

#Preview {
    DouyinDownloadView()
}
