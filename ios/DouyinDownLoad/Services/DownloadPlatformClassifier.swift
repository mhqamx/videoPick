import Foundation

enum DownloadPlatformClassifier {
    static func isXiaohongshuURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("xiaohongshu.com")
            || host.contains("xhslink.com")
            || host.contains("xhslink.cn")
    }
}
