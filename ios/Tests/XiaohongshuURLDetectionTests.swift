import Foundation

@main
struct XiaohongshuURLDetectionTests {
    static func main() {
        expect(
            DownloadPlatformClassifier.isXiaohongshuURL(URL(string: "http://xhslink.cn/o/AqqloiNRXIz")!),
            "xhslink.cn short links should be handled as Xiaohongshu"
        )

        expect(
            DownloadPlatformClassifier.isXiaohongshuURL(URL(string: "https://www.xiaohongshu.com/discovery/item/6a584d24000000000f0126ee")!),
            "xiaohongshu.com note links should be handled as Xiaohongshu"
        )

        expect(
            !DownloadPlatformClassifier.isXiaohongshuURL(URL(string: "https://v.douyin.com/abc123/")!),
            "non-Xiaohongshu links should not be classified as Xiaohongshu"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            Foundation.exit(1)
        }
    }
}
