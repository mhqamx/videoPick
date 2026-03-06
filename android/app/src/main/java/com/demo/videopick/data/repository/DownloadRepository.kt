package com.demo.videopick.data.repository

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import com.demo.videopick.data.model.MediaType
import com.demo.videopick.data.model.ResolveRequest
import com.demo.videopick.data.model.ResolveResponse
import com.demo.videopick.data.model.VideoInfo
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.TimeUnit

class DownloadRepository(private val context: Context) {

    private val json = Json { ignoreUnknownKeys = true }

    private val resolveClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .followRedirects(true)
        .build()

    private val downloadClient = OkHttpClient.Builder()
        .connectTimeout(60, TimeUnit.SECONDS)
        .readTimeout(120, TimeUnit.SECONDS)
        .followRedirects(true)
        .build()

    private val douyinLocalClient = resolveClient.newBuilder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .callTimeout(20, TimeUnit.SECONDS)
        .followRedirects(true)
        .build()

    private val xiaohongshuLocalClient = resolveClient.newBuilder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .callTimeout(20, TimeUnit.SECONDS)
        .followRedirects(true)
        .build()

    private val instagramLocalClient = resolveClient.newBuilder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .callTimeout(25, TimeUnit.SECONDS)
        .followRedirects(true)
        .build()

    private val xLocalClient = resolveClient.newBuilder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .callTimeout(25, TimeUnit.SECONDS)
        .followRedirects(true)
        .build()

    private val kuaishouLocalClient = resolveClient.newBuilder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .callTimeout(20, TimeUnit.SECONDS)
        .followRedirects(true)
        .build()

    @Volatile
    private var xMetadataCache: Triple<String, String, Long>? = null

    companion object {
        private const val TAG = "DownloadRepository"
        private val BACKEND_URLS = listOf(
            "http://10.0.2.2:8000/resolve", // Android Emulator -> host localhost
            "http://192.168.1.100:8000/resolve",
            "https://super-halibut-r4r59wg9qw93pv6p-8000.app.github.dev/resolve",
        )
    }

    private val douyinUrlPattern = Regex(
        """https?://[^\s]*(?:douyin\.com|iesdouyin\.com)[^\s]*""", RegexOption.IGNORE_CASE
    )
    private val xiaohongshuShortPattern = Regex(
        """https?://xhslink\.com/(?:o/)?[a-zA-Z0-9_\-]+/?(?:\?[^\s]*)?""",
        RegexOption.IGNORE_CASE
    )
    private val xiaohongshuLongPattern = Regex(
        """https?://(?:www\.)?xiaohongshu\.com/(?:explore|discovery/item)/[a-zA-Z0-9_\-]+(?:\?[^\s]*)?""",
        RegexOption.IGNORE_CASE
    )
    private val instagramReelPattern = Regex(
        """https?://(?:www\.)?instagram\.com/reel/[A-Za-z0-9_-]+/?(?:\?[^\s]*)?""",
        RegexOption.IGNORE_CASE
    )
    private val instagramPostPattern = Regex(
        """https?://(?:www\.)?instagram\.com/p/[A-Za-z0-9_-]+/?(?:\?[^\s]*)?""",
        RegexOption.IGNORE_CASE
    )
    private val instagramTvPattern = Regex(
        """https?://(?:www\.)?instagram\.com/tv/[A-Za-z0-9_-]+/?(?:\?[^\s]*)?""",
        RegexOption.IGNORE_CASE
    )
    private val xStatusPattern = Regex(
        """https?://(?:www\.)?x\.com/[A-Za-z0-9_]+/status/\d+(?:\?[^\s]*)?""",
        RegexOption.IGNORE_CASE
    )
    private val twitterStatusPattern = Regex(
        """https?://(?:www\.)?twitter\.com/[A-Za-z0-9_]+/status/\d+(?:\?[^\s]*)?""",
        RegexOption.IGNORE_CASE
    )
    private val xMainJsPattern = Regex(
        """https://abs\.twimg\.com/responsive-web/client-web/main\.[^"']+\.js""",
        RegexOption.IGNORE_CASE
    )
    private val kuaishouShortPattern = Regex(
        """https?://v\.kuaishou\.com/[a-zA-Z0-9_\-]+/?""", RegexOption.IGNORE_CASE
    )
    private val kuaishouLongPattern = Regex(
        """https?://(?:www\.|m\.)?kuaishou\.com/(?:short-video|video)/[a-zA-Z0-9_\-]+""", RegexOption.IGNORE_CASE
    )
    private val genericUrlPattern = Regex("""https?://[^\s]+""", RegexOption.IGNORE_CASE)
    private val instagramDesktopUA = (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/537.36 (KHTML, like Gecko) " +
            "Chrome/124.0.0.0 Safari/537.36"
        )

    private fun cleanupExtractedUrl(raw: String): String {
        val suffix = ".,!?;:)]}>\"'，。！？；：）】》、"
        return raw.trim().trimEnd { it in suffix }
    }

    private fun extractDouyinUrl(text: String): String? =
        douyinUrlPattern.find(text)?.value?.let(::cleanupExtractedUrl)

    private fun extractXiaohongshuUrl(text: String): String? {
        for (pattern in listOf(xiaohongshuShortPattern, xiaohongshuLongPattern)) {
            val matched = pattern.find(text)?.value
            if (!matched.isNullOrBlank()) {
                return normalizeXiaohongshuInputUrl(cleanupExtractedUrl(matched))
            }
        }
        val candidate = genericUrlPattern.find(text)?.value?.let(::cleanupExtractedUrl)
        if (!candidate.isNullOrBlank()) {
            val lowered = candidate.lowercase()
            if ("xiaohongshu.com" in lowered || "xhslink.com" in lowered) {
                return normalizeXiaohongshuInputUrl(candidate)
            }
        }
        return null
    }

    private fun normalizeXiaohongshuInputUrl(url: String): String {
        val lower = url.lowercase()
        return if (lower.startsWith("http://xhslink.com/") || lower.startsWith("http://www.xiaohongshu.com/")) {
            "https://" + url.removePrefix("http://")
        } else {
            url
        }
    }

    private fun normalizeXiaohongshuMediaUrl(url: String): String =
        if (url.startsWith("http://")) "https://${url.removePrefix("http://")}" else url

    private fun extractInstagramUrl(text: String): String? {
        for (pattern in listOf(instagramReelPattern, instagramPostPattern, instagramTvPattern)) {
            val matched = pattern.find(text)?.value
            if (!matched.isNullOrBlank()) return normalizeInstagramInputUrl(cleanupExtractedUrl(matched))
        }
        val candidate = genericUrlPattern.find(text)?.value?.let(::cleanupExtractedUrl)
        if (!candidate.isNullOrBlank() && "instagram.com" in candidate.lowercase()) {
            return normalizeInstagramInputUrl(candidate)
        }
        return null
    }

    private fun normalizeInstagramInputUrl(url: String): String {
        val normalized = url.replace("http://", "https://")
        return try {
            val uri = java.net.URI(normalized)
            java.net.URI(uri.scheme, uri.authority, uri.path, null, null).toString()
        } catch (_: Exception) {
            normalized.substringBefore("?")
        }
    }

    private fun extractXUrl(text: String): String? {
        for (pattern in listOf(xStatusPattern, twitterStatusPattern)) {
            val matched = pattern.find(text)?.value
            if (!matched.isNullOrBlank()) return normalizeXInputUrl(cleanupExtractedUrl(matched))
        }
        val candidate = genericUrlPattern.find(text)?.value?.let(::cleanupExtractedUrl)
        if (!candidate.isNullOrBlank()) {
            val lowered = candidate.lowercase()
            if ("x.com/" in lowered || "twitter.com/" in lowered) {
                return normalizeXInputUrl(candidate)
            }
        }
        return null
    }

    private fun normalizeXInputUrl(url: String): String {
        val normalized = url.replace("http://", "https://")
        return try {
            val uri = java.net.URI(normalized)
            java.net.URI(uri.scheme, uri.authority, uri.path, uri.query, null).toString()
        } catch (_: Exception) {
            normalized
        }
    }

    private fun extractKuaishouUrl(text: String): String? {
        for (pattern in listOf(kuaishouShortPattern, kuaishouLongPattern)) {
            val matched = pattern.find(text)?.value
            if (!matched.isNullOrBlank()) return cleanupExtractedUrl(matched)
        }
        val candidate = genericUrlPattern.find(text)?.value?.let(::cleanupExtractedUrl)
        if (!candidate.isNullOrBlank()) {
            val lowered = candidate.lowercase()
            if ("kuaishou.com" in lowered) return candidate
        }
        return null
    }

    private fun logD(msg: String) = Log.d(TAG, msg)
    private fun logW(msg: String) = Log.w(TAG, msg)
    private fun logE(msg: String, t: Throwable? = null) = Log.e(TAG, msg, t)

