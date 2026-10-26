package com.demo.videopick.channels

import androidx.lifecycle.SavedStateHandle

/** Saved instance state contains only the pending share request, never account credentials. */
class ChannelsPendingLogin(private val state: SavedStateHandle) {
    val waiting: Boolean get() = state["channels.login.waiting"] ?: false
    val text: String get() = state["channels.login.text"] ?: ""
    fun save(request: ChannelsDownloadFlow.Request?) {
        state["channels.login.waiting"] = true
        state["channels.login.text"] = request?.text
        state["channels.login.autoSave"] = request?.autoSave ?: false
    }
    fun consume(): ChannelsDownloadFlow.Request? {
        val request = if (waiting && text.isNotBlank()) ChannelsDownloadFlow.Request(
            text = text, autoSave = state["channels.login.autoSave"] ?: false, afterLogin = true,
        ) else null
        clear()
        return request
    }
    fun clear() {
        state.remove<Boolean>("channels.login.waiting")
        state.remove<String>("channels.login.text")
        state.remove<Boolean>("channels.login.autoSave")
    }
}
