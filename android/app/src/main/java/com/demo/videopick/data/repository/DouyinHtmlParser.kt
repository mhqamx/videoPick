package com.demo.videopick.data.repository

import com.demo.videopick.data.model.MediaType
import com.demo.videopick.data.model.VideoInfo
import kotlinx.serialization.json.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/** Pure page parser shared by the Android resolution flow and its regression tests. */
internal class DouyinHtmlParser {
    private val json = Json { ignoreUnknownKeys = true }
    fun parse(html: String): VideoInfo {
        // A shell ROUTER_DATA object must not prevent trying other payloads.
        val payloads = mutableListOf<String>()
        for (name in listOf("window._ROUTER_DATA", "window._SSR_HYDRATED_DATA")) {
            extractJsonAssignment(html, name)?.let { payloads += it }
        }
        val renderPattern = Regex("""<script[^>]*id=["']RENDER_DATA["'][^>]*>(.*?)</script>""", RegexOption.DOT_MATCHES_ALL)
        for (match in renderPattern.findAll(html)) {
            // Percent decoding is not form decoding: literal '+' must survive.
            val decoded = runCatching {
                java.net.URLDecoder.decode(match.groupValues[1].trim().replace("+", "%2B"), "UTF-8")
            }.getOrNull() ?: continue
            payloads += decoded
        }
        // Search every payload for structured media before accepting a generic
        // video URL: ROUTER_DATA may contain only a preview while SSR has the work.
        for (allowRaw in listOf(false, true)) {
            for (payload in payloads) {
                parseVideoFromJson(payload, allowRaw)?.let { return it }
            }
        }

        // Fallback: 从 HTML 中直接提取播放链接
        parseFromRawHtml(html)?.let { return it }

        val itemId = extractDouyinItemId(html)
        if (!itemId.isNullOrBlank()) {
            throw Exception("分享页仅返回作品ID($itemId)，未下发视频播放数据")
        }
        throw Exception("未找到视频数据")
    }

    /** 从 HTML 中提取 `varName = {...}` 赋值语句中的 JSON 对象 */
    private fun extractJsonAssignment(html: String, varName: String): String? {
        val idx = html.indexOf(varName)
        if (idx == -1) return null

        // 找到 '=' 后的第一个 '{'
        val eqIdx = html.indexOf('=', idx + varName.length)
        if (eqIdx == -1) return null
        val braceStart = html.indexOf('{', eqIdx)
        if (braceStart == -1) return null

        // 用括号匹配找到完整 JSON 对象
        var depth = 0
        var inString = false
        var escape = false
        for (i in braceStart until html.length) {
            val c = html[i]
            if (escape) { escape = false; continue }
            if (c == '\\' && inString) { escape = true; continue }
            if (c == '"' && !escape) { inString = !inString; continue }
            if (inString) continue
            if (c == '{') depth++
            else if (c == '}') {
                depth--
                if (depth == 0) {
                    return html.substring(braceStart, i + 1)
                }
            }
        }
        return null
    }

    private fun parseVideoFromJson(jsonStr: String, allowRaw: Boolean): VideoInfo? {
        try {
            val sanitized = Regex(""""(?:\\.|[^"\\])*"|\bundefined\b""").replace(jsonStr) {
                if (it.value == "undefined") "null" else it.value
            }
            val root = json.parseToJsonElement(sanitized)

            // 策略1: loaderData -> videoInfoRes -> item_list (ROUTER_DATA 结构)
            val loaderData = (root as? JsonObject)?.get("loaderData") as? JsonObject
            if (loaderData != null) {
                for ((_, value) in loaderData) {
                    val data = value as? JsonObject ?: continue
                    val videoInfoRes = data["videoInfoRes"] as? JsonObject ?: continue
                    val itemList = videoInfoRes["item_list"] as? JsonArray ?: continue
                    val firstItem = itemList.firstOrNull() as? JsonObject ?: continue
                    // 图文作品优先检测
                    if (isDouyinImagePost(firstItem)) {
                        val info = buildImageInfoFromItem(firstItem)
                        if (info != null) return info
                    }
                    val info = buildVideoInfoFromItem(firstItem)
                    if (info != null) return info
                }
            }

            // 策略2: 先尝试图文
            val imagesDict = findFirstObject(root, "images")
            if (imagesDict != null && isDouyinImagePost(imagesDict)) {
                val info = buildImageInfoFromItem(imagesDict)
                if (info != null) return info
            }

            // 策略3: 递归查找包含 "video" 键的字典
            val awemeDict = findFirstObject(root, "video")
            if (awemeDict != null) {
                val info = buildVideoInfoFromItem(awemeDict)
                if (info != null) return info
            }

            // 策略4: 递归查找 play_addr.url_list
            val videoUrl = findBestVideoUrl(root, allowRaw = allowRaw)
            if (videoUrl != null) {
                val title = findFirstString(root, "desc")
                val videoId = findFirstString(root, "aweme_id") ?: "unknown_${System.currentTimeMillis()}"
                return VideoInfo(
                    id = videoId,
                    downloadUrl = normalizeDouyinVideoUrl(videoUrl),
                    title = title,
                )
            }

            return null
        } catch (_: Exception) {
            return null
        }
    }