    /**
     * Resolve then download media.
     * Douyin links: local HTML parse first -> fallback to backend.
     * Other links: backend first.
     */
    suspend fun parseAndDownload(
        text: String,
        onProgress: (Float) -> Unit = {},
    ): VideoInfo {
        logD("parse.start inputLength=${text.length}")
        val douyinUrl = extractDouyinUrl(text)
        val instagramUrl = extractInstagramUrl(text)
        val xUrl = extractXUrl(text)
        val xhsUrl = extractXiaohongshuUrl(text)
        val kuaishouUrl = extractKuaishouUrl(text)
        logD("parse.detect douyinUrl=${douyinUrl ?: "null"} instagramUrl=${instagramUrl ?: "null"} xUrl=${xUrl ?: "null"} xhsUrl=${xhsUrl ?: "null"} kuaishouUrl=${kuaishouUrl ?: "null"}")
        var resolvePath = "unknown"
        val videoInfo = when {
            douyinUrl != null -> {
                logD("parse.route platform=douyin strategy=local_first")
                try {
                    val info = resolveDouyinLocally(douyinUrl)
                    resolvePath = "local:douyin"
                    info
                } catch (localErr: Exception) {
                    logW("parse.fallback platform=douyin reason=${localErr.message}")
                    try {
                        val info = resolveViaBackend(text)
                        resolvePath = "backend_after_local_fail:douyin"
                        info
                    } catch (backendErr: Exception) {
                        logE("parse.fail both_local_and_backend platform=douyin", backendErr)
                        throw Exception(
                            "抖音本地解析失败: ${localErr.message ?: "未知错误"}；服务端解析失败: ${backendErr.message ?: "未知错误"}"
                        )
                    }
                }
            }
            instagramUrl != null -> {
                logD("parse.route platform=instagram strategy=local_only")
                try {
                    val info = resolveInstagramLocally(instagramUrl)
                    resolvePath = "local:instagram"
                    info
                } catch (localErr: Exception) {
                    logE("parse.fail local_only platform=instagram", localErr)
                    throw Exception("Instagram本地解析失败: ${localErr.message ?: "未知错误"}")
                }
            }
            xUrl != null -> {
                logD("parse.route platform=x strategy=local_only")
                try {
                    val info = resolveXLocally(xUrl)
                    resolvePath = "local:x"
                    info
                } catch (localErr: Exception) {
                    logE("parse.fail local_only platform=x", localErr)
                    throw Exception("X本地解析失败: ${localErr.message ?: "未知错误"}")
                }
            }
            xhsUrl != null -> {
                logD("parse.route platform=xiaohongshu strategy=local_first")
                try {
                    val info = resolveXiaohongshuLocally(xhsUrl)
                    resolvePath = "local:xiaohongshu"
                    info
                } catch (localErr: Exception) {
                    logW("parse.fallback platform=xiaohongshu reason=${localErr.message}")
                    try {
                        val info = resolveViaBackend(text)
                        resolvePath = "backend_after_local_fail:xiaohongshu"
                        info
                    } catch (backendErr: Exception) {
                        logE("parse.fail both_local_and_backend platform=xiaohongshu", backendErr)
                        throw Exception(
                            "小红书本地解析失败: ${localErr.message ?: "未知错误"}；服务端解析失败: ${backendErr.message ?: "未知错误"}"
                        )
                    }
                }
            }
            kuaishouUrl != null -> {
                logD("parse.route platform=kuaishou strategy=local_first")
                try {
                    val info = resolveKuaishouLocally(kuaishouUrl)
                    resolvePath = "local:kuaishou"
                    info
                } catch (localErr: Exception) {
                    logW("parse.fallback platform=kuaishou reason=${localErr.message}")
                    try {
                        val info = resolveViaBackend(text)
                        resolvePath = "backend_after_local_fail:kuaishou"
                        info
                    } catch (backendErr: Exception) {
                        logE("parse.fail both_local_and_backend platform=kuaishou", backendErr)
                        throw Exception(
                            "快手本地解析失败: ${localErr.message ?: "未知错误"}；服务端解析失败: ${backendErr.message ?: "未知错误"}"
                        )
                    }
                }
            }
            else -> {
                logD("parse.route platform=other strategy=backend")
                val info = resolveViaBackend(text)
                resolvePath = "backend:direct"
                info
            }
        }
        logD("parse.resolved path=$resolvePath id=${videoInfo.id} mediaType=${videoInfo.mediaType} downloadUrl=${videoInfo.downloadUrl}")

        return when (videoInfo.mediaType) {
            MediaType.VIDEO -> {
                val localPath = downloadFile(
                    url = videoInfo.downloadUrl,
                    fileName = "videopick_${videoInfo.id}.mp4",
                    onProgress = onProgress,
                )
                logD("parse.downloaded type=video path=$localPath")
                videoInfo.copy(localPath = localPath)
            }
            MediaType.IMAGES -> {
                logD("parse.download_images count=${videoInfo.imageUrls.size}")
                val localPaths = videoInfo.imageUrls.mapIndexedNotNull { index, url ->
                    try {
                        val path = downloadFile(
                            url = url,
                            fileName = "videopick_${videoInfo.id}_$index.jpg",
                            onProgress = { p ->
                                onProgress((index + p) / videoInfo.imageUrls.size)
                            },
                        )
                        logD("parse.download_images item[$index] success path=$path")
                        path
                    } catch (e: Exception) {
                        logW("parse.download_images item[$index] failed reason=${e.message}")
                        null
                    }
                }
                if (localPaths.isEmpty()) throw Exception("图片下载失败")
                logD("parse.download_images done successCount=${localPaths.size}")
                videoInfo.copy(localImagePaths = localPaths)
            }
        }
    }

    // ---------------------------------------------------------------
    // 抖音本地 HTML 解析（与 iOS 端逻辑一致）
    // ---------------------------------------------------------------

    private fun resolveDouyinLocally(url: String): VideoInfo {
        val start = System.currentTimeMillis()
        logD("local.douyin.start url=$url")

        val request = Request.Builder()
            .url(url)
            .header("User-Agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1")
            .header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
            .header("Accept-Language", "zh-CN,zh-Hans;q=0.9")
            .header("Referer", "https://www.douyin.com/")
            .build()

        douyinLocalClient.newCall(request).execute().use { response ->
            val finalUrl = response.request.url.toString()
            if (!response.isSuccessful) {
                throw Exception("请求失败: HTTP ${response.code}")
            }
            val html = response.body?.string() ?: throw Exception("空响应")
            val info = parseDouyinHtml(html)
            logD("local.douyin.success status=${response.code} finalUrl=$finalUrl htmlBytes=${html.length} id=${info.id} costMs=${System.currentTimeMillis() - start}")
            return info
        }
    }

