import Foundation

@main
struct WeChatChannelsTests {
    static func main() throws {
        let short = URL(string: "https://weixin.qq.com/sph/ADKbu5wdF8")!
        expect(WeChatChannelsParser.normalizedShareURL(short) == short, "recognize short link")
        expect(WeChatChannelsParser.normalizedShareURL(URL(string: "https://channels.weixin.qq.com/finder-preview/pages/sph?id=ADKbu5wdF8&foo=1")!) == short, "normalize preview link")
        for text in ["https://weixin.qq.com.evil.test/sph/a", "https://weixin.qq.com/sph/", "https://weixin.qq.com/sph/a/b", "https://channels.weixin.qq.com/finder-preview/pages/sph?id=a%2Fb", "https://user:pass@weixin.qq.com/sph/a", "https://weixin.qq.com:444/sph/a", "https://channels.weixin.qq.com/platform"] {
            expect(WeChatChannelsParser.normalizedShareURL(URL(string:text)!) == nil, "reject invalid share URL")
        }
        let reference = try WeChatChannelsParser.parsePlayableReference(data(#"{"code":0,"data":{"playable_url":"https://channels.weixin.qq.com/finder-preview/pages/feed?token=sample-token&eid=export%2Fsample"}}"#))
        expect(reference.token == "sample-token" && reference.exportID == "export/sample", "decode playable reference")
        expectError(.loginRequired) { _ = try WeChatChannelsParser.parsePlayableReference(data(#"{"code":401,"msg":"请先登录"}"#)) }
        expectError(.invalidResponse) { _ = try WeChatChannelsParser.parsePlayableReference(data(#"{"code":0,"data":{"playable_url":"https://evil.test/?token=a&eid=b"}}"#)) }
        expectError(.invalidResponse) { _ = try WeChatChannelsParser.parsePlayableReference(data(#"{"code":0,"data":{"playable_url":"https://channels.weixin.qq.com/finder-preview/pages/feed?eid=b"}}"#)) }
        let feed = data(#"{"errCode":0,"data":{"errMsg":{"type":0},"feedInfo":{"mediaType":4,"description":"样例视频","h264VideoInfo":{"videoUrl":"http://finder.video.qq.com/a.mp4"},"h265VideoInfo":{"videoUrl":"https://finder.video.qq.com/b.mp4"},"videoUrl":"https://finder.video.qq.com/c.mp4"}}}"#)
        let media = try WeChatChannelsParser.parseFeed(feed, id: "ADKbu5wdF8")
        expect(media.videoURL.absoluteString == "https://finder.video.qq.com/a.mp4", "prefer H264 and HTTPS")
        expect(media.id == "ADKbu5wdF8" && media.title == "样例视频", "preserve title and safe short ID")
        expectError(.unavailable("此内容暂时无法播放")) { _ = try WeChatChannelsParser.parseFeed(data(#"{"errCode":0,"data":{"errMsg":{"type":2,"title":"此内容暂时无法播放"}}}"#), id:"a") }
        expectError(.noMedia) { _ = try WeChatChannelsParser.parseFeed(data(#"{"errCode":0,"data":{"feedInfo":{"mediaType":4}}}"#), id:"a") }
        expectError(.unsupportedMedia) { _ = try WeChatChannelsParser.parseFeed(data(#"{"errCode":0,"data":{"feedInfo":{"mediaType":2,"videoUrl":"https://finder.video.qq.com/a"}}}"#), id:"a") }
        expectError(.unsupportedMedia) { _ = try WeChatChannelsParser.parseFeed(data(#"{"errCode":0,"data":{"feedInfo":{"mediaType":4,"decodeKey":"123","videoUrl":"https://finder.video.qq.com/a"}}}"#), id:"a") }
        expectError(.noMedia) { _ = try WeChatChannelsParser.parseFeed(data(#"{"errCode":0,"data":{"feedInfo":{"mediaType":4,"videoUrl":"https://evil.test/a"}}}"#), id:"a") }
        let now = Date(timeIntervalSince1970: 1000)
        let cookies = [
            makeCookie("sid", "valid", ".tencent.com", expiry: 2000),
            makeCookie("local", "valid2", "yuanbao.tencent.com", expiry: 2000),
            makeCookie("old", "expired", ".tencent.com", expiry: 500),
            makeCookie("other", "secret", "other.tencent.com", expiry: 2000),
            makeCookie("fake", "secret", "tencent.com.evil.test", expiry: 2000),
            makeCookie("path", "secret", ".tencent.com", path: "/elsewhere", expiry: 2000)
        ]
        let header = WeChatChannelsParser.cookieHeader(cookies, now: now)
        expect(header.contains("sid=valid") && header.contains("local=valid2"), "include valid Yuanbao cookies")
        expect(!header.contains("secret") && !header.contains("expired"), "exclude expired, foreign and wrong-path cookies")
        expect(WeChatChannelsParser.isAuthenticatedUser(data(#"{"status":2,"userId":"user-sample","anonUser":{"isAnon":false}}"#)), "recognize authenticated account")
        expect(!WeChatChannelsParser.isAuthenticatedUser(data(#"{"status":2,"userId":"guest","anonUser":{"isAnon":true}}"#)), "anonymous account is not login")
        expect(!WeChatChannelsParser.isAuthenticatedUser(data(#"{"status":2}"#)), "missing user identity is not login")
        print("PASS: WeChat Channels parser and cookie boundaries")
    }
    static func data(_ text:String) -> Data { Data(text.utf8) }
    static func makeCookie(_ name:String,_ value:String,_ domain:String,path:String="/",expiry:Double)->HTTPCookie {
        HTTPCookie(properties:[.name:name,.value:value,.domain:domain,.path:path,.expires:Date(timeIntervalSince1970:expiry)])!
    }
    static func expect(_ condition: @autoclosure () -> Bool,_ message:String) {
        if !condition() { print("FAIL: \(message)"); exit(1) }
    }
    static func expectError(_ wanted:WeChatChannelsError,_ block:() throws->Void) {
        do { try block(); expect(false,"expected error \(wanted)") }
        catch { expect(error as? WeChatChannelsError == wanted,"expected \(wanted), got \(error)") }
    }
}
