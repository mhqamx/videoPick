package com.demo.videopick.data.repository

import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.coroutineContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Response

/** Each platform runs on the device; failure never selects a remote resolver. */
internal suspend fun <T> resolveLocally(platform: String, local: suspend () -> T): T {
    coroutineContext.ensureActive()
    try { return local() }
    catch (error: CancellationException) { throw error }
    catch (error: Exception) {
        throw IOException("${platform}本地解析失败: ${error.message ?: "未知错误"}", error)
    }
}

@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
internal suspend fun Call.awaitResponse(): Response = suspendCancellableCoroutine { continuation ->
    continuation.invokeOnCancellation { cancel() }
    enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) {
            if (continuation.isActive) continuation.resumeWithException(e)
        }
        override fun onResponse(call: Call, response: Response) {
            if (continuation.isActive) continuation.resume(response) { response.close() }
            else response.close()
        }
    })
}
