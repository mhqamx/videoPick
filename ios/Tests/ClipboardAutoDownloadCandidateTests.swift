import Foundation

@main
struct ClipboardAutoDownloadCandidateTests {
    static func main() {
        let shareText = "复制这条分享 https://v.douyin.com/abc123/ 打开看看"
        let firstCandidate = ClipboardAutoDownloadCandidate.resolve(
            from: shareText,
            lastHandledFingerprint: nil
        )

        expect(firstCandidate?.text == shareText, "candidate should preserve original clipboard text")
        expect(firstCandidate?.fingerprint == "https://v.douyin.com/abc123/", "candidate should fingerprint the first URL")

        let duplicateCandidate = ClipboardAutoDownloadCandidate.resolve(
            from: shareText,
            lastHandledFingerprint: firstCandidate?.fingerprint
        )
        expect(duplicateCandidate == nil, "duplicate clipboard URL should be ignored")

        let plainTextCandidate = ClipboardAutoDownloadCandidate.resolve(
            from: "今天没有链接",
            lastHandledFingerprint: nil
        )
        expect(plainTextCandidate == nil, "plain text should not create a candidate")

        expect(
            ClipboardAutomationStartupPolicy.startsAutomatically,
            "clipboard radar should start automatically without a manual enable tap"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            Foundation.exit(1)
        }
    }
}
