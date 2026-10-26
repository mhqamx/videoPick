package com.demo.videopick.channels

/** Stores the exact request across login; generation invalidates late progress/results. */
class ChannelsDownloadFlow {
    data class Request(val text: String, val autoSave: Boolean = false, val afterLogin: Boolean = false)
    data class Attempt(val id: Long, val request: Request)
    @Volatile private var generation = 0L
    private var pending: Request? = null
    fun begin(request: Request): Attempt { pending = null; return Attempt(++generation, request) }
    fun isCurrent(attempt: Attempt) = generation == attempt.id
    fun requireLogin(attempt: Attempt): Boolean {
        if (!isCurrent(attempt) || attempt.request.afterLogin) return false
        pending = attempt.request
        return true
    }
    fun resume(): Request? = pending?.copy(afterLogin = true).also { pending = null }
    fun cancel() { generation++; pending = null }
}
