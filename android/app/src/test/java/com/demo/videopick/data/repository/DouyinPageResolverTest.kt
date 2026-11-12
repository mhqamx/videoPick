package com.demo.videopick.data.repository

import kotlinx.coroutines.runBlocking
import okhttp3.*
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test

class DouyinPageResolverTest {
    @Test fun `canonical empty page is not retried forever`() = runBlocking {
        var calls = 0
        val client = OkHttpClient.Builder().addInterceptor {
            calls++
            Response.Builder().request(it.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body("missing".toResponseBody()).build()
        }.build()
        try {
            try {
                DouyinPageResolver(client).resolve<String>("https://www.iesdouyin.com/share/video/123/?from_ssr=1") { error("no media") }
                fail("expected failure")
            } catch (e: IllegalStateException) { assertEquals("no media", e.message) }
            assertEquals(1, calls)
        } finally { client.dispatcher.executorService.shutdownNow() }
    }

    @Test fun `video shell retries canonical page without tracking flags`() = runBlocking {
        val requests = mutableListOf<Request>()
        val client = OkHttpClient.Builder().addInterceptor {
            val request = it.request(); requests += request
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body((if (requests.size == 1) "missing" else "video").toResponseBody()).build()
        }.build()
        try {
            val result = DouyinPageResolver(client).resolve("https://www.iesdouyin.com/share/video/7623018427791396490/?region=CN&share_token=example") {
                if (it == "missing") error("no payload") else it
            }
            assertEquals("video", result)
            assertEquals(listOf("https://www.iesdouyin.com/share/video/7623018427791396490/?region=CN&share_token=example", "https://www.iesdouyin.com/share/video/7623018427791396490/?from_ssr=1"), requests.map { it.url.toString() })
        } finally { client.dispatcher.executorService.shutdownNow() }
    }

    @Test fun `slides without payload retries mobile video page with query intact`() = runBlocking {
        val requests = mutableListOf<Request>()
        val client = OkHttpClient.Builder().addInterceptor {
            val request = it.request(); requests += request
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body((if (requests.size == 1) "missing" else "images").toResponseBody()).build()
        }.build()
        try {
            val result = DouyinPageResolver(client).resolve("https://www.iesdouyin.com/share/slides/123/?token=a%2Bb") {
                if (it == "missing") error("no payload") else it
            }
            assertEquals("images", result)
            assertEquals(2, requests.size)
            assertEquals("/share/video/123/", requests.last().url.encodedPath)
            assertEquals("token=a%2Bb", requests.last().url.encodedQuery)
            assertEquals("https://www.douyin.com/", requests.last().header("Referer"))
        } finally { client.dispatcher.executorService.shutdownNow() }
    }
}
