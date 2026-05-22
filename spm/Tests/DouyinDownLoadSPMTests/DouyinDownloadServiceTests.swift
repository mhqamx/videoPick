import XCTest
@testable import DouyinDownLoadSPM

final class DouyinDownloadServiceTests: XCTestCase {
    func testExtractURLReturnsFirstHTTPLink() async throws {
        let service = DouyinDownloadService.shared
        let url = try await service.extractURL(from: "文案 https://v.douyin.com/abcd1234/ 其他内容")

        XCTAssertEqual(url.absoluteString, "https://v.douyin.com/abcd1234/")
    }

    func testExtractURLThrowsWhenInputHasNoLink() async {
        let service = DouyinDownloadService.shared

        do {
            _ = try await service.extractURL(from: "这里只有纯文本")
            XCTFail("Expected invalidURL")
        } catch let error as DouyinDownloadError {
            XCTAssertEqual(error.errorDescription, DouyinDownloadError.invalidURL.errorDescription)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
