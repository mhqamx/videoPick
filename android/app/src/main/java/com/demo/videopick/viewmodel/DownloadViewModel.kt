package com.demo.videopick.viewmodel

import android.app.Application
import android.content.ClipboardManager
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.demo.videopick.data.model.MediaType
import com.demo.videopick.data.model.VideoInfo
import com.demo.videopick.data.repository.DownloadRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val CLIPBOARD_HINT_TEXT = "已识别到剪贴板内容，已自动填入"

data class UiState(
    val inputText: String = "",
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val successMessage: String? = null,
    val videoInfo: VideoInfo? = null,
    val showPreview: Boolean = false,
    val downloadProgress: Float? = null,
    val clipboardHint: String? = null,
)

class DownloadViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = DownloadRepository(application)
    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()

    private var downloadJob: Job? = null
    private var lastClipboardContent: String? = null
    private var clipboardHintDismissJob: Job? = null

    fun updateInput(text: String) {
        _state.value = _state.value.copy(inputText = text)
    }

    fun clearInput() {
        _state.value = UiState()
    }

    fun processInput() {
        val text = _state.value.inputText.trim()
        if (text.isEmpty()) {
            _state.value = _state.value.copy(errorMessage = "请输入分享链接")
            return
        }
        downloadJob = viewModelScope.launch {
            download(text)
        }
    }

    fun cancelDownload() {
        downloadJob?.cancel()
        downloadJob = null
        _state.value = _state.value.copy(
            isLoading = false,
            downloadProgress = null,
        )
    }

    private suspend fun download(text: String) {
        _state.value = _state.value.copy(
            isLoading = true,
            errorMessage = null,
            successMessage = null,
            videoInfo = null,
            showPreview = false,
            downloadProgress = null,
        )

        try {
            val info = withContext(Dispatchers.IO) {
                repository.parseAndDownload(text) { progress ->
                    _state.value = _state.value.copy(downloadProgress = progress)
                }
            }
            _state.value = _state.value.copy(
                videoInfo = info,
                showPreview = true,
            )
        } catch (e: Exception) {
            _state.value = _state.value.copy(
                errorMessage = e.message ?: "未知错误",
            )
        } finally {
            _state.value = _state.value.copy(
                isLoading = false,
                downloadProgress = null,
            )
        }
    }

    /** Story 8.1.1: 前台切换时自动读取剪贴板，若内容变化则填入并提示。 */
    fun checkClipboardOnForeground() {
        // AC13: 首次（cache 为 null）时把已有 inputText 同步进 cache，避免 share intent 等预填导致重复触发
        if (lastClipboardContent == null && _state.value.inputText.isNotEmpty()) {
            lastClipboardContent = _state.value.inputText
        }

        val context = getApplication<Application>().applicationContext
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val primaryClip = clipboard.primaryClip ?: return
        if (primaryClip.itemCount == 0) return
        val clipboardString = primaryClip.getItemAt(0).coerceToText(context).toString()

        // AC3: 三条件 AND（非空 + 与缓存不同）
        if (clipboardString.isEmpty()) return
        if (clipboardString == lastClipboardContent) return

        // AC6: 缓存先更新；AC7: 替换 inputText
        lastClipboardContent = clipboardString
        _state.value = _state.value.copy(inputText = clipboardString)
        showClipboardHint(CLIPBOARD_HINT_TEXT)
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
                    when (info.mediaType) {
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
                _state.value = _state.value.copy(successMessage = msg)
            } catch (e: Exception) {
                _state.value = _state.value.copy(errorMessage = e.message ?: "保存失败")
            } finally {
                _state.value = _state.value.copy(isLoading = false)
            }
        }
    }
}
