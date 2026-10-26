package com.demo.videopick.channels

import org.junit.Assert.*
import org.junit.Test

class ChannelsDownloadFlowTest {
    @Test fun `login resumes original text and automatic save once`() {
        val flow = ChannelsDownloadFlow()
        val attempt = flow.begin(ChannelsDownloadFlow.Request("original", autoSave = true))
        assertTrue(flow.requireLogin(attempt))
        val retry = flow.resume()!!
        assertEquals("original", retry.text)
        assertTrue(retry.autoSave)
        assertTrue(retry.afterLogin)
        assertNull(flow.resume())
        assertFalse(flow.requireLogin(flow.begin(retry)))
    }
    @Test fun `cancel dismiss and new attempts invalidate old results`() {
        val flow = ChannelsDownloadFlow()
        val first = flow.begin(ChannelsDownloadFlow.Request("a"))
        flow.requireLogin(first)
        flow.cancel()
        assertFalse(flow.isCurrent(first))
        assertNull(flow.resume())
        assertFalse(flow.requireLogin(first))
        val second = flow.begin(ChannelsDownloadFlow.Request("b"))
        assertTrue(flow.isCurrent(second))
    }
}
