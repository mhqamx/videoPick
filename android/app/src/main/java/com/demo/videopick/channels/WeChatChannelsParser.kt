package com.demo.videopick.channels

import com.demo.videopick.data.model.VideoInfo
import kotlinx.serialization.json.*
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

open class ChannelsException(message: String) : Exception(message)
class ChannelsLoginRequired : ChannelsException("请登录元宝后继续下载视频号")
data class ChannelsReference(val token: String, val exportId: String)

object WeChatChannelsParser {
    private val json = Json { ignoreUnknownKeys = true }
    private fun obj(text: String): JsonObject = try {
        json.parseToJsonElement(text) as? JsonObject ?: throw IllegalArgumentException()
    } catch (_: Exception) { throw ChannelsException("视频号解析响应不完整，请稍后重试") }
    private fun JsonObject.string(key: String) = (get(key) as? JsonPrimitive)?.contentOrNull
    private fun JsonObject.number(key: String) = string(key)?.toIntOrNull()
    private fun JsonObject.child(key: String) = get(key) as? JsonObject
    private fun message(raw: String?) = raw.orEmpty().replace(Regex("<[^>]+>"), "").replace("&nbsp;", " ").trim().take(240)
    private fun loginMessage(text: String) = text.contains("登录") || text.contains("login", true) || text.contains("凭证过期")

    fun extract(text: String): String? = Regex("https?://[^\\s]+", RegexOption.IGNORE_CASE).findAll(text)
        .map { it.value.trimEnd { c -> c in ".,!?;:)]}>\"'，。！？；：）】》、" } }
        .firstOrNull { isChannelsHost(it) }

    fun isChannelsHost(raw: String): Boolean = raw.toHttpUrlOrNull()?.host in setOf("weixin.qq.com", "channels.weixin.qq.com")

    fun normalize(raw: String): String? {
        val url = raw.toHttpUrlOrNull() ?: return null
        if (url.username.isNotEmpty() || url.password.isNotEmpty() || url.port !in setOf(80, 443)) return null
        val id = when {
            url.host == "weixin.qq.com" && url.encodedPath.startsWith("/sph/") -> url.encodedPath.removePrefix("/sph/").removeSuffix("/")
            url.host == "channels.weixin.qq.com" && url.encodedPath == "/finder-preview/pages/sph" -> url.queryParameter("id")
            else -> null
        } ?: return null
        return if (id.length in 1..256 && id.matches(Regex("[A-Za-z0-9_-]+"))) "https://weixin.qq.com/sph/$id" else null
    }

    fun reference(text: String): ChannelsReference {
        val root = obj(text)
        val code = root.number("code") ?: throw ChannelsException("视频号解析响应不完整")
        if (code != 0) {
            val message = message(root.string("msg"))
            if (code in setOf(401, 403) || loginMessage(message)) throw ChannelsLoginRequired()
            throw ChannelsException(message.ifBlank { "元宝暂时无法解析此链接（$code）" })
        }
        val url = root.child("data")?.string("playable_url")?.toHttpUrlOrNull()
        if (url == null || url.scheme != "https" || url.port != 443 || url.host != "channels.weixin.qq.com" ||
            url.username.isNotEmpty() || url.password.isNotEmpty() || url.encodedPath != "/finder-preview/pages/feed") throw ChannelsException("视频号播放信息不完整")
        val token = url.queryParameter("token")?.takeIf { it.isNotBlank() } ?: throw ChannelsException("缺少视频号播放凭据")
        val eid = url.queryParameter("eid")?.takeIf { it.isNotBlank() } ?: throw ChannelsException("缺少视频号播放信息")
        return ChannelsReference(token, eid)
    }

    fun feed(text: String, id: String): VideoInfo {
        val root = obj(text)
        val code = root.number("errCode") ?: throw ChannelsException("视频号解析响应不完整")
        if (code != 0) {
            val message = message(root.string("errMsg"))
            if (code in setOf(401, 403) || loginMessage(message)) throw ChannelsLoginRequired()
            throw ChannelsException(message.ifBlank { "视频号解析失败（$code）" })
        }
        val data = root.child("data") ?: throw ChannelsException("视频号解析响应不完整")
        data.child("errMsg")?.let {
            val textMessage = listOf(message(it.string("title")), message(it.string("content"))).filter(String::isNotEmpty).joinToString("：")
            if ((it.number("type") ?: 0) != 0 || textMessage.isNotBlank()) {
                if (loginMessage(textMessage)) throw ChannelsLoginRequired()
                throw ChannelsException(textMessage.ifBlank { "此视频暂时无法播放" })
            }
        }
        val feed = data.child("feedInfo") ?: throw ChannelsException("此内容没有可下载的视频")
        if (feed.number("mediaType")?.let { it != 4 } == true) throw ChannelsException("暂不支持此内容类型，请使用普通视频分享链接")
        val sources = listOfNotNull(feed.child("h264VideoInfo"), feed.child("h265VideoInfo"), feed)
        if (sources.any { it.string("decodeKey")?.let { key -> key.isNotEmpty() && key != "0" } == true }) throw ChannelsException("暂不支持此视频的加密格式")
        val media = sources.firstNotNullOfOrNull { it.string("videoUrl")?.let(::mediaUrl) } ?: throw ChannelsException("此内容没有可下载的视频地址")
        return VideoInfo(id = "channels_$id", downloadUrl = media, title = feed.string("description"))
    }

    fun mediaUrl(raw: String): String? {
        val url = raw.toHttpUrlOrNull() ?: return null
        if (!url.host.endsWith(".video.qq.com") || url.username.isNotEmpty() || url.password.isNotEmpty() || url.port !in setOf(80, 443)) return null
        return url.newBuilder().scheme("https").port(443).build().toString()
    }

    fun isAuthenticated(text: String): Boolean = runCatching {
        val root = obj(text)
        root.number("status") == 2 && !root.string("userId").isNullOrBlank() &&
            (root.child("anonUser")?.get("isAnon") as? JsonPrimitive)?.booleanOrNull == false
    }.getOrDefault(false)

    fun validCookie(cookie: String) = cookie.isNotBlank() && cookie.none { it.code < 32 || it.code == 127 }
}
