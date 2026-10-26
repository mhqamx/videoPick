package com.demo.videopick.channels

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

/** Opt-in protocol smoke test; never contains credentials or imports them into the Android app. */
class WeChatChannelsLiveTest {
    @Test fun `authorized live reference resolves and downloads`() = runBlocking {
        val cookieFile = System.getenv("VIDEOPICK_YUANBAO_COOKIE_FILE")
        assumeTrue("Optional live account not supplied", !cookieFile.isNullOrBlank())
        val cookie = File(cookieFile!!).readText().trim()
        val service = WeChatChannelsService()
        service.validateSession(cookie)
        val media = service.resolve("https://channels.weixin.qq.com/finder-preview/pages/sph?id=ADKbu5wdF8", cookie)
        assertTrue(media.id == "channels_ADKbu5wdF8")
        val directory = File(System.getenv("VIDEOPICK_CHANNELS_OUTPUT") ?: System.getProperty("java.io.tmpdir"), "android-channels-live")
        val downloaded = File(service.download(media.downloadUrl, directory) {})
        assertTrue(downloaded.length() > 1024)
        val header = downloaded.inputStream().use { input -> ByteArray(12).also { input.read(it) } }
        assertTrue(String(header, 4, 4, Charsets.US_ASCII) == "ftyp")
        println("PASS: Android Kotlin account validation, reference parsing and MP4 download")
    }
}
