package com.demo.videopick.data.repository

import com.demo.videopick.data.model.MediaType
import org.junit.Assert.*
import org.junit.Test

class DouyinHtmlParserTest {
    private val parser = DouyinHtmlParser()
    private fun router(item: String) = "<script>window._ROUTER_DATA = {\"loaderData\":{\"video_(id)/page\":{\"videoInfoRes\":{\"item_list\":[$item]}}}};</script>"

    @Test fun `router video removes watermark without changing signed query values`() {
        val info = parser.parse(router("""{"aweme_id":"123","desc":"test","video":{"play_addr":{"url_list":["https://aweme.snssdk.com/aweme/v1/playwm/?video_id=v123&token=a%26b%3Dc%2Bd&watermark=1&logo_name=douyin"]}}}"""))
        assertEquals("123", info.id)
        assertEquals("https://aweme.snssdk.com/aweme/v1/play/?video_id=v123&token=a%26b%3Dc%2Bd", info.downloadUrl)
    }

    @Test fun `alternate playAddr schema resolves like iOS instead of reporting missing data`() {
        val info = parser.parse("""<script>window._SSR_HYDRATED_DATA = {"aweme_id":"456","video":{"playAddr":[{"src":"https://v.douyinvod.com/video/tos/clip?token=a%2Bb"}]}};</script>""")
        assertEquals("456", info.id)
        assertEquals("https://v.douyinvod.com/video/tos/clip?token=a%2Bb", info.downloadUrl)
    }

    @Test fun `empty router payload does not hide a usable hydration payload`() {
        val html = """<script>window._ROUTER_DATA = {"itemId":"123"};</script><script>window._SSR_HYDRATED_DATA = {"video":{"play_addr":{"url_list":["https://aweme.snssdk.com/aweme/v1/play/?video_id=abc"]}}};</script>"""
        assertEquals("https://aweme.snssdk.com/aweme/v1/play/?video_id=abc", parser.parse(html).downloadUrl)
    }

    @Test fun `javascript undefined normalization preserves text and media tokens`() {
        val info = parser.parse(router("""{"aweme_id":"123","desc":"undefined + test","extra":undefined,"video":{"play_addr":{"url_list":["https://v.douyinvod.com/undefined.mp4"]}}}"""))
        assertEquals("undefined + test", info.title)
        assertEquals("https://v.douyinvod.com/undefined.mp4", info.downloadUrl)
    }

    @Test fun `raw HTML fallback accepts unwatermarked play path`() {
        val info = parser.parse("""<video src="https://aweme.snssdk.com/aweme/v1/play/?video_id=123&amp;ratio=720p"></video>""")
        assertEquals("https://aweme.snssdk.com/aweme/v1/play/?video_id=123&ratio=720p", info.downloadUrl)
    }

    @Test fun `image posts retain images and never select their background music`() {
        val info = parser.parse(router("""{"aweme_id":"123","aweme_type":2,"images":[{"url_list":["https://p.douyinpic.com/a.webp","https://p.douyinpic.com/a.jpg"]},{"url_list":["https://p.douyinpic.com/b.jpg"]}],"music":{"play_url":{"url_list":["https://example.test/audio.mp3"]}}}"""))
        assertEquals(MediaType.IMAGES, info.mediaType)
        assertEquals(listOf("https://p.douyinpic.com/a.jpg", "https://p.douyinpic.com/b.jpg"), info.imageUrls)
    }

    @Test fun `ID only page reports missing media and never invents a playback URL`() {
        try {
            parser.parse("""<script>window._ROUTER_DATA = {"loaderData":{"video_(id)/page":{"itemId":"123"}}};</script>""")
            fail("Expected missing media")
        } catch (e: Exception) { assertTrue(e.message!!.contains("未下发")) }
    }

    @Test fun `RENDER_DATA percent decoding keeps literal plus characters`() {
        val html = """<script id='RENDER_DATA'>%7B%22aweme_id%22:%22123%22,%22desc%22:%22A+B%22,%22video%22:%7B%22play_addr%22:%7B%22url_list%22:%5B%22https://v.douyinvod.com/test.mp4?token=a+b%22%5D%7D%7D%7D</script>"""
        val info = parser.parse(html)
        assertEquals("A+B", info.title)
        assertEquals("https://v.douyinvod.com/test.mp4?token=a+b", info.downloadUrl)
    }

    @Test fun `malformed render encoding still permits raw video fallback`() {
        val html = """<script id="RENDER_DATA">%broken</script><video src="https://v.douyinvod.com/test.mp4"></video>"""
        assertEquals("https://v.douyinvod.com/test.mp4", parser.parse(html).downloadUrl)
    }

    @Test fun `structured playback wins over unrelated preview mp4 regardless of key order`() {
        val html = """<script>window._SSR_HYDRATED_DATA = {"preview":"https://example.test/preview.mp4","detail":{"play_addr":{"url_list":["https://aweme.snssdk.com/aweme/v1/play/?video_id=real"]}}};</script>"""
        assertEquals("https://aweme.snssdk.com/aweme/v1/play/?video_id=real", parser.parse(html).downloadUrl)
    }

    @Test fun `router preview cannot hide structured hydration media`() {
        val html = """<script>window._ROUTER_DATA = {"preview":"https://example.test/preview.mp4"};</script><script>window._SSR_HYDRATED_DATA = {"video":{"playAddr":[{"src":"https://v.douyinvod.com/video/tos/real"}]}};</script>"""
        assertEquals("https://v.douyinvod.com/video/tos/real", parser.parse(html).downloadUrl)
    }
}
