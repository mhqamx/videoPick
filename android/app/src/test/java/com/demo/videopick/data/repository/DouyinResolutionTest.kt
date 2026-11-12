package com.demo.videopick.data.repository

import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test

class DouyinResolutionTest {
    @Test fun `cancelling backend wait cancels the HTTP call`() = runBlocking {
        val entered = CompletableDeferred<Unit>()
        val release = java.util.concurrent.CountDownLatch(1)
        val client = okhttp3.OkHttpClient.Builder().addInterceptor {
            entered.complete(Unit)
            release.await(5, java.util.concurrent.TimeUnit.SECONDS)
            throw java.io.IOException("cancelled test request")
        }.build()
        val call = client.newCall(okhttp3.Request.Builder().url("https://example.test/resolve").build())
        try {
            val job = launch { call.awaitResponse().close() }
            withTimeout(2000) { entered.await() }
            job.cancelAndJoin()
            assertTrue(call.isCanceled())
        } finally { release.countDown(); client.dispatcher.executorService.shutdownNow() }
    }

    @Test fun `local failure is preserved without a remote retry`() = runBlocking {
        var calls = 0
        val original = java.io.IOException("分享页未下发媒体")
        try {
            resolveLocally<String>("抖音") { calls++; throw original }
            fail("expected error")
        } catch (error: Exception) {
            assertSame(original, error.cause)
            assertTrue(error.message!!.contains("分享页未下发媒体"))
            assertEquals(1, calls)
        }
    }
    @Test fun `local cancellation stays cancellation`() = runBlocking {
        val cancellation = CancellationException("cancel")
        try {
            resolveLocally<String>("抖音") { throw cancellation }
            fail("expected cancellation")
        } catch (error: CancellationException) { assertSame(cancellation, error) }
    }
}
