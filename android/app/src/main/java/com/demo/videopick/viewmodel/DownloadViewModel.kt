package com.demo.videopick.viewmodel

import android.app.Application
import android.content.ClipboardManager
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.viewModelScope
import com.demo.videopick.clipboard.ClipboardAutoDownloadCandidate
import com.demo.videopick.data.model.MediaType
import com.demo.videopick.data.model.VideoInfo
import com.demo.videopick.data.repository.DownloadRepository
import com.demo.videopick.channels.ChannelsDownloadFlow
import com.demo.videopick.channels.ChannelsPendingLogin
import com.demo.videopick.channels.ChannelsLoginRequired
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.update
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val CLIPBOARD_SCAN_INTERVAL_MS = 4_000L

enum class ClipboardAutomationState {
    IDLE,
    WATCHING,
    DETECTING,
    DOWNLOADING,
    SAVING,
    SAVED,
    FAILED,
}

data class UiState(
    val inputText: String = "",
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val successMessage: String? = null,
    val videoInfo: VideoInfo? = null,
    val showPreview: Boolean = false,
    val downloadProgress: Float? = null,
    val showYuanbaoLogin: Boolean = false,
    val clipboardHint: String? = null,
    val isClipboardAutoDownloadEnabled: Boolean = true,
    val clipboardAutomationState: ClipboardAutomationState = ClipboardAutomationState.WATCHING,
)

class DownloadViewModel(application: Application, savedStateHandle: SavedStateHandle) : AndroidViewModel(application) {

    private val repository = DownloadRepository(application)
    private val pendingLogin = ChannelsPendingLogin(savedStateHandle)
    private val _state = MutableStateFlow(UiState(inputText = pendingLogin.text, showYuanbaoLogin = pendingLogin.waiting))
    val state: StateFlow<UiState> = _state.asStateFlow()

    private val channelsFlow = ChannelsDownloadFlow()
    private var downloadJob: Job? = null
    private var lastClipboardContent: String? = null
    private var lastHandledClipboardFingerprint: String? = null
    private var clipboardHintDismissJob: Job? = null
    private var clipboardMonitorJob: Job? = null

    fun updateInput(text: String) {
        _state.value = _state.value.copy(inputText = text)
    }

    fun clearInput() {
        cancelDownload()
        _state.value = UiState(
            isClipboardAutoDownloadEnabled = _state.value.isClipboardAutoDownloadEnabled,
            clipboardAutomationState = if (_state.value.isClipboardAutoDownloadEnabled) {
                ClipboardAutomationState.WATCHING
            } else {
                ClipboardAutomationState.IDLE
            },
        )
    }

    fun processInput() {
        if (_state.value.isLoading || _state.value.showYuanbaoLogin) return
        val text = _state.value.inputText.trim()
        if (text.isEmpty()) {
            _state.value = _state.value.copy(errorMessage = "请输入分享链接")
            return
        }
        startDownload(ChannelsDownloadFlow.Request(text))
    }

    fun cancelDownload() {
        pendingLogin.clear()
        channelsFlow.cancel()
        downloadJob?.cancel()
        downloadJob = null
        _state.update { it.copy(isLoading = false, downloadProgress = null, showYuanbaoLogin = false) }
    }

    fun yuanbaoLoginFinished(success: Boolean) {
        val pending = if (success) channelsFlow.resume() ?: pendingLogin.consume() else null
        pendingLogin.clear()
        _state.update { it.copy(showYuanbaoLogin = false) }
        if (pending != null) startDownload(pending) else cancelDownload()
    }

    fun requestYuanbaoLogin() {
        cancelDownload()
        pendingLogin.save(null)
        _state.update { it.copy(showYuanbaoLogin = true) }
    }

    private fun startDownload(request: ChannelsDownloadFlow.Request) {
        pendingLogin.clear()
        downloadJob?.cancel()
        val attempt = channelsFlow.begin(request)
        _state.update { it.copy(inputText = request.text, isLoading = true, showYuanbaoLogin = false) }
        downloadJob = viewModelScope.launch { download(attempt) }
    }

    private suspend fun download(attempt: ChannelsDownloadFlow.Attempt) {
        if (!channelsFlow.isCurrent(attempt)) return
        coroutineContext.ensureActive()
        val request = attempt.request
        _state.update { it.copy(isLoading = true, errorMessage = null, successMessage = null,
            videoInfo = null, showPreview = false, downloadProgress = null,
            clipboardAutomationState = ClipboardAutomationState.DOWNLOADING) }
        try {
            val info = withContext(Dispatchers.IO) {
                repository.parseAndDownload(request.text) { progress ->
                    _state.update { if (channelsFlow.isCurrent(attempt)) it.copy(downloadProgress = progress) else it }
                }
            }
            coroutineContext.ensureActive()
            if (!channelsFlow.isCurrent(attempt)) return
            _state.update { it.copy(videoInfo = info, showPreview = true,
                clipboardAutomationState = if (it.isClipboardAutoDownloadEnabled) ClipboardAutomationState.WATCHING else ClipboardAutomationState.IDLE) }
            if (request.autoSave) {
                _state.update { it.copy(clipboardAutomationState = ClipboardAutomationState.SAVING) }
                val msg = withContext(Dispatchers.IO) { saveResolvedMedia(info) }
                if (!channelsFlow.isCurrent(attempt)) return
                _state.update { it.copy(successMessage = msg, clipboardAutomationState = ClipboardAutomationState.SAVED) }
                showClipboardHint("已自动下载并保存到相册")
            }
        } catch (e: CancellationException) { throw e }
        catch (e: Exception) {
            if (!channelsFlow.isCurrent(attempt)) return
            if (e is ChannelsLoginRequired && channelsFlow.requireLogin(attempt)) {
                pendingLogin.save(request)
                _state.update { it.copy(showYuanbaoLogin = true, clipboardAutomationState = ClipboardAutomationState.WATCHING) }
            } else {
                val message = if (e is ChannelsLoginRequired) "元宝仍无法解析此视频，请稍后重试或在设置中重新登录。" else e.message ?: "下载失败"
                _state.update { it.copy(errorMessage = message, clipboardAutomationState = ClipboardAutomationState.FAILED) }
            }
        } finally {
            if (channelsFlow.isCurrent(attempt)) _state.update { it.copy(isLoading = false, downloadProgress = null) }
        }
    }

