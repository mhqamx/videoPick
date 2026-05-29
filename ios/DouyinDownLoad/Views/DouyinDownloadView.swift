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

// MARK: - Neo-Cyber 设计系统

private enum NeoCyber {
    static let void = Color(red: 0.018, green: 0.026, blue: 0.058)            // #05070F
    static let abyss = Color(red: 0.035, green: 0.05, blue: 0.10)             // #090D1A
    static let surface = Color(red: 0.07, green: 0.10, blue: 0.18)            // #121A2D
    static let cyan = Color(red: 0.0, green: 0.898, blue: 1.0)                // #00E5FF
    static let magenta = Color(red: 1.0, green: 0.176, blue: 0.478)           // #FF2D7A
    static let lime = Color(red: 0.482, green: 1.0, blue: 0.380)              // #7BFF61
    static let amber = Color(red: 1.0, green: 0.733, blue: 0.0)               // #FFBB00
    static let textPrimary = Color(red: 0.91, green: 0.95, blue: 1.0)
    static let textMuted = Color(red: 0.56, green: 0.64, blue: 0.78)

    static let display = Font.system(.title, design: .rounded).weight(.heavy)
    static let displaySmall = Font.system(.title3, design: .rounded).weight(.bold)
    static let mono = Font.system(.body, design: .monospaced).weight(.medium)
    static let monoSmall = Font.system(.caption, design: .monospaced).weight(.medium)
    static let label = Font.system(.subheadline, design: .rounded).weight(.semibold)
}

// MARK: - 动态宇宙背景（统一为单 TimelineView + Canvas 离屏合成，避免多层 SwiftUI diff）

private struct NeoCyberBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [NeoCyber.void, NeoCyber.abyss, Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // 等距网格静态层：不绑定 TimelineView，不会随帧重绘
            GridLines()
                .stroke(NeoCyber.cyan.opacity(0.08), lineWidth: 0.5)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // 单个 TimelineView 驱动光晕 + 扫描线，限制 20fps 足够丝滑
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: false)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    // 青色光晕
                    let cyanCenter = CGPoint(
                        x: size.width * (0.2 + 0.08 * CGFloat(sin(t * 0.3))),
                        y: size.height * (0.18 + 0.05 * CGFloat(cos(t * 0.4)))
                    )
                    let cyanRect = CGRect(
                        x: cyanCenter.x - 360, y: cyanCenter.y - 360,
                        width: 720, height: 720
                    )
                    ctx.drawLayer { layerCtx in
                        layerCtx.fill(
                            Path(ellipseIn: cyanRect),
                            with: .radialGradient(
                                Gradient(colors: [NeoCyber.cyan.opacity(0.35), .clear]),
                                center: cyanCenter, startRadius: 0, endRadius: 360
                            )
                        )
                    }
                    // 品红光晕
                    let magCenter = CGPoint(
                        x: size.width * (0.85 + 0.08 * CGFloat(cos(t * 0.25))),
                        y: size.height * (0.88 + 0.05 * CGFloat(sin(t * 0.35)))
                    )
                    let magRect = CGRect(
                        x: magCenter.x - 420, y: magCenter.y - 420,
                        width: 840, height: 840
                    )
                    ctx.drawLayer { layerCtx in
                        layerCtx.fill(
                            Path(ellipseIn: magRect),
                            with: .radialGradient(
                                Gradient(colors: [NeoCyber.magenta.opacity(0.28), .clear]),
                                center: magCenter, startRadius: 0, endRadius: 420
                            )
                        )
                    }
                    // 扫描线
                    let bandY = (CGFloat(t.truncatingRemainder(dividingBy: 6)) / 6) * size.height
                    ctx.fill(
                        Path(CGRect(x: 0, y: bandY, width: size.width, height: 1.5)),
                        with: .color(NeoCyber.cyan.opacity(0.06))
                    )
                }
                .drawingGroup() // 强制 Metal 离屏合成，避免主线程 layout
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

private struct GridLines: Shape {
    var step: CGFloat = 36
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x: CGFloat = 0
        while x < rect.width {
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: rect.height))
            x += step
        }
        var y: CGFloat = 0
        while y < rect.height {
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: rect.width, y: y))
            y += step
        }
        return p
    }
}

// MARK: - 玻璃面板修饰

private struct HoloPanel: ViewModifier {
    var glow: Color = NeoCyber.cyan
    var corner: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.white.opacity(0.04), Color.clear],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [glow.opacity(0.65), glow.opacity(0.1), glow.opacity(0.55)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: glow.opacity(0.22), radius: 18, x: 0, y: 0)
    }
}

