package com.demo.videopick.data.repository

import java.io.File
import java.io.IOException
import java.nio.file.Files
import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import okio.BufferedSource
import okio.ForwardingSource
import okio.buffer
import org.junit.Assert.*
import org.junit.Test

class DownloadTransportTest {
    @Test fun `platform headers match iOS and cookies stay scoped`() {
        assertEquals("https://www.bilibili.com/", DownloadPolicy.headers("https://a.bilivideo.com/a")["Referer"])
        assertTrue(DownloadPolicy.headers("https://a.bilivideo.com/a")["User-Agent"]!!.contains("Macintosh"))
        assertEquals("https://www.xiaohongshu.com/", DownloadPolicy.headers("https://a.xhscdn.com/a")["Referer"])
        assertEquals("https://www.douyin.com/", DownloadPolicy.headers("https://a.douyinvod.com/a")["Referer"])
        val cookies = mapOf("instagram" to mapOf("sessionid" to "test"))
        assertEquals("sessionid=test", DownloadPolicy.headers("https://a.cdninstagram.com/a", cookies)["Cookie"])
        assertNull(DownloadPolicy.headers("https://cdninstagram.com.evil.test/a", cookies)["Cookie"])
    }

    @Test fun `fallback preserves signed percent escapes and proxy source`() {
        val url = "https://aweme.snssdk.com/play/?signature=a%2Bb%2Fc&line=0"
        assertEquals(listOf(url, url.replace("/play/", "/playwm/"),
            "https://aweme.snssdk.com/play/?signature=a%2Bb%2Fc",
            "https://aweme.snssdk.com/playwm/?signature=a%2Bb%2Fc"), DownloadPolicy.candidates(url))
        val proxy = "https://example.com/download?source=https%3A%2F%2Fcdn.example.com%2Fa%3Fsig%3Da%252Bb"
        assertEquals(listOf(proxy, "https://cdn.example.com/a?sig=a%2Bb"), DownloadPolicy.candidates(proxy))
        assertEquals("https://backend.example.com/download?source=https%3A%2F%2Fcdn.example.com%2Fa", DownloadPolicy.normalizeBackendUrl(
            "http://localhost:8000/download?source=https%3A%2F%2Fcdn.example.com%2Fa", "https://backend.example.com/resolve"))
    }

    @Test fun `truncated video resumes from actual bytes without duplication`() = runBlocking {
        val ranges = mutableListOf<String?>()
        withDownloader({ request ->
            ranges += request.header("Range")
            if (ranges.size == 1) response(request, "abc", declaredLength = 6)
            else response(request, "def", code = 206, range = "bytes 3-5/6")
        }) { downloader, directory ->
            val path = downloader.download("https://cdn.example.com/a", directory, "video.mp4") {}
            assertEquals("abcdef", File(path).readText())
            assertEquals(listOf("bytes=0-", "bytes=3-"), ranges)
        }
    }

    @Test fun `server ignoring range restarts instead of appending`() = runBlocking {
        var calls = 0
        withDownloader({ request ->
            if (calls++ == 0) response(request, "abc", declaredLength = 6)
            else response(request, "abcdef")
        }) { downloader, directory ->
            assertEquals("abcdef", File(downloader.download("https://cdn.example.com/a", directory, "video.mp4") {}).readText())
        }
    }

    @Test fun `real stream failure retains validator for safe resume`() = runBlocking {
        var calls = 0
        withDownloader({ request ->
            if (calls++ == 0) {
                val source = object : ForwardingSource(Buffer().writeUtf8("abc")) {
                    var delivered = false
                    override fun read(sink: Buffer, byteCount: Long): Long {
                        if (delivered) throw IOException("connection reset")
                        delivered = true
                        return super.read(sink, byteCount)
                    }
                }.buffer()
                val body = object : ResponseBody() {
                    override fun contentType() = null
                    override fun contentLength() = 6L
                    override fun source() = source
                }
                response(request, "").newBuilder().header("ETag", "\"version1\"").body(body).build()
            } else {
                assertEquals("\"version1\"", request.header("If-Range"))
                assertEquals("bytes=3-", request.header("Range"))
                response(request, "def", code = 206, range = "bytes 3-5/6")
            }
        }) { downloader, directory ->
            assertEquals("abcdef", File(downloader.download("https://cdn.example.com/a", directory, "video.mp4") {}).readText())
        }
    }

    @Test fun `wrong content range and repeated truncation never publish a partial file`() = runBlocking {
        for (badRange in listOf(false, true)) {
            var calls = 0
            withDownloader({ request ->
                if (calls++ == 0 || !badRange) response(request, "abc", declaredLength = 8)
                else response(request, "def", code = 206, range = "bytes 0-2/8")
            }) { downloader, directory ->
                try { downloader.download("https://cdn.example.com/a", directory, "video.mp4") {}; fail("partial accepted") }
                catch (_: IOException) {}
                assertTrue(directory.listFiles().isNullOrEmpty())
                assertTrue(calls <= 4)
            }
        }
    }

    @Test fun `image content type controls saved extension`() = runBlocking {
        withDownloader({ response(it, "image", type = "image/webp") }) { downloader, directory ->
            assertTrue(downloader.download("https://cdn.example.com/a", directory, "image.jpg") {}.endsWith(".webp"))
        }
    }

    @Test fun `cancelling a download removes temporary files`() = runBlocking {
        withDownloader({ response(it, "abcdef") }) { downloader, directory ->
            val job = launch(start = CoroutineStart.LAZY) {
                downloader.download("https://cdn.example.com/a", directory, "video.mp4") { throw CancellationException() }
            }
            job.start(); job.join()
            assertTrue(job.isCancelled)
            assertTrue(directory.listFiles().isNullOrEmpty())
        }
    }

    private fun response(request: Request, data: String, code: Int = 200, range: String? = null,
                         type: String = "video/mp4", declaredLength: Long = data.length.toLong()): Response {
        val body = object : ResponseBody() {
            private val buffer = Buffer().writeUtf8(data)
            override fun contentType() = null
            override fun contentLength() = declaredLength
            override fun source(): BufferedSource = buffer
        }
        return Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(code).message("fixture")
            .header("Content-Type", type).apply { range?.let { header("Content-Range", it) } }.body(body).build()
    }

    private suspend fun withDownloader(respond: (Request) -> Response, block: suspend (MediaDownloader, File) -> Unit) {
        val client = OkHttpClient.Builder().addInterceptor { respond(it.request()) }.build()
        val directory = Files.createTempDirectory("download-test").toFile()
        try { block(MediaDownloader(client), directory) }
        finally { directory.deleteRecursively(); client.dispatcher.executorService.shutdownNow(); client.connectionPool.evictAll() }
    }
}
