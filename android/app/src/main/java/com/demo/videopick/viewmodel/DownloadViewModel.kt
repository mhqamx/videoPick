package com.demo.videopick.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.demo.videopick.data.model.MediaType
import com.demo.videopick.data.model.VideoInfo
import com.demo.videopick.data.repository.DownloadRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class UiState(
    val inputText: String = "",
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val successMessage: String? = null,
    val videoInfo: VideoInfo? = null,
    val showPreview: Boolean = false,
    val downloadProgress: Float? = null,
)

class DownloadViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = DownloadRepository(application)
    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()

    private var downloadJob: Job? = null

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