private extension View {
    func holoPanel(glow: Color = NeoCyber.cyan, corner: CGFloat = 18) -> some View {
        modifier(HoloPanel(glow: glow, corner: corner))
    }
}

// MARK: - 能量进度环 + 粒子

private struct NeonProgressRing: View {
    var progress: Double?       // nil = indeterminate
    var size: CGFloat = 200

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let spin = Angle.degrees((t.truncatingRemainder(dividingBy: 4)) / 4 * 360)
            let reverseSpin = Angle.degrees(-(t.truncatingRemainder(dividingBy: 6)) / 6 * 360)
            let pulse = 0.85 + 0.15 * sin(t * 2.4)

            ZStack {
                // 外圈底纹
                Circle()
                    .strokeBorder(NeoCyber.cyan.opacity(0.10), lineWidth: 1)
                    .frame(width: size, height: size)

                // 旋转刻度环
                tickRing()
                    .stroke(NeoCyber.cyan.opacity(0.55), lineWidth: 1)
                    .frame(width: size - 8, height: size - 8)
                    .rotationEffect(spin)

                // 反向品红弧
                Circle()
                    .trim(from: 0, to: 0.22)
                    .stroke(
                        AngularGradient(colors: [NeoCyber.magenta, NeoCyber.magenta.opacity(0)],
                                        center: .center),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: size - 28, height: size - 28)
                    .rotationEffect(reverseSpin)
                    .shadow(color: NeoCyber.magenta.opacity(0.7), radius: 8)

                // 主进度弧
                if let p = progress {
                    Circle()
                        .trim(from: 0, to: max(0.02, CGFloat(p)))
                        .stroke(
                            AngularGradient(
                                colors: [NeoCyber.cyan, NeoCyber.lime, NeoCyber.cyan],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: size - 40, height: size - 40)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: NeoCyber.cyan.opacity(0.8), radius: 14)
                        .animation(.easeOut(duration: 0.35), value: p)
                } else {
                    // 不确定态：环绕弹珠
                    Circle()
                        .trim(from: 0, to: 0.35)
                        .stroke(
                            AngularGradient(
                                colors: [NeoCyber.cyan, NeoCyber.cyan.opacity(0)],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: size - 40, height: size - 40)
                        .rotationEffect(spin)
                        .shadow(color: NeoCyber.cyan.opacity(0.7), radius: 10)
                }

                // 粒子轨道
                ParticleOrbit(time: t, radius: (size - 40) / 2)
                    .frame(width: size, height: size)

                // 中心内容
                VStack(spacing: 4) {
                    if let p = progress {
                        Text("\(Int(p * 100))")
                            .font(.system(size: size * 0.26, weight: .black, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(colors: [NeoCyber.cyan, .white], startPoint: .top, endPoint: .bottom)
                            )
                            .monospacedDigit()
                            .shadow(color: NeoCyber.cyan.opacity(0.8), radius: 12)
                        Text("进 度")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .tracking(6)
                            .foregroundColor(NeoCyber.textMuted)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(NeoCyber.cyan)
                            .symbolEffect(.variableColor.iterative.reversing)
                        Text("解 析")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .tracking(8)
                            .foregroundColor(NeoCyber.cyan)
                    }
                }
                .scaleEffect(pulse)
            }
            .drawingGroup()
        }
    }

    private func tickRing() -> Path {
        Path { p in
            let center = CGPoint(x: size / 2, y: size / 2)
            let radius = (size - 8) / 2
            for i in 0..<60 {
                let angle = Double(i) / 60.0 * .pi * 2
                let inner = i % 5 == 0 ? radius - 8 : radius - 4
                let outer = radius
                let x1 = center.x + CGFloat(cos(angle)) * inner
                let y1 = center.y + CGFloat(sin(angle)) * inner
                let x2 = center.x + CGFloat(cos(angle)) * outer
                let y2 = center.y + CGFloat(sin(angle)) * outer
                p.move(to: CGPoint(x: x1, y: y1))
                p.addLine(to: CGPoint(x: x2, y: y2))
            }
        }
    }
}

private struct ParticleOrbit: View {
    var time: TimeInterval
    var radius: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let particleCount = 18
            for i in 0..<particleCount {
                let phase = Double(i) / Double(particleCount)
                let angle = (time * 0.8 + phase * .pi * 2)
                let wobble = sin(time * 2 + phase * 6) * 6
                let r = radius + wobble
                let x = center.x + CGFloat(cos(angle)) * r
                let y = center.y + CGFloat(sin(angle)) * r
                let alpha = 0.4 + 0.6 * (0.5 + 0.5 * sin(time * 3 + phase * 8))
                let dotSize: CGFloat = i % 3 == 0 ? 3 : 1.6
                let color = i % 2 == 0 ? NeoCyber.cyan : NeoCyber.magenta
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x - dotSize / 2, y: y - dotSize / 2,
                                           width: dotSize, height: dotSize)),
                    with: .color(color.opacity(alpha))
                )
            }
        }
    }
}

