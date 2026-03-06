package com.demo.videopick.data.repository

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import com.demo.videopick.data.model.MediaType
import com.demo.videopick.data.model.ResolveRequest
import com.demo.videopick.data.model.ResolveResponse
import com.demo.videopick.data.model.VideoInfo
import kotlinx.serialization.json.Json
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

    companion object {
        private val BACKEND_URLS = listOf(
            "http://10.0.2.2:8000/resolve", // Android Emulator -> host localhost
            "http://192.168.1.100:8000/resolve",
            "https://super-halibut-r4r59wg9qw93pv6p-8000.app.github.dev/resolve",
        )
    }

    private val douyinUrlPattern = Regex(
        """https?://[^\s]*(?:douyin\.com|iesdouyin\.com)[^\s]*""", RegexOption.IGNORE_CASE
    )

    private fun isDouyinUrl(text: String): Boolean =
        douyinUrlPattern.containsMatchIn(text)

    /**
     * Resolve then download media.
     * Douyin links: local HTML parse first -> fallback to backend.
     * Other links: backend first.
     */
    suspend fun parseAndDownload(
        text: String,
        onProgress: (Float) -> Unit = {},
    ): VideoInfo {
        val videoInfo = if (isDouyinUrl(text)) {
            try {
                resolveDouyinLocally(text)
            } catch (localErr: Exception) {
                try {
                    resolveViaBackend(text)
                } catch (_: Exception) {
                    throw localErr
                }
            }
        } else {
            resolveViaBackend(text)
        }

        return when (videoInfo.mediaType) {
            MediaType.VIDEO -> {
                val localPath = downloadFile(
                    url = videoInfo.downloadUrl,
                    fileName = "videopick_${videoInfo.id}.mp4",
                    onProgress = onProgress,
                )
                videoInfo.copy(localPath = localPath)
            }
            MediaType.IMAGES -> {
                val localPaths = videoInfo.imageUrls.mapIndexedNotNull { index, url ->
                    try {
                        val path = downloadFile(
                            url = url,
                            fileName = "videopick_${videoInfo.id}_$index.jpg",
                            onProgress = { p ->
                                onProgress((index + p) / videoInfo.imageUrls.size)
                            },
                        )
                        path
                    } catch (_: Exception) { null }
                }
                if (localPaths.isEmpty()) throw Exception("图片下载失败")
                videoInfo.copy(localImagePaths = localPaths)
            }
        }
    }

    // ---------------------------------------------------------------
    // 抖音本地 HTML 解析（与 iOS 端逻辑一致）
    // ---------------------------------------------------------------

    private fun extractUrl(text: String): String? {
        val m = Regex("""https?://[^\s]+""").find(text)
        return m?.value
    }

    private fun resolveDouyinLocally(text: String): VideoInfo {
        val url = extractUrl(text) ?: throw Exception("未找到有效链接")

        val request = Request.Builder()
            .url(url)
            .header("User-Agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1")
            .header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
            .header("Accept-Language", "zh-CN,zh-Hans;q=0.9")
            .header("Referer", "https://www.douyin.com/")
            .build()

        val response = resolveClient.newCall(request).execute()
        if (!response.isSuccessful) throw Exception("请求失败: HTTP ${response.code}")
        val html = response.body?.string() ?: throw Exception("空响应")

        return parseDouyinHtml(html)
    }

    private fun parseDouyinHtml(html: String): VideoInfo {
        // 尝试多种 JSON 数据模式
        val patterns = listOf(
            Regex("""window\._ROUTER_DATA\s*=\s*(\{.*?\})(?:\s*</script>|\s*;)""", RegexOption.DOT_MATCHES_ALL),
            Regex("""window\._SSR_HYDRATED_DATA\s*=\s*(\{.*?\})(?:\s*</script>|\s*;)""", RegexOption.DOT_MATCHES_ALL),
        )

        var jsonStr: String? = null
        for (pattern in patterns) {
            val m = pattern.find(html)
            if (m != null) {
                jsonStr = m.groupValues[1].trim()
                break
            }
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

    private fun parseVideoFromJson(jsonStr: String): VideoInfo? {
        try {
            // 查找 play_addr.url_list 中的视频 URL
            val urlListPattern = Regex(""""url_list"\s*:\s*\[\s*"(https?://[^"]+)"""")
            val descPattern = Regex(""""desc"\s*:\s*"([^"]*?)"""")
            val awemeIdPattern = Regex(""""aweme_id"\s*:\s*"(\d+)"""")

            // 查找包含 play_addr 的区域附近的 url_list
            val playAddrIdx = jsonStr.indexOf("play_addr")
            if (playAddrIdx == -1) return null

            val searchArea = jsonStr.substring(playAddrIdx, minOf(playAddrIdx + 2000, jsonStr.length))
            val urlMatch = urlListPattern.find(searchArea) ?: return null
            val rawUrl = urlMatch.groupValues[1].replace("\\/", "/")

            val normalizedUrl = normalizeDouyinVideoUrl(rawUrl)
            val title = descPattern.find(jsonStr)?.groupValues?.get(1)
            val videoId = awemeIdPattern.find(jsonStr)?.groupValues?.get(1)
                ?: "unknown_${System.currentTimeMillis()}"

            return VideoInfo(
                id = videoId,
                downloadUrl = normalizedUrl,
                title = title,
            )
        } catch (_: Exception) {
            return null
        }
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
    // Backend 解析
    // ---------------------------------------------------------------

    private fun resolveViaBackend(text: String): VideoInfo {
        val cookies = CookieStore.allCookies(context)
            .ifEmpty { null }
        val requestBody = json.encodeToString(
            ResolveRequest.serializer(),
            ResolveRequest(text = text, cookies = cookies),
        )

        var lastError = "未知错误"

        for (backendUrl in BACKEND_URLS) {
            try {
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
            }
        }

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
        val request = Request.Builder()
            .url(url)
            .header("User-Agent", "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36")
            .header("Accept", "*/*")
            .build()

        downloadClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw Exception("下载失败: HTTP ${response.code}")
            val body = response.body ?: throw Exception("下载失败: 空响应")

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
            return file.absolutePath
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
