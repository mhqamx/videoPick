package com.demo.videopick.data.repository

import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.coroutineContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import okhttp3.*

/** The slides share page can omit its payload; iOS retries the video-shaped mobile page. */
internal class DouyinPageResolver(
    private val client: OkHttpClient,
    private val diagnostics: (String) -> Unit = {},
) {
    suspend fun <T> resolve(url: String, parse: (String) -> T): T {
        val page = fetch(url)
        coroutineContext.ensureActive()
        var failure: Exception
        try { return parse(page.second) }
        catch (error: CancellationException) { throw error }
        catch (error: Exception) { failure = error }
        val candidates = linkedSetOf<String>()
        // Keep the existing iOS-compatible slides retry, including signed query parameters.
        if (page.first.encodedPath.contains("/share/slides/")) {
            candidates += page.first.newBuilder()
                .encodedPath(page.first.encodedPath.replace("/share/slides/", "/share/video/")).build().toString()
        }
        // An app-opening shell can contain only an ID. Try the same public work once
        // without tracking flags, matching the backend's bounded canonical retry.
        val allowedHosts = setOf("www.iesdouyin.com", "iesdouyin.com", "www.douyin.com", "m.douyin.com", "douyin.com")
        val id = Regex("^/(?:share/)?(?:video|slides|note)/(\\d+)/?$")
            .matchEntire(page.first.encodedPath)?.groupValues?.get(1)
        if (page.first.host in allowedHosts && id != null) {
            candidates += "https://www.iesdouyin.com/share/video/$id/?from_ssr=1"
        }
        candidates.remove(page.first.toString())
        for (candidate in candidates) {
            coroutineContext.ensureActive()
            try {
                val retry = fetch(candidate)
                coroutineContext.ensureActive()
                return parse(retry.second)
            } catch (error: CancellationException) { throw error }
            catch (error: Exception) { failure = error }
        }
        throw failure
    }

    private suspend fun fetch(url: String): Pair<HttpUrl, String> = suspendCancellableCoroutine { continuation ->
        val request = Request.Builder().url(url).apply {
            DownloadPolicy.headers(url).forEach { (name, value) -> header(name, value) }
            header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
            header("Accept-Language", "zh-CN,zh-Hans;q=0.9")
        }.build()
        val call = client.newCall(request)
        continuation.invokeOnCancellation { call.cancel() }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                if (continuation.isActive) continuation.resumeWithException(e)
            }
            override fun onResponse(call: Call, response: Response) {
                try {
                    val page = response.use {
                        // Exclude query strings, cookies and media signatures from diagnostics.
                        diagnostics("local.douyin.page host=${it.request.url.host} path=${it.request.url.encodedPath} status=${it.code}")
                        if (!it.isSuccessful) throw IOException("请求失败: HTTP ${it.code}")
                        val html = it.body?.string() ?: throw IOException("空响应")
                        diagnostics("local.douyin.payload chars=${html.length} router=${html.contains("_ROUTER_DATA")} media=${html.contains("play_addr") || html.contains("playAddr") || html.contains("\"images\"")}")
                        it.request.url to html
                    }
                    if (continuation.isActive) continuation.resume(page)
                } catch (e: Exception) { if (continuation.isActive) continuation.resumeWithException(e) }
            }
        })
    }
}
