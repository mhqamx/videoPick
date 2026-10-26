package com.demo.videopick.data.repository

object DownloadPlatformClassifier {
    private val genericUrlPattern = Regex(
        """https?://[^\s，。！？；、<>"'\]\(\)]+""",
        RegexOption.IGNORE_CASE,
    )
    private val douyinUrlPattern = Regex(
        """https?://(?:[A-Za-z0-9_-]+\.)*(?:douyin\.com|iesdouyin\.com)/[^\s，。！？；、<>"'\]\(\)]+""",
        RegexOption.IGNORE_CASE,
    )
    private val xiaohongshuShortPattern = Regex(
        """https?://xhslink\.(?:com|cn)/(?:o/)?[a-zA-Z0-9_\-]+/?(?:\?[^\s]*)?""",
        RegexOption.IGNORE_CASE,
    )
    private val xiaohongshuLongPattern = Regex(
        """https?://(?:www\.)?xiaohongshu\.com/(?:explore|discovery/item)/[a-zA-Z0-9_\-]+(?:\?[^\s]*)?""",
        RegexOption.IGNORE_CASE,
    )
    private val trailingPunctuation = ".,!?;:)]}>\"'，。！？；：）】》、"

    fun extractDouyinUrl(text: String): String? =
        douyinUrlPattern.find(text)?.value
            ?.let(::cleanupExtractedUrl)
            ?.let(::normalizeDouyinInputUrl)

    fun extractXiaohongshuUrl(text: String): String? {
        for (pattern in listOf(xiaohongshuShortPattern, xiaohongshuLongPattern)) {
            val matched = pattern.find(text)?.value
            if (!matched.isNullOrBlank()) {
                return normalizeXiaohongshuInputUrl(cleanupExtractedUrl(matched))
            }
        }

        val candidate = genericUrlPattern.find(text)?.value?.let(::cleanupExtractedUrl)
        if (!candidate.isNullOrBlank()) {
            val lowered = candidate.lowercase()
            if ("xiaohongshu.com" in lowered || "xhslink.com" in lowered || "xhslink.cn" in lowered) {
                return normalizeXiaohongshuInputUrl(candidate)
            }
        }
        return null
    }

    private fun cleanupExtractedUrl(raw: String): String =
        raw.trim()
            .substringBefore("](")
            .substringBefore(")")
            .replace("\\_", "_")
            .trimEnd { it in trailingPunctuation }

    private fun normalizeDouyinInputUrl(url: String): String {
        val lower = url.lowercase()
        return if (lower.startsWith("http://")) {
            "https://" + url.removePrefix("http://")
        } else {
            url
        }
    }

    private fun normalizeXiaohongshuInputUrl(url: String): String {
        val lower = url.lowercase()
        return if (
            lower.startsWith("http://xhslink.com/") ||
            lower.startsWith("http://xhslink.cn/") ||
            lower.startsWith("http://www.xiaohongshu.com/")
        ) {
            "https://" + url.removePrefix("http://")
        } else {
            url
        }
    }
}