    private fun extractDouyinItemId(html: String): String? {
        val patterns = listOf(
            Regex(""""itemId"\s*:\s*"(\d+)""""),
            Regex(""""aweme_id"\s*:\s*"(\d+)""""),
            Regex("""/(?:share/)?video/(\d+)"""),
        )
        for (pattern in patterns) {
            val match = pattern.find(html)
            val itemId = match?.groupValues?.getOrNull(1)
            if (!itemId.isNullOrBlank()) return itemId
        }
        return null
    }

    private fun isDouyinImagePost(item: JsonObject): Boolean {
        val awemeType = jsonPrimitiveContent(item["aweme_type"])
        if (awemeType == "2") return true
        val images = item["images"] as? JsonArray
        return images != null && images.isNotEmpty()
    }

    private fun buildImageInfoFromItem(item: JsonObject): VideoInfo? {
        val images = item["images"] as? JsonArray ?: return null
        if (images.isEmpty()) return null

        val imageUrls = mutableListOf<String>()
        for (imgElement in images) {
            val img = imgElement as? JsonObject ?: continue
            val urlList = img["url_list"] as? JsonArray ?: continue
            if (urlList.isEmpty()) continue
            // 优先选 jpeg/jpg，其次任意可用 URL
            var chosen: String? = null
            for (uElement in urlList) {
                val u = (uElement as? JsonPrimitive)?.content ?: continue
                if (u.isBlank()) continue
                if (chosen == null) chosen = u
                val lower = u.lowercase()
                if ("jpeg" in lower || "jpg" in lower) {
                    chosen = u
                    break
                }
            }
            if (!chosen.isNullOrBlank()) imageUrls.add(chosen)
        }

        if (imageUrls.isEmpty()) return null

        val awemeId = jsonPrimitiveContent(item["aweme_id"]) ?: "unknown_${System.currentTimeMillis()}"
        val title = jsonPrimitiveContent(item["desc"])



        return VideoInfo(
            id = awemeId,
            downloadUrl = imageUrls.first(),
            title = title,
            mediaType = MediaType.IMAGES,
            imageUrls = imageUrls,
        )
    }

    private fun buildVideoInfoFromItem(item: JsonObject): VideoInfo? {
        val video = item["video"] as? JsonObject ?: return null
        val playAddr = video["play_addr"] as? JsonObject ?: return null
        val urlList = playAddr["url_list"] as? JsonArray ?: return null
        val firstUrl = (urlList.firstOrNull() as? JsonPrimitive)?.content ?: return null

        val awemeId = (item["aweme_id"] as? JsonPrimitive)?.content
            ?: "unknown_${System.currentTimeMillis()}"
        val title = (item["desc"] as? JsonPrimitive)?.content

        return VideoInfo(
            id = awemeId,
            downloadUrl = normalizeDouyinVideoUrl(firstUrl),
            title = title,
        )
    }

    private fun findFirstObject(element: JsonElement, key: String, maxDepth: Int = 15): JsonObject? {
        if (maxDepth <= 0) return null
        when (element) {
            is JsonObject -> {
                if (element.containsKey(key)) return element
                for ((_, child) in element) {
                    val found = findFirstObject(child, key, maxDepth - 1)
                    if (found != null) return found
                }
            }
            is JsonArray -> {
                for (child in element) {
                    val found = findFirstObject(child, key, maxDepth - 1)
                    if (found != null) return found
                }
            }
            else -> {}
        }
        return null
    }

    private fun findFirstString(element: JsonElement, key: String, maxDepth: Int = 15): String? {
        if (maxDepth <= 0) return null
        when (element) {
            is JsonObject -> {
                val v = element[key]
                if (v is JsonPrimitive) return v.content
                for ((_, child) in element) {
                    val found = findFirstString(child, key, maxDepth - 1)
                    if (found != null) return found
                }
            }
            is JsonArray -> {
                for (child in element) {
                    val found = findFirstString(child, key, maxDepth - 1)
                    if (found != null) return found
                }
            }
            else -> {}
        }
        return null
    }

    private fun findBestVideoUrl(element: JsonElement, maxDepth: Int = 15, allowRaw: Boolean = false): String? {
        if (maxDepth <= 0) return null
        when (element) {
            is JsonObject -> {
                // CDN streams often have no .mp4 suffix. Only known media fields
                // may accept these URLs; arbitrary url_list can be covers/audio.
                for (key in listOf("play_addr", "playAddr", "play_addr_h264", "play_addr_265", "download_addr", "playUrl", "play_url")) {
                    element[key]?.let { firstMediaAddress(it, maxDepth - 1) }?.let { return it }
                }
                for ((key, child) in element) {
                    if (key in setOf("music", "cover", "origin_cover", "dynamic_cover", "images", "avatar_thumb")) continue
                    val found = findBestVideoUrl(child, maxDepth - 1, allowRaw)
                    if (found != null) return found
                }
            }
            is JsonArray -> {
                for (child in element) {
                    val found = findBestVideoUrl(child, maxDepth - 1, allowRaw)
                    if (found != null) return found
                }
            }
            is JsonPrimitive -> {
                val raw = element.content
                val url = raw.toHttpUrlOrNull()
                if (allowRaw && url != null && (url.encodedPath.contains("/aweme/v1/play") || url.encodedPath.endsWith(".mp4", true))) return raw
            }
            else -> {}
        }
        return null
    }

    private fun firstMediaAddress(element: JsonElement, depth: Int): String? {
        if (depth <= 0) return null
        return when (element) {
            is JsonPrimitive -> element.content.takeIf { it.toHttpUrlOrNull() != null }
            is JsonArray -> element.firstNotNullOfOrNull { firstMediaAddress(it, depth - 1) }
            is JsonObject -> listOf("url_list", "urlList", "src", "url").firstNotNullOfOrNull { key ->
                element[key]?.let { firstMediaAddress(it, depth - 1) }
            }
            else -> null
        }
    }

    private fun parseFromRawHtml(html: String): VideoInfo? {
        val decoded = html.replace("\\/", "/").replace("\\u0026", "&").replace("&amp;", "&")
        val patterns = listOf(
            Regex("""(https?://[^"'<>\s]+/aweme/v1/play(?:wm)?/[^"'<>\s]*)""", RegexOption.IGNORE_CASE),
            Regex("""(https?://[^"'<>\s]+\.mp4[^"'<>\s]*)""", RegexOption.IGNORE_CASE),
        )

        for (pattern in patterns) {
            val m = pattern.find(decoded)
            if (m != null) {
                val raw = m.groupValues[1].replace("\\/", "/")
                val normalized = normalizeDouyinVideoUrl(raw)
                return VideoInfo(
                    id = "unknown_${System.currentTimeMillis()}",
                    downloadUrl = normalized,
                )
            }
        }
        return null
    }

    private fun normalizeDouyinVideoUrl(raw: String): String {
        val url = raw.toHttpUrl()
        return url.newBuilder()
            .encodedPath(url.encodedPath.replace("/playwm/", "/play/"))
            .removeAllQueryParameters("watermark")
            .removeAllQueryParameters("logo_name")
            .build().toString()
    }

    private fun jsonPrimitiveContent(element: JsonElement?): String? = (element as? JsonPrimitive)?.content
}