    private fun parseDouyinHtml(html: String): VideoInfo {
        var jsonStr: String? = null

        // 尝试多种 JSON 数据变量名
        val varNames = listOf("window._ROUTER_DATA", "window._SSR_HYDRATED_DATA")
        for (varName in varNames) {
            jsonStr = extractJsonAssignment(html, varName)
            if (jsonStr != null) break
        }

        // RENDER_DATA (URL encoded)
        if (jsonStr == null) {
            val renderPattern = Regex("""<script[^>]*id="RENDER_DATA"[^>]*>(.*?)</script>""", RegexOption.DOT_MATCHES_ALL)
            val m = renderPattern.find(html)
            if (m != null) {
                jsonStr = java.net.URLDecoder.decode(m.groupValues[1].trim(), "UTF-8")
            }
        }

        if (jsonStr != null) {
            jsonStr = jsonStr.replace("undefined", "null")
            val info = parseVideoFromJson(jsonStr)
            if (info != null) return info
        }

        // Fallback: 从 HTML 中直接提取播放链接
        return parseFromRawHtml(html) ?: throw Exception("未找到视频数据")
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

    private fun parseVideoFromJson(jsonStr: String): VideoInfo? {
        try {
            val root = json.parseToJsonElement(jsonStr)

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
            val videoUrl = findBestVideoUrl(root)
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

        logD("local.douyin.image awemeId=$awemeId imageCount=${imageUrls.size}")

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

    private fun findBestVideoUrl(element: JsonElement, maxDepth: Int = 15): String? {
        if (maxDepth <= 0) return null
        when (element) {
            is JsonObject -> {
                val playAddr = element["play_addr"] as? JsonObject
                if (playAddr != null) {
                    val urlList = playAddr["url_list"] as? JsonArray
                    val url = (urlList?.firstOrNull() as? JsonPrimitive)?.content
                    if (url != null) return url
                }
                for ((_, child) in element) {
                    val found = findBestVideoUrl(child, maxDepth - 1)
                    if (found != null) return found
                }
            }
            is JsonArray -> {
                for (child in element) {
                    val found = findBestVideoUrl(child, maxDepth - 1)
                    if (found != null) return found
                }
            }
            else -> {}
        }
        return null
    }

    private fun parseFromRawHtml(html: String): VideoInfo? {
        val patterns = listOf(
            Regex("""(https?:\\/\\/[^"']+aweme\\/v1\\/playwm?\\/[^"']*)""", RegexOption.IGNORE_CASE),
            Regex("""(https?:\\/\\/[^"']+\.mp4[^"']*)""", RegexOption.IGNORE_CASE),
            Regex("""(https?://[^"']+aweme/v1/playwm?/[^"']*)""", RegexOption.IGNORE_CASE),
        )

        for (pattern in patterns) {
            val m = pattern.find(html)
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
        var url = raw.replace("playwm", "play")
        try {
            val uri = java.net.URI(url)
            val query = uri.query
            if (query != null) {
                val filteredParams = query.split("&")
                    .filter { !it.startsWith("watermark=") && !it.startsWith("logo_name=") }
                    .joinToString("&")
                url = java.net.URI(uri.scheme, uri.authority, uri.path, filteredParams.ifEmpty { null }, null).toString()
            }
        } catch (_: Exception) { }
        return url
    }

    // ---------------------------------------------------------------
    // Instagram 本地解析（不依赖 backend）
    // ---------------------------------------------------------------

    private data class InstagramResolveResult(
        val title: String? = null,
        val videoId: String? = null,
        val videoCandidates: List<String> = emptyList(),
        val imageUrls: List<String> = emptyList(),
        val webpageUrl: String? = null,
    )

    private fun resolveInstagramLocally(url: String): VideoInfo {
        val start = System.currentTimeMillis()
        val normalizedUrl = normalizeInstagramInputUrl(url)
        logD("local.instagram.start url=$normalizedUrl")

        val cookies = CookieStore.getCookies(context, "instagram")
        if (cookies.isEmpty()) {
            throw Exception("未配置 Instagram Cookie，请在设置中填写 sessionid")
        }
        if (cookies["sessionid"].isNullOrBlank()) {
            throw Exception("Instagram Cookie 缺少 sessionid")
        }

        val apiResolved = resolveInstagramViaPrivateApi(normalizedUrl, cookies)
        var title = apiResolved.title
        var videoId = apiResolved.videoId
        val videoCandidates = apiResolved.videoCandidates.toMutableList()
        val imageUrls = apiResolved.imageUrls.toMutableList()
        var webpageUrl = apiResolved.webpageUrl ?: normalizedUrl

        if (videoCandidates.isEmpty() && imageUrls.isEmpty()) {
            val pageResult = fetchInstagramWebpage(normalizedUrl, cookies)
            webpageUrl = pageResult.first
            val fallback = parseInstagramHtml(pageResult.second)
            if (title.isNullOrBlank()) title = fallback.title
            videoCandidates.addAll(fallback.videoCandidates)
        }

        if (videoCandidates.isEmpty() && imageUrls.isEmpty()) {
            throw Exception("未找到可下载媒体链接（cookie 可能失效）")
        }

        val resolvedId = videoId
            ?: extractInstagramShortcode(webpageUrl)
            ?: extractInstagramShortcode(normalizedUrl)
            ?: "ig_unknown_${System.currentTimeMillis()}"

        if (imageUrls.isNotEmpty() && videoCandidates.isEmpty()) {
            logD(
                "local.instagram.success media=image id=$resolvedId imageCount=${imageUrls.size} " +
                    "webpage=$webpageUrl costMs=${System.currentTimeMillis() - start}"
            )
            return VideoInfo(
                id = resolvedId,
                downloadUrl = imageUrls.first(),
                title = title,
                mediaType = MediaType.IMAGES,
                imageUrls = dedupe(imageUrls),
            )
        }

        logD(
            "local.instagram.success media=video id=$resolvedId videoCount=${videoCandidates.size} " +
                "webpage=$webpageUrl costMs=${System.currentTimeMillis() - start}"
        )
        return VideoInfo(
            id = resolvedId,
            downloadUrl = videoCandidates.first(),
            title = title,
            mediaType = MediaType.VIDEO,
        )
    }

    private fun resolveInstagramViaPrivateApi(
        normalizedUrl: String,
        cookies: Map<String, String>,
    ): InstagramResolveResult {
        val headers = buildInstagramHeaders(referer = normalizedUrl, cookies = cookies, jsonApi = true)

        val oembedUrl = "https://www.instagram.com/api/v1/oembed/?url=${
            java.net.URLEncoder.encode(normalizedUrl, "UTF-8")
        }"
        val oembedReq = Request.Builder()
            .url(oembedUrl)
            .headers(okhttp3.Headers.headersOf(*headers.flatMap { listOf(it.key, it.value) }.toTypedArray()))
            .build()

        val oembedPayload = try {
            instagramLocalClient.newCall(oembedReq).execute().use { response ->
                if (!response.isSuccessful) {
                    logW("local.instagram.api.oembed failed status=${response.code}")
                    return InstagramResolveResult()
                }
                val body = response.body?.string() ?: return InstagramResolveResult()
                json.parseToJsonElement(body) as? JsonObject
            }
        } catch (e: Exception) {
            logW("local.instagram.api.oembed exception=${e.message}")
            return InstagramResolveResult()
        } ?: return InstagramResolveResult()

        val fallbackTitle = jsonPrimitiveContent(oembedPayload["title"])
        val mediaId = jsonPrimitiveContent(oembedPayload["media_id"])
        if (mediaId.isNullOrBlank()) {
            return InstagramResolveResult(title = fallbackTitle)
        }

        val infoReq = Request.Builder()
            .url("https://www.instagram.com/api/v1/media/$mediaId/info/")
            .headers(okhttp3.Headers.headersOf(*headers.flatMap { listOf(it.key, it.value) }.toTypedArray()))
            .build()

        val infoPayload = try {
            instagramLocalClient.newCall(infoReq).execute().use { response ->
                if (!response.isSuccessful) {
                    logW("local.instagram.api.mediaInfo failed status=${response.code}")
                    return InstagramResolveResult(title = fallbackTitle, videoId = mediaId)
                }
                val body = response.body?.string() ?: return InstagramResolveResult(title = fallbackTitle, videoId = mediaId)
                json.parseToJsonElement(body) as? JsonObject
            }
        } catch (e: Exception) {
            logW("local.instagram.api.mediaInfo exception=${e.message}")
            return InstagramResolveResult(title = fallbackTitle, videoId = mediaId)
        } ?: return InstagramResolveResult(title = fallbackTitle, videoId = mediaId)

        val parsed = extractInstagramFromMediaInfo(infoPayload, fallbackTitle)
        return parsed.copy(videoId = parsed.videoId ?: mediaId)
    }

    private fun extractInstagramFromMediaInfo(
        payload: JsonObject,
        fallbackTitle: String?,
    ): InstagramResolveResult {
        val items = payload["items"] as? JsonArray ?: return InstagramResolveResult(title = fallbackTitle)
        val item = items.firstOrNull() as? JsonObject ?: return InstagramResolveResult(title = fallbackTitle)

        val videoId = jsonPrimitiveContent(item["id"]) ?: jsonPrimitiveContent(item["pk"])
        val mediaType = jsonPrimitiveContent(item["media_type"])
        val code = jsonPrimitiveContent(item["code"])
        val webpageUrl = if (!code.isNullOrBlank()) {
            "https://www.instagram.com/${if (mediaType == "2") "reel" else "p"}/$code/"
        } else {
            null
        }

        var title = fallbackTitle
        val caption = item["caption"] as? JsonObject
        val captionText = jsonPrimitiveContent(caption?.get("text"))
        if (!captionText.isNullOrBlank()) title = captionText

        val videoCandidates = mutableListOf<String>()
        val imageUrls = mutableListOf<String>()
        val carousel = item["carousel_media"] as? JsonArray
        if (carousel != null && carousel.isNotEmpty()) {
            for (mediaItem in carousel) {
                val mediaObj = mediaItem as? JsonObject ?: continue
                videoCandidates.addAll(extractInstagramVideoVersions(mediaObj["video_versions"]))
                imageUrls.addAll(extractInstagramImageVersions(mediaObj["image_versions2"]))
            }
        } else {
            videoCandidates.addAll(extractInstagramVideoVersions(item["video_versions"]))
            imageUrls.addAll(extractInstagramImageVersions(item["image_versions2"]))
        }

        return InstagramResolveResult(
            title = title,
            videoId = videoId,
            videoCandidates = dedupe(videoCandidates),
            imageUrls = dedupe(imageUrls),
            webpageUrl = webpageUrl,
        )
    }

    private fun extractInstagramVideoVersions(videoVersions: JsonElement?): List<String> {
        val array = videoVersions as? JsonArray ?: return emptyList()
        val candidates = mutableListOf<String>()
        for (item in array) {
            val obj = item as? JsonObject ?: continue
            val raw = jsonPrimitiveContent(obj["url"]) ?: continue
            val normalized = normalizeInstagramVideoCandidate(raw) ?: continue
            candidates.add(normalized)
        }
        return dedupe(candidates)
    }

    private fun extractInstagramImageVersions(imageVersions2: JsonElement?): List<String> {
        val root = imageVersions2 as? JsonObject ?: return emptyList()
        val candidates = root["candidates"] as? JsonArray ?: return emptyList()

        var bestUrl: String? = null
        var bestArea = -1L
        for (item in candidates) {
            val obj = item as? JsonObject ?: continue
            val raw = jsonPrimitiveContent(obj["url"]) ?: continue
            val normalized = normalizeInstagramImageCandidate(raw) ?: continue
            val width = jsonPrimitiveContent(obj["width"])?.toLongOrNull() ?: 0L
            val height = jsonPrimitiveContent(obj["height"])?.toLongOrNull() ?: 0L
            val area = width * height
            if (area > bestArea || bestUrl == null) {
                bestArea = area
                bestUrl = normalized
            }
        }
        return if (bestUrl != null) listOf(bestUrl) else emptyList()
    }

    private fun fetchInstagramWebpage(
        url: String,
        cookies: Map<String, String>,
    ): Pair<String, String> {
        val request = Request.Builder()
            .url(url)
            .headers(okhttp3.Headers.headersOf(*buildInstagramHeaders(url, cookies, jsonApi = false).flatMap { listOf(it.key, it.value) }.toTypedArray()))
            .build()
        instagramLocalClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw Exception("Instagram 网页请求失败: HTTP ${response.code}")
            val html = response.body?.string() ?: throw Exception("Instagram 网页响应为空")
            val finalUrl = response.request.url.toString()
            logD("local.instagram.webpage status=${response.code} finalUrl=$finalUrl htmlBytes=${html.length}")
            return finalUrl to html
        }
    }

    private fun parseInstagramHtml(html: String): InstagramResolveResult {
        val videoCandidates = mutableListOf<String>()
        val patterns = listOf(
            Regex(""""video_url":"(https:[^"]+)"""", RegexOption.IGNORE_CASE),
            Regex(""""contentUrl":"(https:[^"]+)"""", RegexOption.IGNORE_CASE),
            Regex(""""url":"(https:[^"]+\\.mp4[^"]*)"""", RegexOption.IGNORE_CASE),
        )
        for (pattern in patterns) {
            for (m in pattern.findAll(html)) {
                val raw = m.groupValues.getOrNull(1) ?: continue
                val normalized = normalizeInstagramVideoCandidate(raw)
                if (!normalized.isNullOrBlank()) videoCandidates.add(normalized)
            }
        }

        val videoBlockPattern = Regex(""""video_versions":\[(.*?)\]""", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
        val urlInBlockPattern = Regex(""""url":"(https:[^"]+)"""", RegexOption.IGNORE_CASE)
        for (blockMatch in videoBlockPattern.findAll(html)) {
            val block = blockMatch.groupValues.getOrNull(1) ?: continue
            for (urlMatch in urlInBlockPattern.findAll(block)) {
                val raw = urlMatch.groupValues.getOrNull(1) ?: continue
                val normalized = normalizeInstagramVideoCandidate(raw)
                if (!normalized.isNullOrBlank()) videoCandidates.add(normalized)
            }
        }

        return InstagramResolveResult(
            title = extractInstagramOgTitle(html),
            videoCandidates = dedupe(videoCandidates),
        )
    }

    private fun extractInstagramOgTitle(html: String): String? {
        val m = Regex(
            """<meta[^>]+property="og:title"[^>]+content="([^"]+)"""",
            RegexOption.IGNORE_CASE
        ).find(html) ?: return null
        return decodeUrlEscapes(m.groupValues[1]).ifBlank { null }
    }

    private fun extractInstagramShortcode(url: String): String? =
        Regex("""/(?:reel|p|tv)/([A-Za-z0-9_-]+)""", RegexOption.IGNORE_CASE)
            .find(url)
            ?.groupValues
            ?.getOrNull(1)

    private fun buildInstagramHeaders(
        referer: String,
        cookies: Map<String, String>,
        jsonApi: Boolean,
    ): Map<String, String> {
        val headers = linkedMapOf(
            "User-Agent" to instagramDesktopUA,
            "Accept-Language" to "en-US,en;q=0.9,zh-CN;q=0.8",
            "Referer" to referer,
            "Origin" to "https://www.instagram.com",
            "Cookie" to buildCookieHeader(cookies),
        )
        if (jsonApi) {
            headers["Accept"] = "application/json, text/plain, */*"
            headers["X-IG-App-ID"] = "936619743392459"
            headers["X-Requested-With"] = "XMLHttpRequest"
        } else {
            headers["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        }
        return headers
    }

    private fun buildCookieHeader(cookies: Map<String, String>): String =
        cookies.entries.joinToString("; ") { "${it.key}=${it.value}" }

    private fun normalizeInstagramVideoCandidate(value: String): String? {
        val url = decodeUrlEscapes(value)
        if (!url.startsWith("http")) return null
        val host = try {
            java.net.URI(url).host?.lowercase()
        } catch (_: Exception) {
            null
        } ?: return null

        val hostAllowed = host == "instagram.com" || host.endsWith(".instagram.com") ||
            host == "cdninstagram.com" || host.endsWith(".cdninstagram.com") ||
            host == "fbcdn.net" || host.endsWith(".fbcdn.net")
        if (!hostAllowed) return null

        val lower = url.lowercase()
        if (".mp4" in lower || "bytestart" in lower || "video" in lower) return url
        return null
    }

    private fun normalizeInstagramImageCandidate(value: String): String? {
        val url = decodeUrlEscapes(value)
        if (!url.startsWith("http")) return null
        val host = try {
            java.net.URI(url).host?.lowercase()
        } catch (_: Exception) {
            null
        } ?: return null
        val hostAllowed = host == "instagram.com" || host.endsWith(".instagram.com") ||
            host == "cdninstagram.com" || host.endsWith(".cdninstagram.com") ||
            host == "fbcdn.net" || host.endsWith(".fbcdn.net")
        return if (hostAllowed) url else null
    }

    private fun decodeUrlEscapes(value: String): String = value
        .replace("\\u002F", "/")
        .replace("\\u0026", "&")
        .replace("\\/", "/")
        .replace("&amp;", "&")

    // ---------------------------------------------------------------
    // X 本地解析（不依赖 backend）
    // ---------------------------------------------------------------

    private fun resolveXLocally(url: String): VideoInfo {
        val start = System.currentTimeMillis()
        val normalizedUrl = normalizeXInputUrl(url)
        logD("local.x.start url=$normalizedUrl")

        val cookies = CookieStore.getCookies(context, "x")
        if (cookies.isEmpty()) throw Exception("未配置 X Cookie，请在设置中填写 auth_token 和 ct0")
        if (cookies["auth_token"].isNullOrBlank()) throw Exception("X Cookie 缺少 auth_token")
        if (cookies["ct0"].isNullOrBlank()) throw Exception("X Cookie 缺少 ct0")

        val tweetId = extractXTweetId(normalizedUrl) ?: throw Exception("无法从链接中提取 tweet id")
        val (queryId, bearer) = loadXGraphqlMetadata(tweetId, cookies)
        val result = resolveXMedia(tweetId, queryId, bearer, cookies)

        // 视频推文
        if (result.videoCandidates.isNotEmpty()) {
            logD("local.x.success media=video id=$tweetId candidateCount=${result.videoCandidates.size} costMs=${System.currentTimeMillis() - start}")
            return VideoInfo(
                id = tweetId,
                downloadUrl = result.videoCandidates.first(),
                title = result.title,
                mediaType = MediaType.VIDEO,
            )
        }

        // 图片推文
        if (result.imageUrls.isNotEmpty()) {
            logD("local.x.success media=image id=$tweetId imageCount=${result.imageUrls.size} costMs=${System.currentTimeMillis() - start}")
            return VideoInfo(
                id = tweetId,
                downloadUrl = result.imageUrls.first(),
                title = result.title,
                mediaType = MediaType.IMAGES,
                imageUrls = result.imageUrls,
            )
        }

        throw Exception("X 推文中未找到可下载媒体")
    }

    private fun resolveXMedia(
        tweetId: String,
        queryId: String,
        bearerToken: String,
        cookies: Map<String, String>,
    ): XMediaResult {
        val variables = """{"tweetId":"$tweetId","withCommunity":false,"includePromotedContent":false,"withVoice":true}"""
        val features =
            """{"responsive_web_graphql_exclude_directive_enabled":true,"longform_notetweets_inline_media_enabled":true,"responsive_web_media_download_video_enabled":true,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":true}"""
        val endpoint =
            "https://x.com/i/api/graphql/$queryId/TweetResultByRestId?variables=${
                java.net.URLEncoder.encode(variables, "UTF-8")
            }&features=${java.net.URLEncoder.encode(features, "UTF-8")}"

        var lastError = "unknown error"
        for (attempt in 0 until 3) {
            try {
                logD("local.x.graphql.try[$attempt] endpoint=$endpoint")
                val headers = buildXGraphqlHeaders(tweetId, bearerToken, cookies)
                val req = Request.Builder()
                    .url(endpoint)
                    .headers(okhttp3.Headers.headersOf(*headers.flatMap { listOf(it.key, it.value) }.toTypedArray()))
                    .build()
                xLocalClient.newCall(req).execute().use { response ->
                    if (response.code == 401) {
                        lastError = "unauthorized, cookie may be expired"
                        logW("local.x.graphql.try[$attempt] status=401")
                        return@use
                    }
                    if (!response.isSuccessful) {
                        lastError = "HTTP ${response.code}"
                        logW("local.x.graphql.try[$attempt] failed status=${response.code}")
                        return@use
                    }
                    val body = response.body?.string() ?: ""
                    val payload = json.parseToJsonElement(body)
                    val unavailable = extractXTweetUnavailableReason(payload)
                    if (!unavailable.isNullOrBlank()) {
                        lastError = unavailable
                        logW("local.x.graphql.try[$attempt] unavailable=$unavailable")
                        return@use
                    }
                    val parsed = extractXMediaFromGraphql(payload)
                    if (parsed.videoCandidates.isNotEmpty() || parsed.imageUrls.isNotEmpty()) {
                        logD("local.x.graphql.success try[$attempt] status=${response.code} videos=${parsed.videoCandidates.size} images=${parsed.imageUrls.size}")
                        return parsed
                    }
                    lastError = "no media in graphql response"
                    logW("local.x.graphql.try[$attempt] no candidates")
                }
            } catch (e: Exception) {
                lastError = e.message ?: "unknown error"
                logW("local.x.graphql.try[$attempt] exception=$lastError")
            }
            if ("tweet unavailable" in lastError.lowercase()) break
        }
        throw Exception("X graphql resolve failed: $lastError")
    }

    private fun loadXGraphqlMetadata(tweetId: String, cookies: Map<String, String>): Pair<String, String> {
        val now = System.currentTimeMillis()
        xMetadataCache?.let { cached ->
            if (now - cached.third < 30 * 60 * 1000) {
                logD("local.x.meta.cache hit")
                return cached.first to cached.second
            }
        }

        val pageHeaders = buildXPageHeaders(cookies)
        val pageReq = Request.Builder()
            .url("https://x.com/i/status/$tweetId")
            .headers(okhttp3.Headers.headersOf(*pageHeaders.flatMap { listOf(it.key, it.value) }.toTypedArray()))
            .build()

        val html = xLocalClient.newCall(pageReq).execute().use { response ->
            if (!response.isSuccessful) throw Exception("X page load failed: HTTP ${response.code}")
            response.body?.string() ?: throw Exception("X page load failed: empty body")
        }
        val mainJsUrl = extractXMainJsUrl(html) ?: throw Exception("Could not locate X main.js bundle")
        logD("local.x.meta.mainJs url=$mainJsUrl")

        val jsReq = Request.Builder()
            .url(mainJsUrl)
            .headers(okhttp3.Headers.headersOf(*pageHeaders.flatMap { listOf(it.key, it.value) }.toTypedArray()))
            .build()
        val js = xLocalClient.newCall(jsReq).execute().use { response ->
            if (!response.isSuccessful) throw Exception("X main.js fetch failed: HTTP ${response.code}")
            response.body?.string() ?: throw Exception("X main.js fetch failed: empty body")
        }

        val queryId = extractXQueryId(js)
        val bearer = extractXBearerToken(js)
        if (queryId.isNullOrBlank() || bearer.isNullOrBlank()) {
            throw Exception("Could not parse X graphql metadata from main.js")
        }

        xMetadataCache = Triple(queryId, bearer, now)
        logD("local.x.meta.success queryId=$queryId bearerLen=${bearer.length}")
        return queryId to bearer
    }

    private fun buildXPageHeaders(cookies: Map<String, String>): Map<String, String> = mapOf(
        "User-Agent" to "Mozilla/5.0",
        "Accept" to "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language" to "en-US,en;q=0.9",
        "Referer" to "https://x.com/",
        "Cookie" to buildCookieHeader(cookies),
    )

    private fun buildXGraphqlHeaders(
        tweetId: String,
        bearerToken: String,
        cookies: Map<String, String>,
    ): Map<String, String> = mapOf(
        "User-Agent" to "Mozilla/5.0",
        "Authorization" to "Bearer $bearerToken",
        "X-CSRF-Token" to (cookies["ct0"] ?: ""),
        "X-Twitter-Active-User" to "yes",
        "X-Twitter-Auth-Type" to "OAuth2Session",
        "Referer" to "https://x.com/i/status/$tweetId",
        "Origin" to "https://x.com",
        "Accept" to "*/*",
        "Accept-Language" to "en-US,en;q=0.9",
        "Cookie" to buildCookieHeader(cookies),
    )

    private fun extractXTweetId(url: String): String? =
        Regex("""/status/(\d+)""", RegexOption.IGNORE_CASE)
            .find(url)
            ?.groupValues
            ?.getOrNull(1)

    private fun extractXMainJsUrl(html: String): String? =
        xMainJsPattern.find(html)?.value

    private fun extractXQueryId(js: String): String? =
        Regex(
            """queryId:"([A-Za-z0-9_-]{20,})",operationName:"TweetResultByRestId"""",
            RegexOption.IGNORE_CASE
        ).find(js)?.groupValues?.getOrNull(1)

    private fun extractXBearerToken(js: String): String? =
        Regex("""AAAAAAAAAAAAAAAAAAAAA[A-Za-z0-9%_=-]{40,}""")
            .find(js)
            ?.value

    private data class XMediaResult(
        val title: String? = null,
        val videoCandidates: List<String> = emptyList(),
        val imageUrls: List<String> = emptyList(),
    )

    private fun extractXMediaFromGraphql(payload: JsonElement): XMediaResult {
        var title: String? = null
        val mp4s = mutableListOf<Pair<Int, String>>()
        val others = mutableListOf<String>()
        val imageUrls = mutableListOf<String>()

        fun walk(node: JsonElement?) {
            when (node) {
                is JsonObject -> {
                    val fullText = jsonPrimitiveContent(node["full_text"])
                    if (!fullText.isNullOrBlank() && title.isNullOrBlank()) {
                        title = fullText.trim()
                    }

                    val variants = node["variants"] as? JsonArray
                    variants?.forEach { variantItem ->
                        val variant = variantItem as? JsonObject ?: return@forEach
                        val url = jsonPrimitiveContent(variant["url"]) ?: return@forEach
                        if (!url.contains("video.twimg.com")) return@forEach
                        val contentType = jsonPrimitiveContent(variant["content_type"])
                        val bitrate = jsonPrimitiveInt(variant["bitrate"]) ?: 0
                        when {
                            contentType == "video/mp4" -> mp4s.add(bitrate to url)
                            ".m3u8" in url.lowercase() -> others.add(url)
                        }
                    }

                    // 图片推文: type == "photo" 的 media_url_https
                    val mediaType = jsonPrimitiveContent(node["type"])
                    if (mediaType == "photo") {
                        val mediaUrl = jsonPrimitiveContent(node["media_url_https"])
                        if (!mediaUrl.isNullOrBlank() && "pbs.twimg.com" in mediaUrl) {
                            imageUrls.add(mediaUrl)
                        }
                    }

                    if (jsonPrimitiveContent(node["key"]) == "unified_card") {
                        val value = node["value"] as? JsonObject
                        val stringValue = jsonPrimitiveContent(value?.get("string_value"))
                        if (!stringValue.isNullOrBlank() && stringValue.startsWith("{")) {
                            val cardObj = runCatching { json.parseToJsonElement(stringValue) }.getOrNull()
                            if (cardObj != null) walk(cardObj)
                        }
                    }

                    node.values.forEach(::walk)
                }
                is JsonArray -> node.forEach(::walk)
                else -> {}
            }
        }

        walk(payload)
        val sortedMp4 = mp4s.sortedByDescending { it.first }.map { it.second }
        return XMediaResult(
            title = title,
            videoCandidates = dedupe(sortedMp4 + others),
            imageUrls = dedupe(imageUrls),
        )
    }

    private fun extractXTweetUnavailableReason(payload: JsonElement): String? {
        val root = payload as? JsonObject ?: return null
        val data = root["data"] as? JsonObject ?: return null
        val tweetResult = data["tweetResult"] as? JsonObject ?: return null
        val result = tweetResult["result"] as? JsonObject ?: return null
        val typeName = jsonPrimitiveContent(result["__typename"])
        if (typeName == "TweetUnavailable") {
            val reason = jsonPrimitiveContent(result["reason"]) ?: "unknown"
            return "tweet unavailable: $reason"
        }
        return null
    }

    private fun jsonPrimitiveInt(element: JsonElement?): Int? {
        val primitive = element as? JsonPrimitive ?: return null
        return primitive.content.toIntOrNull()
    }

    // ---------------------------------------------------------------
    // 小红书本地 HTML 解析（可行性实验）
    // ---------------------------------------------------------------

    private data class XiaohongshuParsedMedia(
        val title: String? = null,
        val videoCandidates: List<String> = emptyList(),
        val mediaType: MediaType = MediaType.VIDEO,
        val imageUrls: List<String> = emptyList(),
    )

    private fun resolveXiaohongshuLocally(url: String): VideoInfo {
        val start = System.currentTimeMillis()
        logD("local.xhs.start url=$url")
        val request = Request.Builder()
            .url(url)
            .header("User-Agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1")
            .header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
            .header("Accept-Language", "zh-CN,zh-Hans;q=0.9")
            .header("Referer", "https://www.xiaohongshu.com/")
            .build()

        xiaohongshuLocalClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw Exception("请求失败: HTTP ${response.code}")
            val html = response.body?.string() ?: throw Exception("空响应")
            val webpageUrl = response.request.url.toString()
            val parsed = parseXiaohongshuHtml(html)
            val noteId = extractXiaohongshuNoteId(webpageUrl) ?: "xhs_unknown_${System.currentTimeMillis()}"
            logD(
                "local.xhs.parsed status=${response.code} finalUrl=$webpageUrl htmlBytes=${html.length} " +
                    "videoCandidates=${parsed.videoCandidates.size} imageUrls=${parsed.imageUrls.size} mediaType=${parsed.mediaType}"
            )

            if (parsed.mediaType == MediaType.IMAGES && parsed.imageUrls.isNotEmpty()) {
                logD("local.xhs.success media=image id=$noteId costMs=${System.currentTimeMillis() - start}")
                return VideoInfo(
                    id = noteId,
                    downloadUrl = normalizeXiaohongshuMediaUrl(parsed.imageUrls.first()),
                    title = parsed.title,
                    mediaType = MediaType.IMAGES,
                    imageUrls = parsed.imageUrls.map(::normalizeXiaohongshuMediaUrl),
                )
            }

            if (parsed.videoCandidates.isEmpty()) {
                throw Exception("No video link found in XiaoHongShu page")
            }

            logD("local.xhs.success media=video id=$noteId costMs=${System.currentTimeMillis() - start}")
            return VideoInfo(
                id = noteId,
                downloadUrl = normalizeXiaohongshuMediaUrl(parsed.videoCandidates.first()),
                title = parsed.title,
                mediaType = MediaType.VIDEO,
                imageUrls = emptyList(),
            )
        }
    }

    private fun parseXiaohongshuHtml(html: String): XiaohongshuParsedMedia {
        val initial = parseXiaohongshuInitialState(html)
        if (initial.videoCandidates.isNotEmpty() || initial.imageUrls.isNotEmpty()) return initial

        val rawCandidates = parseXiaohongshuRawHtml(html)
        return XiaohongshuParsedMedia(
            title = initial.title,
            videoCandidates = rawCandidates,
            mediaType = MediaType.VIDEO,
            imageUrls = emptyList(),
        )
    }

    private fun parseXiaohongshuInitialState(html: String): XiaohongshuParsedMedia {
        val jsonStr = extractJsonAssignment(html, "window.__INITIAL_STATE__")
            ?.replace("undefined", "null")
            ?: return XiaohongshuParsedMedia()

        val root = try {
            json.parseToJsonElement(jsonStr) as? JsonObject
        } catch (_: Exception) {
            null
        } ?: return XiaohongshuParsedMedia()

        val notes = mutableListOf<JsonObject>()

        val noteDataPath = (((root["noteData"] as? JsonObject)
            ?.get("data") as? JsonObject)
            ?.get("noteData")) as? JsonObject
        if (noteDataPath != null) notes.add(noteDataPath)

        val noteDetailMap = ((root["note"] as? JsonObject)
            ?.get("noteDetailMap")) as? JsonObject
        noteDetailMap?.values?.forEach { entry ->
            val note = (entry as? JsonObject)?.get("note") as? JsonObject
            if (note != null) notes.add(note)
        }

        var title: String? = null
        val candidates = mutableListOf<String>()
        val imageUrls = mutableListOf<String>()

        for (note in notes) {
            val noteType = jsonPrimitiveContent(note["type"])
            if (title == null) {
                title = jsonPrimitiveContent(note["title"]) ?: jsonPrimitiveContent(note["desc"])
            }

            if (noteType == "normal") {
                val imageList = note["imageList"] as? JsonArray ?: JsonArray(emptyList())
                for (imgItem in imageList) {
                    val img = imgItem as? JsonObject ?: continue
                    var imgUrl: String? = null
                    val infoList = img["infoList"] as? JsonArray ?: JsonArray(emptyList())
                    for (infoItem in infoList) {
                        val info = infoItem as? JsonObject ?: continue
                        if (jsonPrimitiveContent(info["imageScene"]) == "H5_DTL") {
                            imgUrl = jsonPrimitiveContent(info["url"])
                            break
                        }
                    }
                    if (imgUrl.isNullOrBlank()) {
                        imgUrl = jsonPrimitiveContent(img["url"])
                    }
                    if (!imgUrl.isNullOrBlank()) {
                        if (imgUrl.startsWith("http://")) {
                            imgUrl = "https://" + imgUrl.removePrefix("http://")
                        }
                        imageUrls.add(normalizeXiaohongshuMediaUrl(imgUrl))
                    }
                }
                if (imageUrls.isNotEmpty()) {
                    return XiaohongshuParsedMedia(
                        title = title,
                        videoCandidates = emptyList(),
                        mediaType = MediaType.IMAGES,
                        imageUrls = dedupe(imageUrls),
                    )
                }
            }

            if (noteType == "video") {
                val stream = (((note["video"] as? JsonObject)
                    ?.get("media") as? JsonObject)
                    ?.get("stream")) as? JsonObject

                for (codec in listOf("h264", "h265", "av1")) {
                    val streams = stream?.get(codec) as? JsonArray ?: JsonArray(emptyList())
                    for (item in streams) {
                        val obj = item as? JsonObject ?: continue
                        val url = jsonPrimitiveContent(obj["masterUrl"])
                        if (!url.isNullOrBlank() && url.startsWith("http")) {
                            candidates.add(normalizeXiaohongshuMediaUrl(url))
                        }
                    }
                }
            }
        }

        return XiaohongshuParsedMedia(
            title = title,
            videoCandidates = dedupe(candidates),
            mediaType = MediaType.VIDEO,
            imageUrls = emptyList(),
        )
    }

    private fun parseXiaohongshuRawHtml(html: String): List<String> {
        val patterns = listOf(
            Regex("""(https?:\\/\\/[^"']+xhscdn\.(?:com|net)[^"']*\.mp4[^"']*)""", RegexOption.IGNORE_CASE),
            Regex("""(https?://[^"']+xhscdn\.(?:com|net)[^"']*\.mp4[^"']*)""", RegexOption.IGNORE_CASE),
            Regex("""(https?:\\/\\/[^"']+xhscdn\.(?:com|net)[^"']*)""", RegexOption.IGNORE_CASE),
            Regex("""(https?://[^"']+xhscdn\.(?:com|net)[^"']*)""", RegexOption.IGNORE_CASE),
        )
        val results = mutableListOf<String>()
        for (pattern in patterns) {
            for (m in pattern.findAll(html)) {
                val raw = m.groupValues[1].replace("\\/", "/")
                if (raw.contains("/stream/") || raw.contains("/video/") || raw.contains("masterUrl") || raw.contains(".mp4")) {
                    results.add(normalizeXiaohongshuMediaUrl(raw))
                }
            }
        }
        return dedupe(results)
    }

    private fun extractXiaohongshuNoteId(url: String): String? =
        Regex("""/(?:explore|discovery/item)/([a-zA-Z0-9_\-]+)""", RegexOption.IGNORE_CASE)
            .find(url)
            ?.groupValues
            ?.getOrNull(1)

    private fun jsonPrimitiveContent(element: JsonElement?): String? =
        (element as? JsonPrimitive)?.let { p ->
            runCatching { p.content }.getOrNull()?.takeIf { it.isNotBlank() }
        }

    private fun dedupe(urls: List<String>): List<String> = LinkedHashSet(urls).toList()

    // ---------------------------------------------------------------
    // 快手本地解析
    // ---------------------------------------------------------------

    private val kuaishouAtlasPhotoTypes = setOf("VERTICAL_ATLAS", "HORIZONTAL_ATLAS", "MULTI_IMAGE")

    private fun resolveKuaishouLocally(url: String): VideoInfo {
        val start = System.currentTimeMillis()
        logD("local.kuaishou.start url=$url")

        val request = Request.Builder()
            .url(url)
            .header("User-Agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1")
            .header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
            .header("Accept-Language", "zh-CN,zh-Hans;q=0.9")
            .header("Referer", "https://www.kuaishou.com/")
            .build()

        kuaishouLocalClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw Exception("请求失败: HTTP ${response.code}")
            val html = response.body?.string() ?: throw Exception("空响应")
            val webpageUrl = response.request.url.toString()
            logD("local.kuaishou.fetched status=${response.code} finalUrl=$webpageUrl htmlBytes=${html.length}")

            val videoId = extractKuaishouVideoId(webpageUrl)
            val photoId = extractKuaishouPhotoId(webpageUrl)

            // 尝试通过 API 获取
            if (photoId != null) {
                val apiResult = resolveKuaishouViaApi(photoId)
                if (apiResult != null) {
                    val vid = videoId ?: photoId ?: "ks_unknown_${System.currentTimeMillis()}"
                    if (apiResult.mediaType == MediaType.IMAGES && apiResult.imageUrls.isNotEmpty()) {
                        logD("local.kuaishou.api.success media=image id=$vid imageCount=${apiResult.imageUrls.size} costMs=${System.currentTimeMillis() - start}")
                        return VideoInfo(
                            id = vid,
                            downloadUrl = apiResult.imageUrls.first(),
                            title = apiResult.title,
                            mediaType = MediaType.IMAGES,
                            imageUrls = apiResult.imageUrls,
                        )
                    }
                    if (apiResult.videoCandidates.isNotEmpty()) {
                        logD("local.kuaishou.api.success media=video id=$vid costMs=${System.currentTimeMillis() - start}")
                        return VideoInfo(
                            id = vid,
                            downloadUrl = apiResult.videoCandidates.first(),
                            title = apiResult.title,
                            mediaType = MediaType.VIDEO,
                        )
                    }
                }
            }

            // 回退到 HTML 解析
            val parsed = parseKuaishouHtml(html)
            if (parsed.videoCandidates.isEmpty()) {
                throw Exception("No video link found in Kuaishou page")
            }

            val vid = videoId ?: "ks_unknown_${System.currentTimeMillis()}"
            logD("local.kuaishou.html.success media=video id=$vid costMs=${System.currentTimeMillis() - start}")
            return VideoInfo(
                id = vid,
                downloadUrl = parsed.videoCandidates.first(),
                title = parsed.title,
                mediaType = MediaType.VIDEO,
            )
        }
    }

    private data class KuaishouApiResult(
        val title: String? = null,
        val mediaType: MediaType = MediaType.VIDEO,
        val imageUrls: List<String> = emptyList(),
        val videoCandidates: List<String> = emptyList(),
    )

    private fun resolveKuaishouViaApi(photoId: String): KuaishouApiResult? {
        val apiUrl = "https://v.m.chenzhongtech.com/rest/wd/ugH5App/photo/simple/info"
        val bodyJson = """{"photoId":"$photoId","kpn":"KUAISHOU"}"""
        val request = Request.Builder()
            .url(apiUrl)
            .header("User-Agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1")
            .header("Accept", "*/*")
            .header("Referer", "https://www.kuaishou.com/")
            .header("Content-Type", "application/json")
            .post(bodyJson.toRequestBody("application/json".toMediaType()))
            .build()

        val responseBody = try {
            kuaishouLocalClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    logW("local.kuaishou.api failed status=${response.code}")
                    return null
                }
                response.body?.string()
            }
        } catch (e: Exception) {
            logW("local.kuaishou.api exception=${e.message}")
            return null
        }

        if (responseBody.isNullOrBlank()) return null

        val root = try {
            json.parseToJsonElement(responseBody) as? JsonObject
        } catch (_: Exception) {
            return null
        } ?: return null

        val result = jsonPrimitiveContent(root["result"])
        if (result != "1") return null

        val photo = root["photo"] as? JsonObject ?: return null
        val title = jsonPrimitiveContent(photo["caption"])
        val photoType = jsonPrimitiveContent(photo["photoType"]) ?: ""

        // 图文作品：从 atlas 提取图片 URL
        val atlas = root["atlas"] as? JsonObject
        val cdnList = atlas?.get("cdnList") as? JsonArray
        val imgList = atlas?.get("list") as? JsonArray

        if (photoType in kuaishouAtlasPhotoTypes && cdnList != null && cdnList.isNotEmpty() && imgList != null && imgList.isNotEmpty()) {
            val firstCdn = (cdnList.firstOrNull() as? JsonObject)
            val cdn = jsonPrimitiveContent(firstCdn?.get("cdn")) ?: ""
            if (cdn.isNotBlank()) {
                val imageUrls = mutableListOf<String>()
                for (pathElement in imgList) {
                    val path = (pathElement as? JsonPrimitive)?.content
                    if (!path.isNullOrBlank()) {
                        imageUrls.add("https://$cdn$path")
                    }
                }
                if (imageUrls.isNotEmpty()) {
                    logD("local.kuaishou.api atlas photoType=$photoType imageCount=${imageUrls.size}")
                    return KuaishouApiResult(
                        title = title,
                        mediaType = MediaType.IMAGES,
                        imageUrls = imageUrls,
                    )
                }
            }
        }

        // 视频作品：从 mainMvUrls 提取
        val mainMvUrls = photo["mainMvUrls"] as? JsonArray
        val videoCandidates = mutableListOf<String>()
        if (mainMvUrls != null) {
            for (item in mainMvUrls) {
                val obj = item as? JsonObject ?: continue
                val videoUrl = jsonPrimitiveContent(obj["url"])
                if (!videoUrl.isNullOrBlank() && videoUrl.startsWith("http")) {
                    videoCandidates.add(videoUrl)
                }
            }
        }

        if (videoCandidates.isNotEmpty()) {
            logD("local.kuaishou.api video candidateCount=${videoCandidates.size}")
            return KuaishouApiResult(
                title = title,
                mediaType = MediaType.VIDEO,
                videoCandidates = videoCandidates,
            )
        }

        return null
    }

    private data class KuaishouParsedMedia(
        val title: String? = null,
        val videoCandidates: List<String> = emptyList(),
    )

    private fun parseKuaishouHtml(html: String): KuaishouParsedMedia {
        // 策略 1: window.__APOLLO_STATE__
        val apollo = parseKuaishouApolloState(html)
        if (apollo.videoCandidates.isNotEmpty()) return apollo

        // 策略 2: window.__INITIAL_STATE__
        val initial = parseKuaishouInitialState(html)
        if (initial.videoCandidates.isNotEmpty()) {
            return KuaishouParsedMedia(
                title = initial.title ?: apollo.title,
                videoCandidates = initial.videoCandidates,
            )
        }

        // 策略 3: 原始 HTML 正则匹配 CDN URL
        val rawCandidates = parseKuaishouRawHtml(html)
        return KuaishouParsedMedia(title = apollo.title ?: initial.title, videoCandidates = rawCandidates)
    }

    private fun parseKuaishouApolloState(html: String): KuaishouParsedMedia {
        val jsonStr = extractJsonAssignment(html, "window.__APOLLO_STATE__") ?: return KuaishouParsedMedia()

        val root = try {
            json.parseToJsonElement(jsonStr) as? JsonObject
        } catch (_: Exception) {
            null
        } ?: return KuaishouParsedMedia()

        var title: String? = null
        val candidates = mutableListOf<String>()

        for ((key, value) in root) {
            val obj = value as? JsonObject ?: continue
            if (!("Photo" in key || "Work" in key || "Video" in key)) continue
            val videoUrl = jsonPrimitiveContent(obj["videoUrl"])
                ?: jsonPrimitiveContent(obj["video_url"])
            if (!videoUrl.isNullOrBlank() && videoUrl.startsWith("http")) {
                if (title == null) {
                    title = jsonPrimitiveContent(obj["caption"]) ?: jsonPrimitiveContent(obj["title"])
                }
                candidates.add(videoUrl)
            }
        }

        return KuaishouParsedMedia(title = title, videoCandidates = dedupe(candidates))
    }

    private fun parseKuaishouInitialState(html: String): KuaishouParsedMedia {
        val jsonStr = extractJsonAssignment(html, "window.__INITIAL_STATE__")
            ?.replace("undefined", "null")
            ?: return KuaishouParsedMedia()

        val root = try {
            json.parseToJsonElement(jsonStr)
        } catch (_: Exception) {
            return KuaishouParsedMedia()
        }

        var title: String? = null
        val candidates = mutableListOf<String>()

        fun walk(node: JsonElement) {
            when (node) {
                is JsonObject -> {
                    for ((k, v) in node) {
                        if (k in listOf("videoUrl", "video_url", "mp4Url") && v is JsonPrimitive) {
                            val url = v.content
                            if (url.startsWith("http")) candidates.add(url)
                        } else if (k in listOf("caption", "title") && v is JsonPrimitive && title == null) {
                            val text = v.content
                            if (text.isNotBlank()) title = text
                        } else {
                            walk(v)
                        }
                    }
                }
                is JsonArray -> node.forEach(::walk)
                else -> {}
            }
        }

        walk(root)
        return KuaishouParsedMedia(title = title, videoCandidates = dedupe(candidates))
    }

    private fun parseKuaishouRawHtml(html: String): List<String> {
        val patterns = listOf(
            Regex("""(https?:\\/\\/[^"']+kwimgs\.com[^"']*\.mp4[^"']*)""", RegexOption.IGNORE_CASE),
            Regex("""(https?:\\/\\/[^"']+kwai\.net[^"']*\.mp4[^"']*)""", RegexOption.IGNORE_CASE),
            Regex("""(https?://[^"']+kwimgs\.com[^"']*\.mp4[^"']*)""", RegexOption.IGNORE_CASE),
            Regex("""(https?://[^"']+kwai\.net[^"']*\.mp4[^"']*)""", RegexOption.IGNORE_CASE),
        )
        val results = mutableListOf<String>()
        for (pattern in patterns) {
            for (m in pattern.findAll(html)) {
                val raw = m.groupValues[1].replace("\\/", "/")
                results.add(raw)
            }
        }
        return dedupe(results)
    }

    private fun extractKuaishouVideoId(url: String): String? =
        Regex("""/(?:short-video|video)/([a-zA-Z0-9_\-]+)""", RegexOption.IGNORE_CASE)
            .find(url)
            ?.groupValues
            ?.getOrNull(1)

    private fun extractKuaishouPhotoId(url: String): String? {
        val m1 = Regex("""/(?:fw/)?photo/([a-zA-Z0-9_\-]+)""", RegexOption.IGNORE_CASE).find(url)
        if (m1 != null) return m1.groupValues[1]
        val m2 = Regex("""photoId=([a-zA-Z0-9_\-]+)""", RegexOption.IGNORE_CASE).find(url)
        return m2?.groupValues?.getOrNull(1)
    }

    // ---------------------------------------------------------------
    // Backend 解析
    // ---------------------------------------------------------------

    private fun resolveViaBackend(text: String): VideoInfo {
        val start = System.currentTimeMillis()
        logD("backend.resolve.start inputLength=${text.length}")
        val cookies = CookieStore.allCookies(context)
            .ifEmpty { null }
        logD("backend.resolve.cookies platforms=${cookies?.keys?.joinToString(",") ?: "none"}")
        val requestBody = json.encodeToString(
            ResolveRequest.serializer(),
            ResolveRequest(text = text, cookies = cookies),
        )

        var lastError = "未知错误"

        for ((index, backendUrl) in BACKEND_URLS.withIndex()) {
            try {
                logD("backend.resolve.try[$index] url=$backendUrl")
                val request = Request.Builder()
                    .url(backendUrl)
                    .post(requestBody.toRequestBody("application/json".toMediaType()))
                    .build()

                resolveClient.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) {
                        val body = response.body?.string() ?: ""
                        lastError = try {
                            json.decodeFromString<com.demo.videopick.data.model.ErrorResponse>(body).detail
                        } catch (_: Exception) {
                            "HTTP ${response.code}"
                        }
                        logW("backend.resolve.try[$index] failed status=${response.code} detail=$lastError")
                        return@use
                    }

                    val body = response.body?.string() ?: throw Exception("空响应")
                    val resp = json.decodeFromString<ResolveResponse>(body)

                    val mediaType = if (resp.media_type == "image") MediaType.IMAGES else MediaType.VIDEO
                    val videoId = resp.video_id?.takeIf { it.isNotBlank() }
                        ?: "unknown_${System.currentTimeMillis()}"

                    // Normalize download URLs
                    val downloadUrl = normalizeUrl(resp.download_url, backendUrl)
                    val imageUrls = resp.image_urls.map { normalizeUrl(it, backendUrl) }
                    logD(
                        "backend.resolve.success try[$index] status=${response.code} id=$videoId mediaType=$mediaType " +
                            "downloadUrl=$downloadUrl imageCount=${imageUrls.size} costMs=${System.currentTimeMillis() - start}"
                    )

                    return VideoInfo(
                        id = videoId,
                        downloadUrl = downloadUrl,
                        title = resp.title,
                        mediaType = mediaType,
                        imageUrls = imageUrls,
                    )
                }
            } catch (e: Exception) {
                lastError = e.message ?: "网络错误"
                logW("backend.resolve.try[$index] exception=$lastError")
            }
        }

        logE("backend.resolve.fail costMs=${System.currentTimeMillis() - start} lastError=$lastError")
        throw Exception("服务端解析失败: $lastError")
    }

    private fun normalizeUrl(raw: String, backendUrl: String): String {
        if (raw.startsWith("/")) {
            // Relative path -> append to backend base
            val base = backendUrl.substringBeforeLast("/")
            return "$base$raw"
        }
        // Replace localhost with actual backend host
        val lower = raw.lowercase()
        if ("localhost" in lower || "127.0.0.1" in lower || "::1" in lower) {
            val backendBase = backendUrl.substringBeforeLast("/resolve")
            return try {
                val parsed = java.net.URI(raw)
                val backendParsed = java.net.URI(backendBase)
                java.net.URI(
                    backendParsed.scheme, null,
                    backendParsed.host, backendParsed.port,
                    parsed.path, parsed.query, null
                ).toString()
            } catch (_: Exception) { raw }
        }
        return raw
    }

    private fun downloadFile(
        url: String,
        fileName: String,
        onProgress: (Float) -> Unit,
    ): String {
        val start = System.currentTimeMillis()
        logD("download.start fileName=$fileName url=$url")
        val requestBuilder = Request.Builder()
            .url(url)
            .header("User-Agent", "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36")
            .header("Accept", "*/*")
        applyPlatformDownloadHeaders(requestBuilder, url)
        val request = requestBuilder.build()

        downloadClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw Exception("下载失败: HTTP ${response.code}")
            val body = response.body ?: throw Exception("下载失败: 空响应")
            logD("download.response status=${response.code} contentLength=${body.contentLength()}")

            val cacheDir = File(context.cacheDir, "downloads")
            if (!cacheDir.exists()) cacheDir.mkdirs()
            val file = File(cacheDir, fileName)

            val totalBytes = body.contentLength()
            var downloadedBytes = 0L

            FileOutputStream(file).use { fos ->
                val buffer = ByteArray(65536)
                val inputStream = body.byteStream()
                while (true) {
                    val read = inputStream.read(buffer)
                    if (read == -1) break
                    fos.write(buffer, 0, read)
                    downloadedBytes += read
                    if (totalBytes > 0) {
                        onProgress(downloadedBytes.toFloat() / totalBytes)
                    }
                }
            }

            onProgress(1f)
            logD("download.success path=${file.absolutePath} bytes=$downloadedBytes costMs=${System.currentTimeMillis() - start}")
            return file.absolutePath
        }
    }

    private fun applyPlatformDownloadHeaders(requestBuilder: Request.Builder, url: String) {
        val host = try {
            java.net.URI(url).host?.lowercase()
        } catch (_: Exception) {
            null
        } ?: return

        val isInstagramHost = host == "instagram.com" || host.endsWith(".instagram.com") ||
            host == "cdninstagram.com" || host.endsWith(".cdninstagram.com") ||
            host == "fbcdn.net" || host.endsWith(".fbcdn.net")
        if (isInstagramHost) {
            requestBuilder.header("Referer", "https://www.instagram.com/")
            val igCookies = CookieStore.getCookies(context, "instagram")
            if (igCookies.isNotEmpty()) {
                requestBuilder.header("Cookie", buildCookieHeader(igCookies))
            }
            logD("download.headers platform=instagram cookie=${if (igCookies.isNotEmpty()) "present" else "absent"}")
            return
        }

        val isXHost = host == "x.com" || host.endsWith(".x.com") ||
            host == "twitter.com" || host.endsWith(".twitter.com") ||
            host == "twimg.com" || host.endsWith(".twimg.com")
        if (isXHost) {
            requestBuilder.header("Referer", "https://x.com/")
            val xCookies = CookieStore.getCookies(context, "x")
            if (xCookies.isNotEmpty()) {
                requestBuilder.header("Cookie", buildCookieHeader(xCookies))
            }
            logD("download.headers platform=x cookie=${if (xCookies.isNotEmpty()) "present" else "absent"}")
            return
        }

        val isKuaishouHost = host.endsWith("kwimgs.com") || host.endsWith("kwai.net") ||
            host.endsWith("kuaishou.com") || host.endsWith("yximgs.com")
        if (isKuaishouHost) {
            requestBuilder.header("Referer", "https://www.kuaishou.com/")
            logD("download.headers platform=kuaishou")
        }
    }

    /**
     * Save video to gallery via MediaStore.
     */
    fun saveVideoToGallery(localPath: String): String {
        val file = File(localPath)
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, file.name)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/VideoPick")
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }
        }

        val uri = context.contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
            ?: throw Exception("无法创建媒体文件")

        context.contentResolver.openOutputStream(uri)?.use { os ->
            file.inputStream().use { it.copyTo(os) }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            values.clear()
            values.put(MediaStore.Video.Media.IS_PENDING, 0)
            context.contentResolver.update(uri, values, null, null)
        }

        return "视频已保存到相册"
    }

    /**
     * Save images to gallery via MediaStore.
     */
    fun saveImagesToGallery(localPaths: List<String>): String {
        for (path in localPaths) {
            val file = File(path)
            val mimeType = when {
                path.endsWith(".png") -> "image/png"
                path.endsWith(".webp") -> "image/webp"
                else -> "image/jpeg"
            }

            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, file.name)
                put(MediaStore.Images.Media.MIME_TYPE, mimeType)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/VideoPick")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
            }

            val uri = context.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                ?: continue

            context.contentResolver.openOutputStream(uri)?.use { os ->
                file.inputStream().use { it.copyTo(os) }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                context.contentResolver.update(uri, values, null, null)
            }
        }

        return "${localPaths.size} 张图片已保存到相册"
    }
}
