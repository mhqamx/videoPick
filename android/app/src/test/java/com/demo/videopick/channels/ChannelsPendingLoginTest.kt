package com.demo.videopick.channels

import androidx.lifecycle.SavedStateHandle
import org.junit.Assert.*
import org.junit.Test

class ChannelsPendingLoginTest {
    @Test fun `recreated activity restores original link and automatic save once`() {
        val state = SavedStateHandle()
        ChannelsPendingLogin(state).save(ChannelsDownloadFlow.Request("original share", autoSave = true))
        val restored = SavedStateHandle(state.keys().associateWith { state.get<Any?>(it) })
        val login = ChannelsPendingLogin(restored)
        assertTrue(login.waiting)
        val request = login.consume()
        assertNotNull(request)
        assertEquals("original share", request!!.text)
        assertTrue(request.autoSave)
        assertTrue(request.afterLogin)
        assertNull(login.consume())
        assertFalse(login.waiting)
    }
    @Test fun `cancelled or settings-only login must never restore a download`() {
        val state = SavedStateHandle()
        val login = ChannelsPendingLogin(state)
        login.save(ChannelsDownloadFlow.Request("cancelled"))
        login.clear()
        assertNull(ChannelsPendingLogin(state).consume())
        login.save(null)
        assertTrue(login.waiting)
        assertNull(ChannelsPendingLogin(state).consume())
        assertFalse(login.waiting)
    }
}
