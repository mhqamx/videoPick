import Foundation

final class ChannelsFixtureProtocol: URLProtocol, @unchecked Sendable {
    static var calls = 0
    static var failAuthentication = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.calls += 1
        let isYuanbao = request.url!.host == "yuanbao.tencent.com"
        let isUserInfo = request.url!.path == "/api/getuserinfo"
        check(request.httpMethod == (isUserInfo ? "GET" : "POST"), "correct API method")
        if isYuanbao {
            check(request.value(forHTTPHeaderField: "Cookie") == "sid=sample", "account cookie reaches Yuanbao")
        } else {
            check(request.url!.host == "channels.weixin.qq.com", "only Tencent feed endpoint")
            check(request.value(forHTTPHeaderField: "Cookie") == nil, "Yuanbao cookie must not reach feed API")
        }
        let text = isUserInfo ? #"{"status":2,"userId":"sample","anonUser":{"isAnon":false}}"# : isYuanbao
          ? #"{"code":0,"data":{"playable_url":"https://channels.weixin.qq.com/finder-preview/pages/feed?token=sample-token&eid=export%2Fsample"}}"#
          : #"{"errCode":0,"data":{"errMsg":{"type":0},"feedInfo":{"mediaType":4,"description":"样例","h264VideoInfo":{"videoUrl":"https://finder.video.qq.com/video.mp4"}}}}"#
        let response = HTTPURLResponse(url:request.url!,statusCode:Self.failAuthentication ? 401:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!
        client!.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client!.urlProtocol(self,didLoad:Data(text.utf8))
        client!.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    func check(_ ok: Bool,_ text:String) { if !ok { print("FAIL: \(text)"); exit(1) } }
}
@main struct WeChatChannelsServiceTests {
    static func main() async throws {
        let config=URLSessionConfiguration.ephemeral
        config.protocolClasses=[ChannelsFixtureProtocol.self]
        let session=URLSession(configuration:config)
        let service=WeChatChannelsService(session:session)
        let url=URL(string:"https://channels.weixin.qq.com/finder-preview/pages/sph?id=ADKbu5wdF8")!
        do { _ = try await service.resolve(url,cookie:""); fail("empty login accepted") }
        catch { check(error as? WeChatChannelsError == .loginRequired,"missing login classification") }
        check(ChannelsFixtureProtocol.calls==0,"empty login must not request network")
        let result=try await service.resolve(url,cookie:"sid=sample")
        check(result.videoURL.absoluteString=="https://finder.video.qq.com/video.mp4","two-step parse result")
        check(ChannelsFixtureProtocol.calls==2,"exactly two API requests")
        try await service.validateSession(cookie: "sid=sample")
        ChannelsFixtureProtocol.failAuthentication=true
        do { try await service.validateSession(cookie:"sid=sample"); fail("expired session validated") }
        catch { check(error as? WeChatChannelsError == .loginRequired,"validation rejects HTTP401") }
        do { _ = try await service.resolve(url,cookie:"sid=sample"); fail("expired login accepted") }
        catch { check(error as? WeChatChannelsError == .loginRequired,"HTTP401 prompts login") }
        print("PASS: WeChat Channels network credential boundaries")
    }
    static func check(_ ok:Bool,_ text:String) { if !ok { fail(text) } }
    static func fail(_ text:String)->Never { print("FAIL: \(text)"); exit(1) }
}
