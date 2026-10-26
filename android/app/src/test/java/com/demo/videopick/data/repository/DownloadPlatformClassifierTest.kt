package com.demo.videopick.data.repository

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DownloadPlatformClassifierTest {
    @Test
    fun `extracts douyin short link from markdown copied text`() {
        val text = """
            4.89 复制打开抖音，看看【傅立青的作品】美到我了 两个剑妈 # 和平精英剑来动画联动
            [https://v.douyin.com/bGEx0S\_dBf4/](https://v.douyin.com/bGEx0S_dBf4/) 07/21 W@z.TL :9pm iPK:/
        """.trimIndent()

        assertEquals(
            "https://v.douyin.com/bGEx0S_dBf4/",
            DownloadPlatformClassifier.extractDouyinUrl(text),
        )
    }

    @Test
    fun `extracts plain douyin short link`() {
        val text = "复制打开抖音，看看这个视频 https://v.douyin.com/abc_123/ 07/21"

        assertEquals(
            "https://v.douyin.com/abc_123/",
            DownloadPlatformClassifier.extractDouyinUrl(text),
        )
    }

    @Test
    fun `extracts xhslink cn short link`() {
        val text = "漂发成洋妞了 http://xhslink.cn/o/AqqloiNRXIz 复制后直奔小红书"

        assertEquals(
            "https://xhslink.cn/o/AqqloiNRXIz",
            DownloadPlatformClassifier.extractXiaohongshuUrl(text),
        )
    }

    @Test
    fun `extracts xiaohongshu long link`() {
        val url = "https://www.xiaohongshu.com/discovery/item/6a584d24000000000f0126ee?type=video"

        assertEquals(url, DownloadPlatformClassifier.extractXiaohongshuUrl(url))
    }

    @Test
    fun `ignores non xiaohongshu link`() {
        assertNull(DownloadPlatformClassifier.extractXiaohongshuUrl("https://v.douyin.com/abc123/"))
    }
}
