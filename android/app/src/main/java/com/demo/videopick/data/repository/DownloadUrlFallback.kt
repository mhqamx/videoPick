package com.demo.videopick.data.repository

/**
 * Mirrors iOS `candidateDownloadURLs`: keep the original URL, then retry the
 * backend proxy source or Douyin play/playwm variants when the first CDN rejects us.
 */
internal object DownloadUrlFallback {
    fun candidates(url: String): List<String> {
        val result = linkedSetOf<String>()
        fun add(value: String) {
            if (value.isNotBlank()) result.add(value)
        }

        add(url)
        extractBackendProxySourceUrl(url)?.let { source ->
            add(source)
            return result.toList()
        }

        add(url.replace("/play/", "/playwm/"))
        val stripped = stripQueryParam(url, "line")
        if (stripped != url) {
            add(stripped)
            add(stripped.replace("/play/", "/playwm/"))
        }
        return result.toList()
    }

    private fun extractBackendProxySourceUrl(url: String): String? {
        return try {
            val uri = java.net.URI(url)
            if (!uri.path.orEmpty().endsWith("/download")) return null
            val source = uri.rawQuery
                ?.split("&")
                ?.firstOrNull { it.substringBefore("=") == "source" }
                ?.substringAfter("=", "")
                ?.takeIf { it.isNotBlank() }
                ?: return null
            java.net.URLDecoder.decode(source, "UTF-8")
        } catch (_: Exception) {
            null
        }
    }

    private fun stripQueryParam(url: String, name: String): String {
        return try {
            val uri = java.net.URI(url)
            val rawQuery = uri.rawQuery ?: return url
            val filtered = rawQuery
                .split("&")
                .filter { it.substringBefore("=") != name }
                .joinToString("&")
                .ifBlank { null }
            java.net.URI(uri.scheme, uri.authority, uri.path, filtered, uri.fragment).toString()
        } catch (_: Exception) {
            url
        }
    }
}
