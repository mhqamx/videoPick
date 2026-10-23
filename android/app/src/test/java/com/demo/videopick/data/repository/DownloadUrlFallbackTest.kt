package com.demo.videopick.data.repository

import org.junit.Assert.assertEquals
import org.junit.Test

class DownloadUrlFallbackTest {
    @Test
    fun `proxy download keeps the original url then the decoded source`() {
        val proxy = "https://example.lambda-url.on.aws/download?source=" +
            "https%3A%2F%2Fv16m.tiktokcdn.com%2Fvideo%2Fplay.mp4"

        assertEquals(
            listOf(
                proxy,
                "https://v16m.tiktokcdn.com/video/play.mp4",
            ),
            DownloadUrlFallback.candidates(proxy),
        )
    }

    @Test
    fun `douyin play url falls back to watermarked and line-stripped variants`() {
        val url = "https://aweme.snssdk.com/aweme/v1/play/?video_id=1&line=0"

        assertEquals(
            listOf(
                url,
                "https://aweme.snssdk.com/aweme/v1/playwm/?video_id=1&line=0",
                "https://aweme.snssdk.com/aweme/v1/play/?video_id=1",
                "https://aweme.snssdk.com/aweme/v1/playwm/?video_id=1",
            ),
            DownloadUrlFallback.candidates(url),
        )
    }
}
