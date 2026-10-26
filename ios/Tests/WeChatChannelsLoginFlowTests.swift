// Standalone simulator test: compile with the real ViewModel and this service fixture.
import Foundation

actor DouyinDownloadService {
    static let shared = DouyinDownloadService()
    enum Mode { case loginRequired, success, delayed }
    var mode: Mode = .loginRequired
    var requests: [String] = []
    var saves = 0
    private var continuation: CheckedContinuation<DouyinVideoInfo, Never>?
    func configure(_ mode: Mode) { self.mode = mode }
    func reset() { requests = []; saves = 0; mode = .loginRequired }
    func parseAndDownload(_ text: String, progress: @Sendable (Double) -> Void) async throws -> DouyinVideoInfo {
        requests.append(text)
        switch mode {
        case .loginRequired: throw WeChatChannelsError.loginRequired
        case .success: return media()
        case .delayed: return await withCheckedContinuation { continuation = $0 }
        }
    }
    func release() { continuation?.resume(returning: media()); continuation = nil }
    func media() -> DouyinVideoInfo {
        DouyinVideoInfo(id: "sample", downloadURL: URL(string: "https://finder.video.qq.com/sample")!, localURL: URL(fileURLWithPath: "/tmp/sample.mp4"))
    }
    func saveVideo(videoURL: URL) async throws -> URL? { saves += 1; return nil }
    func saveImages(imageURLs: [URL]) async throws { saves += 1 }
}

@main struct WeChatChannelsLoginFlowTests {
    @MainActor static func main() async throws {
        let service = DouyinDownloadService.shared
        let model = DouyinDownloadViewModel()
        model.inputText = "original share"
        await model.downloadVideo()
        check(model.showYuanbaoLogin && !model.isLoading && model.errorMessage == nil, "missing session opens login")
        model.inputText = "edited during login"
        await service.configure(.success)
        model.yuanbaoLoginCompleted()
        try await wait { !model.isLoading }
        check(model.showPreview && !model.showYuanbaoLogin, "login resumes preview")
        check(await service.requests == ["original share", "original share"], "resume original link")

        await service.reset()
        model.clearInput()
        model.inputText = "cancelled login"
        await model.downloadVideo()
        model.yuanbaoLoginDismissed()
        model.yuanbaoLoginCompleted()
        check(await service.requests.count == 1, "dismissed login cannot resume")
        check(!model.showYuanbaoLogin && !model.showPreview, "dismiss leaves no success")

        await service.reset()
        await service.configure(.delayed)
        model.inputText = "cancelled download"
        model.processInput()
        try await wait { await service.requests.count == 1 }
        model.cancelDownload()
        await service.release()
        try await Task.sleep(for: .milliseconds(20))
        check(!model.showPreview && !model.showYuanbaoLogin && !model.isLoading, "late result after cancellation is ignored")

        await service.reset()
        model.inputText = "still unauthorized"
        await model.downloadVideo()
        model.yuanbaoLoginCompleted()
        try await wait { !model.isLoading }
        check(!model.showYuanbaoLogin && model.errorMessage != nil, "rejected authenticated retry cannot loop login")

        await service.reset()
        model.inputText = "automatic save"
        await model.downloadVideo(autoSaveAfterLogin: true)
        await service.configure(.success)
        model.yuanbaoLoginCompleted()
        try await wait { await service.saves == 1 }
        check(model.errorMessage == nil, "auto-save resumes after login")
        await service.reset()
        await service.configure(.success)
        model.clearInput()
        model.inputText = "double tap"
        model.processInput()
        model.processInput()
        try await Task.sleep(for: .milliseconds(30))
        check(await service.requests.count == 1, "rapid taps start only one download")
        print("PASS: login resume, original input, cancellation, retry limit and auto-save")
    }
    @MainActor static func wait(_ condition: () async -> Bool) async throws {
        for _ in 0..<1000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        check(false, "async operation timed out")
    }
    static func check(_ condition: Bool, _ message: String) {
        if !condition { print("FAIL: \(message)"); exit(1) }
    }
}
