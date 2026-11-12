package com.demo.videopick.data.repository

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.coroutineContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import okhttp3.*

/** Stream to a unique file, retry up to four times, and publish only complete media. */
internal class MediaDownloader(private val client: OkHttpClient) {
    private class HttpFailure(code: Int) : IOException("下载失败: HTTP $code")
    private data class Transfer(val total: Long, val contentType: String?, val validator: String?)

    suspend fun download(url: String, directory: File, fileName: String,
                         cookies: Map<String, Map<String, String>> = emptyMap(), onProgress: (Float) -> Unit): String {
        directory.mkdirs()
        var lastError: IOException = IOException("下载失败")
        for (candidate in DownloadPolicy.candidates(url)) {
            coroutineContext.ensureActive()
            val prefix = fileName.substringBeforeLast('.').replace(Regex("[^A-Za-z0-9_-]"), "_").take(80).padEnd(3, '_')
            val file = File.createTempFile("${prefix}_", ".part", directory)
            var completed = false
            var total = -1L
            var validator: String? = null
            try {
                for (attempt in 0 until 4) {
                    coroutineContext.ensureActive()
                    try {
                        val result = transfer(candidate, file, cookies, total, validator, onProgress) { size, tag ->
                            total = size
                            validator = tag
                        }
                        total = result.total
                        validator = result.validator
                        if (file.length() == 0L || total > 0 && file.length() != total) {
                            throw IOException("视频下载不完整，请重试")
                        }
                        coroutineContext.ensureActive()
                        val ext = DownloadPolicy.extension(result.contentType, fileName.substringAfterLast('.', "mp4"))
                        val destination = File(directory, file.nameWithoutExtension + "." + ext)
                        onProgress(1f)
                        coroutineContext.ensureActive()
                        if (!file.renameTo(destination)) throw IOException("无法保存下载文件")
                        completed = true
                        return destination.absolutePath
                    } catch (e: CancellationException) { throw e }
                    catch (e: HttpFailure) { lastError = e; break }
                    catch (e: IOException) { lastError = e }
                }
            } finally { if (!completed) file.delete() }
        }
        throw lastError
    }

    private suspend fun transfer(url: String, file: File, cookies: Map<String, Map<String, String>>,
                                 knownTotal: Long, validator: String?, progress: (Float) -> Unit,
                                 onHeaders: (Long, String?) -> Unit): Transfer = suspendCancellableCoroutine { continuation ->
        val offset = file.length()
        val request = Request.Builder().url(url).apply {
            DownloadPolicy.headers(url, cookies).forEach { (key, value) -> header(key, value) }
            header("Range", "bytes=$offset-")
            if (offset > 0 && validator != null) header("If-Range", validator)
        }.build()
        val call = client.newCall(request)
        continuation.invokeOnCancellation { call.cancel() }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                if (continuation.isActive) continuation.resumeWithException(e)
            }
            override fun onResponse(call: Call, response: Response) {
                try {
                    val result = response.use {
                        if (!it.isSuccessful) throw HttpFailure(it.code)
                        val body = it.body ?: throw IOException("下载失败: 空响应")
                        val type = it.header("Content-Type")
                        if (type?.contains("text/html") == true || type?.contains("application/json") == true) throw IOException("下载地址返回了网页，请重新解析链接")
                        val append = it.code == 206
                        val responseValidator = it.header("ETag") ?: it.header("Last-Modified")
                        if (append && offset > 0 && validator != null && responseValidator != null && validator != responseValidator) {
                            throw IOException("下载内容已变化，请重新解析链接")
                        }
                        val range = it.header("Content-Range")?.let { value -> Regex("bytes (\\d+)-(\\d+)/(\\d+)").matchEntire(value) }
                        val total = if (append) {
                            val start = range?.groupValues?.get(1)?.toLongOrNull()
                            val end = range?.groupValues?.get(2)?.toLongOrNull()
                            val size = range?.groupValues?.get(3)?.toLongOrNull()
                            if (start != offset || end == null || size == null || end < start || end >= size || knownTotal > 0 && size != knownTotal) {
                                throw IOException("下载续传范围不匹配，请重新解析")
                            }
                            size
                        } else body.contentLength()
                        // Preserve metadata even if reading the body throws midway through.
                        onHeaders(total, responseValidator ?: if (append) validator else null)
                        var received = if (append) offset else 0L
                        FileOutputStream(file, append).use { output ->
                            body.byteStream().use { input ->
                                val buffer = ByteArray(65536)
                                while (true) {
                                    if (!continuation.isActive) throw CancellationException()
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    output.write(buffer, 0, count)
                                    received += count
                                    if (total > 0) progress((received.toFloat() / total).coerceIn(0f, 1f))
                                }
                            }
                        }
                        Transfer(total, type, responseValidator ?: if (append) validator else null)
                    }
                    if (continuation.isActive) continuation.resume(result)
                } catch (e: Exception) {
                    if (continuation.isActive) continuation.resumeWithException(e)
                } finally {
                    if (continuation.isCancelled) file.delete()
                }
            }
        })
    }
}
