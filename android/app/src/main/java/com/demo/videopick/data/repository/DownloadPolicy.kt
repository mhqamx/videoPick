package com.demo.videopick.data.repository

import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

internal object DownloadPolicy {
    private const val MOBILE_UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    private const val DESKTOP_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    fun headers(url: String, cookies: Map<String, Map<String, String>> = emptyMap()): Map<String, String> {
        val host = url.toHttpUrl().host
        fun matches(vararg domains: String) = domains.any { host == it || host.endsWith(".$it") }
        var ua = MOBILE_UA
        var cookiePlatform: String? = null
        val referer = when {
            matches("bilibili.com", "bilivideo.com", "bilivideo.cn", "akamaized.net") || host.startsWith("upos-") -> {
                ua = DESKTOP_UA; "https://www.bilibili.com/"
            }
            matches("instagram.com", "cdninstagram.com", "fbcdn.net") -> { cookiePlatform = "instagram"; "https://www.instagram.com/" }
            matches("x.com", "twitter.com", "twimg.com") -> { cookiePlatform = "x"; "https://x.com/" }
            matches("xhscdn.com", "xhscdn.net", "xiaohongshu.com") -> "https://www.xiaohongshu.com/"
            matches("kwimgs.com", "kwai.net", "kuaishou.com", "yximgs.com") -> "https://www.kuaishou.com/"
            else -> "https://www.douyin.com/"
        }
        return buildMap {
            put("User-Agent", ua); put("Referer", referer); put("Accept", "*/*")
            cookiePlatform?.let { cookies[it] }?.takeIf { it.isNotEmpty() }?.let {
                put("Cookie", it.entries.joinToString("; ") { (k, v) -> "$k=$v" })
            }
        }
    }

    fun candidates(raw: String): List<String> {
        val url = raw.toHttpUrl()
        val result = linkedSetOf(raw)
        if (url.encodedPath.endsWith("/download")) {
            url.queryParameter("source")?.toHttpUrlOrNull()?.let { result += it.toString() }
            return result.toList()
        }
        result += raw.replace("/play/", "/playwm/")
        val stripped = url.newBuilder().removeAllQueryParameters("line").build().toString()
        result += stripped
        result += stripped.replace("/play/", "/playwm/")
        return result.toList()
    }

    fun normalizeBackendUrl(raw: String, backend: String): String {
        val base = backend.toHttpUrl()
        val url = base.resolve(raw) ?: return raw
        return if (url.host in setOf("localhost", "127.0.0.1", "::1")) {
            url.newBuilder().scheme(base.scheme).host(base.host).port(base.port).build().toString()
        } else url.toString()
    }

    fun extension(contentType: String?, fallback: String): String = when (contentType?.substringBefore(';')?.trim()) {
        "image/webp" -> "webp"
        "image/png" -> "png"
        "image/jpeg" -> "jpg"
        "image/gif" -> "gif"
        else -> fallback
    }
}
