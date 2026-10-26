package com.demo.videopick.channels

import org.junit.Assert.*
import org.junit.Test

class WeChatChannelsParserTest {
    @Test fun `normalizes both supported share forms and rejects spoofed hosts`() {
        val short = "https://weixin.qq.com/sph/ADKbu5wdF8"
        assertEquals(short, WeChatChannelsParser.normalize(short))
        assertEquals(short, WeChatChannelsParser.normalize("https://channels.weixin.qq.com/finder-preview/pages/sph?id=ADKbu5wdF8"))
        listOf("https://weixin.qq.com.evil.test/sph/a", "https://weixin.qq.com/sph/", "https://weixin.qq.com/sph/a/b", "https://user:pass@weixin.qq.com/sph/a", "https://weixin.qq.com:444/sph/a").forEach { assertNull(WeChatChannelsParser.normalize(it)) }
    }
    @Test fun `extracts copied Chinese share text`() {
        assertEquals("https://weixin.qq.com/sph/abc", WeChatChannelsParser.extract("分享 https://weixin.qq.com/sph/abc。"))
    }
    @Test fun `requires a real authenticated account`() {
        assertTrue(WeChatChannelsParser.isAuthenticated("""{"status":2,"userId":"sample","anonUser":{"isAnon":false}}"""))
        assertFalse(WeChatChannelsParser.isAuthenticated("""{"status":2,"userId":"guest","anonUser":{"isAnon":true}}"""))
        assertFalse(WeChatChannelsParser.isAuthenticated("""{"status":2}"""))
    }
    @Test fun `parses reference and prefers H264`() {
        val reference = WeChatChannelsParser.reference("""{"code":0,"data":{"playable_url":"https://channels.weixin.qq.com/finder-preview/pages/feed?token=sample&eid=abc%2Fxyz"}}""")
        assertEquals("abc/xyz", reference.exportId)
        val media = WeChatChannelsParser.feed("""{"errCode":0,"data":{"feedInfo":{"mediaType":4,"description":"样例","h264VideoInfo":{"videoUrl":"http://finder.video.qq.com/a"},"videoUrl":"https://finder.video.qq.com/b"}}}""", "abc")
        assertEquals("https://finder.video.qq.com/a", media.downloadUrl)
        assertEquals("channels_abc", media.id)
    }
    @Test fun `rejects unsupported and encrypted media`() {
        listOf(
            """{"errCode":0,"data":{"feedInfo":{"mediaType":2}}}""",
            """{"errCode":0,"data":{"feedInfo":{"mediaType":4,"decodeKey":"123","videoUrl":"https://finder.video.qq.com/a"}}}""",
            """{"errCode":0,"data":{"feedInfo":{"mediaType":4,"videoUrl":"https://evil.test/a"}}}""",
            """{"errCode":0,"data":{"errMsg":{"type":2,"title":"不可播放"}}}"""
        ).forEach { assertThrows(ChannelsException::class.java) { WeChatChannelsParser.feed(it,"abc") } }
    }
    @Test fun `unauthorized responses request login and wrong token hosts are rejected`() {
        assertThrows(ChannelsLoginRequired::class.java) { WeChatChannelsParser.reference("""{"code":401}""") }
        assertThrows(ChannelsException::class.java) { WeChatChannelsParser.reference("""{"code":0,"data":{"playable_url":"https://evil.test/?token=a&eid=b"}}""") }
        assertFalse(WeChatChannelsParser.validCookie("sid=x\r\nHost: evil.test"))
    }
}
