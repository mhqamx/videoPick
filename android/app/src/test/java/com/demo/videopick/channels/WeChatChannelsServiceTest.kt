package com.demo.videopick.channels

import kotlinx.coroutines.runBlocking
import okhttp3.*
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test

class WeChatChannelsServiceTest {
    @Test fun `two request chain scopes account credentials to Yuanbao`() = runBlocking {
        val requests = mutableListOf<Request>()
        val client = WeChatChannelsService.newClient().newBuilder().addInterceptor { chain ->
            val request = chain.request(); requests += request
            val text = if (request.url.host == "yuanbao.tencent.com") {
                assertEquals("sid=sample", request.header("Cookie"))
                """{"code":0,"data":{"playable_url":"https://channels.weixin.qq.com/finder-preview/pages/feed?token=sample&eid=abc"}}"""
            } else {
                assertEquals("channels.weixin.qq.com", request.url.host)
                assertNull(request.header("Cookie"))
                """{"errCode":0,"data":{"feedInfo":{"mediaType":4,"videoUrl":"https://finder.video.qq.com/a"}}}"""
            }
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK").body(text.toResponseBody()).build()
        }.build()
        val service = WeChatChannelsService(client)
        try { service.resolve("https://weixin.qq.com/sph/a", ""); fail("missing login accepted") } catch (_: ChannelsLoginRequired) {}
        assertEquals(0, requests.size)
        assertEquals("channels_a", service.resolve("https://weixin.qq.com/sph/a", "sid=sample").id)
        assertEquals(2, requests.size)
        assertFalse(client.followRedirects)
        assertFalse(client.followSslRedirects)
    }
    @Test fun `authentication rejects anonymous accounts and unauthorized responses`() = runBlocking {
        for (code in listOf(200, 401, 403, 302)) {
            val client = WeChatChannelsService.newClient().newBuilder().addInterceptor {
                assertEquals("/api/getuserinfo", it.request().url.encodedPath)
                Response.Builder().request(it.request()).protocol(Protocol.HTTP_1_1).code(code).message("fixture")
                    .body("""{"status":2,"userId":"guest","anonUser":{"isAnon":true}}""".toResponseBody()).build()
            }.build()
            try { WeChatChannelsService(client).validateSession("sid=sample"); fail("invalid session accepted") }
            catch (_: ChannelsLoginRequired) {}
        }
    }
}
