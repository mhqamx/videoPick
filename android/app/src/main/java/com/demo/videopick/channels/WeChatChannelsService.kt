package com.demo.videopick.channels

import com.demo.videopick.data.model.VideoInfo
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class WeChatChannelsService(private val client: OkHttpClient = newClient()) {
    companion object {
        const val PARSE_URL = "https://yuanbao.tencent.com/api/weixin/get_parse_result"
        const val LOGIN_URL = "https://yuanbao.tencent.com/chat/naQivTmsDa"
        const val USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36"
        fun newClient() = OkHttpClient.Builder().cookieJar(CookieJar.NO_COOKIES)
            .followRedirects(false).followSslRedirects(false)
            .connectTimeout(30, TimeUnit.SECONDS).readTimeout(60, TimeUnit.SECONDS).build()
    }

    suspend fun validateSession(cookie: String) {
        requireCookie(cookie)
        val data = send(base("https://yuanbao.tencent.com/api/getuserinfo")
            .header("Cookie", cookie).header("Referer", LOGIN_URL).build())
        if (!WeChatChannelsParser.isAuthenticated(data)) throw ChannelsLoginRequired()
    }

    suspend fun resolve(raw: String, cookie: String): VideoInfo {
        requireCookie(cookie)
        val share = WeChatChannelsParser.normalize(raw) ?: throw ChannelsException("请使用视频号的普通视频分享链接")
        val reference = WeChatChannelsParser.reference(send(base(PARSE_URL)
            .header("Cookie", cookie).header("Origin", "https://yuanbao.tencent.com")
            .header("Referer", LOGIN_URL).header("X-Requested-With", "XMLHttpRequest")
            .post(body(buildJsonObject { put("type", "video_channel_url"); put("url", share); put("scene", 1) })).build()))
        val feedPage = "https://channels.weixin.qq.com/finder-preview/pages/feed".toHttpUrl().newBuilder()
            .addQueryParameter("token", reference.token).addQueryParameter("eid", reference.exportId)
            .addQueryParameter("appid", "0").addQueryParameter("entry_card_type", "48")
            .addQueryParameter("comment_scene", "39").addQueryParameter("entry_scene", "0").build()
        val endpoint = "https://channels.weixin.qq.com/finder-preview/api/feed/get_feed_info".toHttpUrl().newBuilder()
            .addQueryParameter("_rid", "${System.currentTimeMillis().toString(16)}-${UUID.randomUUID().toString().take(8)}")
            .addQueryParameter("_pageUrl", "https://channels.weixin.qq.com/finder-preview/pages/feed").build()
        return WeChatChannelsParser.feed(send(base(endpoint.toString())
            .header("Origin", "https://channels.weixin.qq.com").header("Referer", feedPage.toString())
            .post(body(buildJsonObject { putJsonObject("baseReq") { put("generalToken", reference.token) }; put("exportId", reference.exportId) })).build()), share.substringAfterLast('/'))
    }

    private fun requireCookie(cookie: String) { if (!WeChatChannelsParser.validCookie(cookie)) throw ChannelsLoginRequired() }
    private fun body(json: JsonObject) = json.toString().toRequestBody("application/json".toMediaType())
    private fun base(url: String) = Request.Builder().url(url).header("User-Agent", USER_AGENT)
        .header("Accept", "application/json, text/plain, */*").header("Accept-Language", "zh-CN,zh;q=0.9")

    private suspend fun send(request: Request): String = suspendCancellableCoroutine { continuation ->
        val call = client.newCall(request)
        continuation.invokeOnCancellation { call.cancel() }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) { if (continuation.isActive) continuation.resumeWithException(ChannelsException("网络请求失败，请检查网络后重试")) }
            override fun onResponse(call: Call, response: Response) {
                try {
                    val text = response.use {
                        if (it.code in setOf(401, 403) || it.code in 300..399) throw ChannelsLoginRequired()
                        if (!it.isSuccessful) throw ChannelsException("视频号服务暂时不可用（HTTP ${it.code}）")
                        it.body?.string() ?: throw ChannelsException("视频号响应为空")
                    }
                    if (continuation.isActive) continuation.resume(text)
                } catch (e: Exception) { if (continuation.isActive) continuation.resumeWithException(e) }
            }
        })
    }

    /** Unique temporary file plus cancellation prevents an old download overwriting a new one. */
    suspend fun download(url: String, directory: File, progress: (Float) -> Unit): String = suspendCancellableCoroutine { continuation ->
        val safe = WeChatChannelsParser.mediaUrl(url) ?: throw ChannelsException("视频地址无效")
        directory.mkdirs()
        val file = File.createTempFile("channels_", ".mp4", directory)
        val call = client.newCall(base(safe).header("Referer", "https://channels.weixin.qq.com/")
            .header("Accept", "*/*").build())
        continuation.invokeOnCancellation { call.cancel(); file.delete() }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                file.delete()
                if (continuation.isActive) continuation.resumeWithException(ChannelsException("视频下载失败，请重试"))
            }
            override fun onResponse(call: Call, response: Response) {
                try {
                    response.use {
                        if (!it.isSuccessful) throw ChannelsException("视频下载失败（HTTP ${it.code}）")
                        val body = it.body ?: throw ChannelsException("视频响应为空")
                        var count = 0L
                        val total = body.contentLength()
                        file.outputStream().use { output ->
                            body.byteStream().use { input ->
                                val buffer = ByteArray(65536)
                                while (continuation.isActive) {
                                    val read = input.read(buffer)
                                    if (read < 0) break
                                    output.write(buffer, 0, read); count += read
                                    if (total > 0) progress((count.toFloat() / total).coerceAtMost(1f))
                                }
                            }
                        }
                        if (count == 0L || total > 0 && count != total) throw ChannelsException("视频下载不完整，请重试")
                    }
                    if (continuation.isActive) { progress(1f); continuation.resume(file.absolutePath) }
                    else file.delete()
                } catch (e: Exception) {
                    file.delete()
                    if (continuation.isActive) continuation.resumeWithException(e)
                }
            }
        })
    }
}