    fun startClipboardAutoDownloadIfNeeded(reason: String = "自动启动") {
        if (!_state.value.isClipboardAutoDownloadEnabled) {
            _state.value = _state.value.copy(
                isClipboardAutoDownloadEnabled = true,
                clipboardAutomationState = ClipboardAutomationState.DETECTING,
            )
        }
        beginClipboardMonitoring()
        scheduleClipboardScan(reason)
    }

    fun stopClipboardAutoDownload() {
        cancelDownload()
        clipboardMonitorJob?.cancel()
        clipboardMonitorJob = null
        downloadJob?.cancel()
        downloadJob = null
        _state.value = _state.value.copy(
            isClipboardAutoDownloadEnabled = false,
            clipboardAutomationState = ClipboardAutomationState.IDLE,
            isLoading = false,
            downloadProgress = null,
        )
        showClipboardHint("剪贴板雷达已关闭")
    }

    /** 前台切换时自动扫描剪贴板，若内容变化则直接下载并保存。 */
    fun checkClipboardOnForeground() {
        startClipboardAutoDownloadIfNeeded(reason = "前台唤醒")
    }

    private fun beginClipboardMonitoring() {
        if (clipboardMonitorJob != null) return
        clipboardMonitorJob = viewModelScope.launch {
            while (true) {
                delay(CLIPBOARD_SCAN_INTERVAL_MS)
                if (_state.value.isClipboardAutoDownloadEnabled && !_state.value.isLoading) {
                    scanClipboardForAutoDownload(reason = "定时扫描")
                }
            }
        }
    }

    private fun scheduleClipboardScan(reason: String) {
        viewModelScope.launch {
            scanClipboardForAutoDownload(reason)
        }
    }

    private fun scanClipboardForAutoDownload(reason: String) {
        if (!_state.value.isClipboardAutoDownloadEnabled || _state.value.isLoading || _state.value.showYuanbaoLogin) return

        // AC13: 首次（cache 为 null）时把已有 inputText 同步进 cache，避免 share intent 等预填导致重复触发
        if (lastClipboardContent == null && _state.value.inputText.isNotEmpty()) {
            lastClipboardContent = _state.value.inputText
        }

        _state.value = _state.value.copy(clipboardAutomationState = ClipboardAutomationState.DETECTING)
        val context = getApplication<Application>().applicationContext
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val primaryClip = clipboard.primaryClip ?: run {
            markClipboardWatching()
            return
        }
        if (primaryClip.itemCount == 0) {
            markClipboardWatching()
            return
        }
        val clipboardString = primaryClip.getItemAt(0).coerceToText(context).toString()

        val candidate = ClipboardAutoDownloadCandidate.resolve(
            text = clipboardString,
            lastHandledFingerprint = lastHandledClipboardFingerprint,
        ) ?: run {
            markClipboardWatching()
            return
        }

        lastClipboardContent = candidate.text
        lastHandledClipboardFingerprint = candidate.fingerprint
        _state.value = _state.value.copy(inputText = candidate.text)
        showClipboardHint("${reason}捕获到新链接，正在自动下载并保存")

        startDownload(ChannelsDownloadFlow.Request(candidate.text, autoSave = true))
    }

    private fun markClipboardWatching() {
        if (_state.value.isClipboardAutoDownloadEnabled && !_state.value.isLoading) {
            _state.value = _state.value.copy(clipboardAutomationState = ClipboardAutomationState.WATCHING)
        }
    }

    private fun showClipboardHint(message: String) {
        // AC9: cancel-and-restart，不堆叠
        clipboardHintDismissJob?.cancel()
        _state.value = _state.value.copy(clipboardHint = message)
        clipboardHintDismissJob = viewModelScope.launch {
            delay(3000)
            _state.value = _state.value.copy(clipboardHint = null)
        }
    }

    fun saveMedia() {
        val info = _state.value.videoInfo ?: return
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, errorMessage = null, successMessage = null)
            try {
                val msg = withContext(Dispatchers.IO) {
                    saveResolvedMedia(info)
                }
                _state.value = _state.value.copy(successMessage = msg)
            } catch (e: Exception) {
                _state.value = _state.value.copy(errorMessage = e.message ?: "保存失败")
            } finally {
                _state.value = _state.value.copy(isLoading = false)
            }
        }
    }

    private fun saveResolvedMedia(info: VideoInfo): String {
        return when (info.mediaType) {
            MediaType.VIDEO -> {
                val path = info.localPath ?: throw Exception("没有可保存的视频")
                repository.saveVideoToGallery(path)
            }
            MediaType.IMAGES -> {
                if (info.localImagePaths.isEmpty()) throw Exception("没有可保存的图片")
                repository.saveImagesToGallery(info.localImagePaths)
            }
        }
    }

    override fun onCleared() {
        clipboardHintDismissJob?.cancel()
        clipboardMonitorJob?.cancel()
        downloadJob?.cancel()
        super.onCleared()
    }
}
