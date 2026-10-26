package com.demo.videopick.clipboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ClipboardAutoDownloadCandidateTest {
    @Test
    fun `resolves first url and trims share punctuation`() {
        val text = "漂发成洋妞了 https://xhslink.cn/o/AqqloiNRXIz 复制后打开"

        val candidate = ClipboardAutoDownloadCandidate.resolve(
            text = text,
            lastHandledFingerprint = null,
        )

        assertEquals(text, candidate?.text)
        assertEquals("https://xhslink.cn/o/AqqloiNRXIz", candidate?.fingerprint)
    }

    @Test
    fun `fingerprint trims markdown link wrapper`() {
        val text = "[https://v.douyin.com/bGEx0S\\_dBf4/](https://v.douyin.com/bGEx0S_dBf4/)"

        val candidate = ClipboardAutoDownloadCandidate.resolve(
            text = text,
            lastHandledFingerprint = null,
        )

        assertEquals("https://v.douyin.com/bGEx0S_dBf4/", candidate?.fingerprint)
    }

    @Test
    fun `ignores duplicate clipboard url`() {
        val text = "看这个 https://vt.tiktok.com/ZS4YCsm1W/"
        val first = ClipboardAutoDownloadCandidate.resolve(text, null)

        val duplicate = ClipboardAutoDownloadCandidate.resolve(text, first?.fingerprint)

        assertNull(duplicate)
    }

    @Test
    fun `ignores plain text`() {
        assertNull(ClipboardAutoDownloadCandidate.resolve("今天没有链接", null))
    }
}
