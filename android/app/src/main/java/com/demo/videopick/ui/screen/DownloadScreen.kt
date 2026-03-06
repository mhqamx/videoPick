package com.demo.videopick.ui.screen

import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.demo.videopick.data.model.MediaType
import com.demo.videopick.data.model.VideoInfo
import com.demo.videopick.ui.component.VideoPlayerView
import com.demo.videopick.viewmodel.DownloadViewModel
import com.demo.videopick.viewmodel.UiState
import java.io.File

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DownloadScreen(
    viewModel: DownloadViewModel,
    onNavigateToCookieSettings: () -> Unit,
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("短视频下载") },
                actions = {
                    IconButton(onClick = onNavigateToCookieSettings) {
                        Icon(Icons.Default.Settings, contentDescription = "Cookie 设置")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            HeaderSection()
            InputSection(state, viewModel, context)
            StatusSection(state, viewModel)
            if (state.showPreview && state.videoInfo != null) {
                PreviewSection(state.videoInfo!!, viewModel)
            }
        }
    }
}

@Composable
private fun HeaderSection() {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.padding(vertical = 8.dp),
    ) {
        Icon(
            Icons.Default.PlayCircle,
            contentDescription = null,
            modifier = Modifier.size(60.dp),
            tint = MaterialTheme.colorScheme.primary,
        )
        Text(
            "短视频无水印下载",
            style = MaterialTheme.typography.titleLarge,
        )
        Text(
            "支持抖音、TikTok、Instagram、X、B站、快手、小红书分享链接",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun InputSection(
    state: UiState,
    viewModel: DownloadViewModel,
    context: Context,
) {
    Card(
        shape = RoundedCornerShape(12.dp),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedTextField(
                value = state.inputText,
                onValueChange = { viewModel.updateInput(it) },
                placeholder = { Text("粘贴分享链接...") },
                modifier = Modifier.fillMaxWidth(),
                maxLines = 4,
                trailingIcon = {
                    if (state.inputText.isNotEmpty()) {
                        IconButton(onClick = { viewModel.clearInput() }) {
                            Icon(Icons.Default.Clear, "清除")
                        }
                    }
                },
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                OutlinedButton(
                    onClick = {
                        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        val clip = clipboard.primaryClip
                        if (clip != null && clip.itemCount > 0) {
                            val text = clip.getItemAt(0).text?.toString() ?: ""
                            viewModel.updateInput(text)
                        }
                    },
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.Default.ContentPaste, null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("粘贴")
                }

                Button(
                    onClick = { viewModel.processInput() },
                    modifier = Modifier.weight(1f),
                    enabled = state.inputText.isNotBlank() && !state.isLoading,
                ) {
                    Icon(Icons.Default.Download, null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("下载")
                }
            }
        }
    }
}

@Composable
private fun StatusSection(state: UiState, viewModel: DownloadViewModel) {
    state.errorMessage?.let { error ->
        Card(
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.errorContainer,
            ),
            shape = RoundedCornerShape(8.dp),
        ) {
            Row(
                modifier = Modifier.padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    Icons.Default.Warning,
                    null,
                    tint = MaterialTheme.colorScheme.error,
                    modifier = Modifier.size(20.dp),
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    error,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
        }
    }

    state.successMessage?.let { msg ->
        Card(
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.primaryContainer,
            ),
            shape = RoundedCornerShape(8.dp),
        ) {
            Row(
                modifier = Modifier.padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    Icons.Default.CheckCircle,
                    null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp),
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    msg,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }

    if (state.isLoading) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (state.downloadProgress != null) {
                LinearProgressIndicator(
                    progress = { state.downloadProgress },
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(
                    "下载中 ${(state.downloadProgress * 100).toInt()}%",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                CircularProgressIndicator(modifier = Modifier.size(32.dp))
                Text(
                    "解析中...",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            TextButton(
                onClick = { viewModel.cancelDownload() },
                colors = ButtonDefaults.textButtonColors(
                    contentColor = MaterialTheme.colorScheme.error,
                ),
            ) {
                Icon(Icons.Default.Close, null, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(4.dp))
                Text("取消")
            }
        }
    }
}

@Composable
private fun PreviewSection(videoInfo: VideoInfo, viewModel: DownloadViewModel) {
    var showFullscreen by remember { mutableStateOf(false) }
    var fullscreenIndex by remember { mutableIntStateOf(0) }

    Card(
        shape = RoundedCornerShape(12.dp),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = if (videoInfo.mediaType == MediaType.VIDEO) "视频信息" else "图文信息",
                style = MaterialTheme.typography.titleMedium,
            )

            videoInfo.title?.let { title ->
                Row {
                    Text("标题: ", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(title, style = MaterialTheme.typography.bodySmall, maxLines = 2)
                }
            }

            when (videoInfo.mediaType) {
                MediaType.VIDEO -> {
                    videoInfo.localPath?.let { path ->
                        VideoPlayerView(
                            uri = Uri.fromFile(File(path)),
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(300.dp)
                                .clip(RoundedCornerShape(12.dp)),
                        )
                    }
                }
                MediaType.IMAGES -> {
                    if (videoInfo.localImagePaths.isNotEmpty()) {
                        Text(
                            "共 ${videoInfo.localImagePaths.size} 张图片",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )

                        LazyVerticalGrid(
                            columns = GridCells.Adaptive(minSize = 80.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier.height(300.dp),
                        ) {
                            itemsIndexed(videoInfo.localImagePaths) { index, path ->
                                AsyncImage(
                                    model = File(path),
                                    contentDescription = "图片 ${index + 1}",
                                    contentScale = ContentScale.Crop,
                                    modifier = Modifier
                                        .aspectRatio(1f)
                                        .clip(RoundedCornerShape(8.dp))
                                        .clickable {
                                            fullscreenIndex = index
                                            showFullscreen = true
                                        },
                                )
                            }
                        }
                    }
                }
            }

            // Save button
            Button(
                onClick = { viewModel.saveMedia() },
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(10.dp),
            ) {
                Icon(Icons.Default.SaveAlt, null)
                Spacer(Modifier.width(8.dp))
                Text("保存到相册")
            }
        }
    }

    if (showFullscreen && videoInfo.localImagePaths.isNotEmpty()) {
        FullscreenImageScreen(
            imagePaths = videoInfo.localImagePaths,
            initialIndex = fullscreenIndex,
            onDismiss = { showFullscreen = false },
        )
    }
}
