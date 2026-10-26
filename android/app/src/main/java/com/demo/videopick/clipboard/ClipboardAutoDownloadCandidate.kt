package com.demo.videopick.clipboard

data class ClipboardAutoDownloadCandidate(
    val text: String,
    val fingerprint: String,
) {
    companion object {
        private val urlPattern = Regex("""https?://[^\s，。！？；、<>"'\]\(\)]+""", RegexOption.IGNORE_CASE)
        private val trailingPunctuation = ".,!?;:)]}>\"'，。！？；：）】》、"

        fun resolve(text: String, lastHandledFingerprint: String?): ClipboardAutoDownloadCandidate? {
            val trimmedText = text.trim()
            if (trimmedText.isBlank()) return null

            val rawUrl = urlPattern.find(trimmedText)?.value ?: return null
            val url = rawUrl
                .substringBefore("](")
                .substringBefore(")")
                .replace("\\_", "_")
                .trimEnd { it in trailingPunctuation }
            if (!url.startsWith("http", ignoreCase = true)) return null
            if (url == lastHandledFingerprint) return null

            return ClipboardAutoDownloadCandidate(
                text = trimmedText,
                fingerprint = url,
            )
        }
    }
}