// MARK: - 数据流装饰（横向）

private struct DataStreamBar: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                Canvas { ctx, size in
                    let segments = 28
                    let segW = size.width / CGFloat(segments)
                    for i in 0..<segments {
                        let phase = Double(i) / Double(segments)
                        let h = 4 + abs(sin(t * 4 + phase * 8)) * 18
                        let rect = CGRect(
                            x: CGFloat(i) * segW + 1,
                            y: (size.height - h) / 2,
                            width: segW - 2,
                            height: h
                        )
                        let alpha = 0.4 + 0.6 * abs(sin(t * 3 + phase * 6))
                        let color = i % 4 == 0 ? NeoCyber.magenta : NeoCyber.cyan
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5),
                                 with: .color(color.opacity(alpha)))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .frame(height: 26)
    }
}

// MARK: - 主视图

struct DouyinDownloadView: View {
    @StateObject private var viewModel = DouyinDownloadViewModel()
    @State private var selectedImageIndex: Int = 0
    @State private var showFullscreenImage = false
    @State private var showCookieSettings = false
    @State private var inputFocusHalo: Bool = false
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
        .preferredColorScheme(.dark)
        .tint(NeoCyber.cyan)
        .onAppear {
            viewModel.autoPasteFromClipboardIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                viewModel.autoPasteFromClipboardIfNeeded()
            }
        }
    }

    // MARK: - iOS 布局

    private var phoneLayout: some View {
        NavigationStack {
            ZStack {
                NeoCyberBackground()

                ScrollView {
                    VStack(spacing: 22) {
                        heroBanner
                        platformBadges
                        inputSection
                        statusSection
                        if viewModel.showPreview, let videoInfo = viewModel.videoInfo {
                            videoPreviewSection(videoInfo)
                        }
                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(NeoCyber.lime)
                            .frame(width: 8, height: 8)
                            .shadow(color: NeoCyber.lime.opacity(0.9), radius: 6)
                        Text("灵 枢 · 壹")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .tracking(3)
                            .foregroundColor(NeoCyber.textPrimary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCookieSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(NeoCyber.cyan)
                            .padding(8)
                            .background(
                                Circle().fill(NeoCyber.cyan.opacity(0.12))
                            )
                            .overlay(
                                Circle().strokeBorder(NeoCyber.cyan.opacity(0.4), lineWidth: 1)
                            )
                    }
                }
            }
            .sheet(isPresented: $showCookieSettings) {
                CookieSettingsView()
            }
        }
    }

    // MARK: - Mac 布局

    private var macLayout: some View {
        ZStack {
            NeoCyberBackground()

            HStack(spacing: 0) {
                VStack(spacing: 24) {
                    HStack {
                        HStack(spacing: 8) {
                            Circle().fill(NeoCyber.lime).frame(width: 8, height: 8)
                                .shadow(color: NeoCyber.lime.opacity(0.9), radius: 6)
                            Text("灵 枢 · 壹")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .tracking(3)
                                .foregroundColor(NeoCyber.textPrimary)
                        }
                        Spacer()
                        Button {
                            showCookieSettings = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(NeoCyber.cyan)
                                .padding(8)
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showCookieSettings) {
                            CookieSettingsView()
                        }
                    }

                    heroBanner
                    platformBadges
                    inputSection
                    statusSection

                    Spacer()
                }
                .padding(28)
                .frame(minWidth: 360, idealWidth: 420, maxWidth: 480)

                Divider().background(NeoCyber.cyan.opacity(0.2))

                ZStack {
                    if viewModel.showPreview, let videoInfo = viewModel.videoInfo {
                        macPreviewSection(videoInfo)
                    } else {
                        emptyPreviewPlaceholder
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Hero Banner

    private var heroBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(NeoCyber.amber)
                Text("媒 体 · 解 析 · 引 擎")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundColor(NeoCyber.amber)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().stroke(NeoCyber.amber.opacity(0.6), lineWidth: 1)
            )

            Text("无 水 印\n下载控制台")
                .font(.system(size: isMac ? 34 : 38, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, NeoCyber.cyan, NeoCyber.magenta.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .lineSpacing(4)
                .tracking(2)
                .shadow(color: NeoCyber.cyan.opacity(0.4), radius: 12)

            Text("粘贴链接 · 自动解析 · 一键直取")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tracking(1)
                .foregroundColor(NeoCyber.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }

    // MARK: - 平台徽章带

    private var platformBadges: some View {
        let items: [(String, String, Color)] = [
            ("抖音", "play.fill", NeoCyber.cyan),
            ("TikTok", "globe", NeoCyber.magenta),
            ("INS", "camera.fill", NeoCyber.magenta),
            ("X", "xmark", .white),
            ("B站", "tv.fill", NeoCyber.cyan),
            ("快手", "bolt.fill", NeoCyber.amber),
            ("小红书", "heart.fill", NeoCyber.magenta)
        ]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 6) {
                        Image(systemName: item.1)
                            .font(.system(size: 9, weight: .bold))
                        Text(item.0)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(item.2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(item.2.opacity(0.10))
                    )
                    .overlay(
                        Capsule().strokeBorder(item.2.opacity(0.4), lineWidth: 0.8)
                    )
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - 输入区

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("链 接 · 入 口")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundColor(NeoCyber.cyan)
                Spacer()
                if !viewModel.inputText.isEmpty {
                    Button(action: viewModel.clearInput) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                            Text("清空")
                        }
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(NeoCyber.magenta)
                    }
                }
            }

            ZStack(alignment: .topLeading) {
                if viewModel.inputText.isEmpty {
                    Text("　在此粘贴分享链接 …")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(NeoCyber.textMuted.opacity(0.6))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $viewModel.inputText)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(NeoCyber.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: 84)
            }
            .background(NeoCyber.surface.opacity(0.55))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(NeoCyber.cyan.opacity(0.45), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 12) {
                Button(action: viewModel.pasteFromClipboard) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.clipboard.fill")
                        Text("粘 贴")
                            .tracking(4)
                    }
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundColor(NeoCyber.cyan)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(NeoCyber.cyan.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(NeoCyber.cyan.opacity(0.7), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button(action: viewModel.processInput) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.to.line")
                        Text("立 即 解 析")
                            .tracking(3)
                    }
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundColor(.black)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [NeoCyber.cyan, NeoCyber.lime.opacity(0.85)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                    )
                    .shadow(color: NeoCyber.cyan.opacity(0.7), radius: 14)
                    .opacity(viewModel.inputText.isEmpty || viewModel.isLoading ? 0.35 : 1.0)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.inputText.isEmpty || viewModel.isLoading)
            }
        }
        .padding(18)
        .holoPanel(glow: NeoCyber.cyan)
    }

    // MARK: - 状态区

    private var statusSection: some View {
        VStack(spacing: 14) {
            if let error = viewModel.errorMessage {
                errorView(error)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let result = viewModel.saveResult {
                successView(result)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if viewModel.isLoading {
                downloadingPanel
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.28), value: viewModel.isLoading)
        .animation(.easeOut(duration: 0.28), value: viewModel.errorMessage)
        .animation(.easeOut(duration: 0.28), value: viewModel.saveResult)
    }

    private var downloadingPanel: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                Circle().fill(NeoCyber.magenta)
                    .frame(width: 8, height: 8)
                    .shadow(color: NeoCyber.magenta, radius: 6)
                Text("信 号 传 输 中")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .tracking(4)
                    .foregroundColor(NeoCyber.textPrimary)
                Spacer()
                Text("实 时")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(2)
                    .foregroundColor(NeoCyber.magenta)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().stroke(NeoCyber.magenta.opacity(0.8), lineWidth: 1))
            }

            NeonProgressRing(progress: viewModel.downloadProgress,
                             size: isMac ? 180 : 220)
                .frame(maxWidth: .infinity)

            DataStreamBar()

            HStack(spacing: 16) {
                metric(label: "状 态",
                       value: viewModel.downloadProgress == nil ? "解 析" : "传 输",
                       color: NeoCyber.cyan)
                metric(label: "通 道", value: "主 线 一", color: NeoCyber.lime)
                metric(label: "编 码", value: "H · 264", color: NeoCyber.amber)
            }

            Button(action: viewModel.cancelDownload) {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill")
                    Text("中 止 任 务")
                        .tracking(4)
                }
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundColor(NeoCyber.magenta)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(NeoCyber.magenta.opacity(0.7), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .holoPanel(glow: NeoCyber.magenta)
    }

    private func metric(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(3)
                .foregroundColor(NeoCyber.textMuted)
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundColor(color)
                .shadow(color: color.opacity(0.7), radius: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(color.opacity(0.4), lineWidth: 0.8)
        )
    }

    // MARK: - 预览区

    private var emptyPreviewPlaceholder: some View {
        VStack(spacing: 16) {
            ZStack {
                ForEach(0..<3) { i in
                    Circle()
                        .strokeBorder(NeoCyber.cyan.opacity(0.2 - Double(i) * 0.05), lineWidth: 1)
                        .frame(width: 120 + CGFloat(i) * 40,
                               height: 120 + CGFloat(i) * 40)
                }
                Image(systemName: "play.rectangle.on.rectangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(colors: [NeoCyber.cyan, NeoCyber.magenta],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .shadow(color: NeoCyber.cyan.opacity(0.6), radius: 14)
            }
            Text("待 机 中")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .tracking(10)
                .foregroundColor(NeoCyber.textPrimary)
            Text("等 待 媒 体 载 入")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tracking(4)
                .foregroundColor(NeoCyber.textMuted)
        }
    }

    private func macPreviewSection(_ videoInfo: DouyinVideoInfo) -> some View {
        VStack(spacing: 16) {
            if let title = videoInfo.title {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundColor(NeoCyber.cyan)
                    Text(title)
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                        .foregroundColor(NeoCyber.textPrimary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }

            switch videoInfo.mediaType {
            case .video:
                if let localURL = videoInfo.localURL {
                    StableVideoPlayerView(url: localURL)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(NeoCyber.cyan.opacity(0.4), lineWidth: 1)
                        )
                        .padding(.horizontal, 24)
                    saveButton
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                }
            case .images:
                if !videoInfo.localImageURLs.isEmpty {
                    imageGalleryView(videoInfo.localImageURLs)
                        .padding(.horizontal, 24)
                    Text("共 \(videoInfo.localImageURLs.count) 张")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(3)
                        .foregroundColor(NeoCyber.textMuted)
                    saveButton
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                }
            }
        }
    }

    private func videoPreviewSection(_ videoInfo: DouyinVideoInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(NeoCyber.lime).frame(width: 8, height: 8)
                    .shadow(color: NeoCyber.lime, radius: 6)
                Text(videoInfo.mediaType == .video ? "视 频 · 载 荷" : "图 集 · 载 荷")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(4)
                    .foregroundColor(NeoCyber.lime)
            }

            if let title = videoInfo.title {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundColor(NeoCyber.textPrimary)
                    .lineLimit(3)
            }

            switch videoInfo.mediaType {
            case .video:
                if let localURL = videoInfo.localURL {
                    StableVideoPlayerView(url: localURL)
                        .frame(height: 280)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(NeoCyber.cyan.opacity(0.5), lineWidth: 1)
                        )
                    saveButton
                }
            case .images:
                if !videoInfo.localImageURLs.isEmpty {
                    Text("共 \(videoInfo.localImageURLs.count) 张")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(3)
                        .foregroundColor(NeoCyber.textMuted)
                    imageGalleryView(videoInfo.localImageURLs)
                        .frame(minHeight: 200)
                    saveButton
                }
            }
        }
        .padding(18)
        .holoPanel(glow: NeoCyber.lime)
    }

    // MARK: - 图片网格

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
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(NeoCyber.cyan.opacity(0.5), lineWidth: 1)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(NeoCyber.surface.opacity(0.5))
                            .aspectRatio(1, contentMode: .fill)
                            .overlay(ProgressView().tint(NeoCyber.cyan))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .fullScreenCover(isPresented: $showFullscreenImage) {
            FullscreenImageViewer(
                imageURLs: imageURLs,
                currentIndex: $selectedImageIndex
            )
        }
    }

    // MARK: - 保存按钮

    private var saveButton: some View {
        Button(action: {
            Task { await viewModel.saveMedia() }
        }) {
            #if targetEnvironment(macCatalyst)
            let saveLabel = "导 出 · 至 · 下 载"
            #else
            let saveLabel = "归 档 · 至 · 相 册"
            #endif
            HStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down.fill")
                Text(saveLabel)
                    .tracking(4)
            }
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [NeoCyber.lime, NeoCyber.cyan],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .cornerRadius(12)
            .shadow(color: NeoCyber.lime.opacity(0.5), radius: 12)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
    }

    // MARK: - 错误/成功

    private func errorView(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundColor(NeoCyber.magenta)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text("错 误 提 示")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundColor(NeoCyber.magenta)
                Text(message)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(NeoCyber.textPrimary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .holoPanel(glow: NeoCyber.magenta)
    }

    private func successView(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(NeoCyber.lime)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text("已 归 档")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(4)
                    .foregroundColor(NeoCyber.lime)
                Text(message)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(NeoCyber.textPrimary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .holoPanel(glow: NeoCyber.lime)
    }
}

#Preview {
    DouyinDownloadView()
}
