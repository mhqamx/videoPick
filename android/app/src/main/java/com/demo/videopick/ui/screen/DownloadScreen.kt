package com.demo.videopick.ui.screen

import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.SaveAlt
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.demo.videopick.data.model.MediaType
import com.demo.videopick.data.model.VideoInfo
import com.demo.videopick.ui.component.VideoPlayerView
import com.demo.videopick.viewmodel.ClipboardAutomationState
import com.demo.videopick.viewmodel.DownloadViewModel
import com.demo.videopick.viewmodel.UiState
import java.io.File

private val Ink = Color(0xFF071017)
private val Panel = Color(0xFF101B24)
private val PanelSoft = Color(0xFF172635)
private val Cyan = Color(0xFF43E6FF)
private val Lime = Color(0xFFA9FF68)
private val Amber = Color(0xFFFFC857)
private val Rose = Color(0xFFFF5C8A)
private val TextPrimary = Color(0xFFEAF7FF)
private val TextSecondary = Color(0xFF92A7B8)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DownloadScreen(
    viewModel: DownloadViewModel,
    onNavigateToCookieSettings: () -> Unit,
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current

    Scaffold(
        containerColor = Ink,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        "VideoPick",
                        color = TextPrimary,
                        fontWeight = FontWeight.SemiBold,
                    )
                },
                actions = {
                    IconButton(onClick = onNavigateToCookieSettings) {
                        Icon(Icons.Default.Settings, contentDescription = "Cookie 设置", tint = TextPrimary)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Ink),
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        listOf(Color(0xFF061018), Color(0xFF0D1720), Color(0xFF091018)),
                    ),
                )
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            RadarPanel(state = state, viewModel = viewModel)
            InputPanel(state = state, viewModel = viewModel, context = context)
            StatusPanel(state = state, viewModel = viewModel)
            if (state.showPreview && state.videoInfo != null) {
                PreviewSection(videoInfo = state.videoInfo, viewModel = viewModel)
            }
        }
    }
}

@Composable
private fun RadarPanel(state: UiState, viewModel: DownloadViewModel) {
    val status = automationStatus(state)
    Surface(
        color = Panel,
        shape = RoundedCornerShape(18.dp),
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, Color(0xFF244558), RoundedCornerShape(18.dp)),
    ) {
        Row(
            modifier = Modifier.padding(18.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            RadarGlyph(color = status.color, active = state.isClipboardAutoDownloadEnabled)
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("剪贴板雷达", color = TextSecondary, style = MaterialTheme.typography.labelMedium)
                Text(status.title, color = TextPrimary, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Text(status.detail, color = TextSecondary, style = MaterialTheme.typography.bodySmall)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TechChip("MODE", if (state.isClipboardAutoDownloadEnabled) "AUTO" else "OFF", Cyan)
                    TechChip("SAVE", "相册", Lime)
                    TechChip("视频号", "已支持", Amber)
                }
            }
            IconButton(
                onClick = {
                    if (state.isClipboardAutoDownloadEnabled) {
                        viewModel.stopClipboardAutoDownload()
                    } else {
                        viewModel.startClipboardAutoDownloadIfNeeded(reason = "手动恢复")
                    }
                },
            ) {
                Icon(
                    imageVector = if (state.isClipboardAutoDownloadEnabled) Icons.Default.Close else Icons.Default.PlayCircle,
                    contentDescription = if (state.isClipboardAutoDownloadEnabled) "关闭雷达" else "恢复雷达",
                    tint = TextPrimary,
                )
            }
        }
    }
}

@Composable
private fun RadarGlyph(color: Color, active: Boolean) {
    Box(contentAlignment = Alignment.Center, modifier = Modifier.size(82.dp)) {
        Box(
            modifier = Modifier
                .size(82.dp)
                .clip(CircleShape)
                .background(color.copy(alpha = if (active) 0.16f else 0.08f))
                .border(1.dp, color.copy(alpha = 0.55f), CircleShape),
        )
        Box(
            modifier = Modifier
                .size(54.dp)
                .clip(CircleShape)
                .border(1.dp, color.copy(alpha = 0.75f), CircleShape),
        )
        Box(
            modifier = Modifier
                .size(18.dp)
                .clip(CircleShape)
                .background(color),
        )
    }
}

@Composable
private fun TechChip(label: String, value: String, color: Color) {
    Surface(color = color.copy(alpha = 0.12f), shape = RoundedCornerShape(6.dp)) {
        Row(modifier = Modifier.padding(horizontal = 8.dp, vertical = 5.dp), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(label, color = color, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold)
            Text(value, color = TextPrimary, style = MaterialTheme.typography.labelSmall)
        }
    }
}

@Composable
private fun InputPanel(
    state: UiState,
    viewModel: DownloadViewModel,
    context: Context,
) {
    Surface(color = PanelSoft, shape = RoundedCornerShape(16.dp), modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("支持视频号分享链接，首次下载时登录元宝即可。", color = TextSecondary, style = MaterialTheme.typography.bodySmall)
            OutlinedTextField(
                value = state.inputText,
                onValueChange = { viewModel.updateInput(it) },
                placeholder = { Text("复制分享链接后，雷达会自动捕获") },
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

            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                TextButton(
                    onClick = {
                        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        val clip = clipboard.primaryClip
                        if (clip != null && clip.itemCount > 0) {
                            viewModel.updateInput(clip.getItemAt(0).coerceToText(context).toString())
                        }
                    },
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.textButtonColors(contentColor = Cyan),
                ) {
                    Icon(Icons.Default.ContentPaste, null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("粘贴")
                }

                Button(
                    onClick = { viewModel.processInput() },
                    modifier = Modifier.weight(1f),
                    enabled = state.inputText.isNotBlank() && !state.isLoading,
                    colors = ButtonDefaults.buttonColors(containerColor = Cyan, contentColor = Color(0xFF06202A)),
                    shape = RoundedCornerShape(10.dp),
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
private fun StatusPanel(state: UiState, viewModel: DownloadViewModel) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        state.clipboardHint?.let {
            SignalCard(text = it, color = Cyan, icon = Icons.Default.ContentPaste)
        }
        state.errorMessage?.let {
            SignalCard(text = it, color = Rose, icon = Icons.Default.Warning)
        }
        state.successMessage?.let {
            SignalCard(text = it, color = Lime, icon = Icons.Default.CheckCircle)
        }
        if (state.isLoading) {
            Surface(color = Panel, shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    val progress = state.downloadProgress
                    Text(
                        if (progress != null) "下载中 ${(progress * 100).toInt()}%" else "解析中",
                        color = TextPrimary,
                        fontWeight = FontWeight.SemiBold,
                    )
                    LinearProgressIndicator(
                        progress = { progress ?: 0.18f },
                        modifier = Modifier.fillMaxWidth(),
                        color = Cyan,
                        trackColor = Color(0xFF233544),
                    )
                    TextButton(
                        onClick = { viewModel.cancelDownload() },
                        colors = ButtonDefaults.textButtonColors(contentColor = Rose),
                    ) {
                        Icon(Icons.Default.Close, null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(4.dp))
                        Text("取消")
                    }
                }
            }
        }
    }
}

@Composable
private fun SignalCard(text: String, color: Color, icon: ImageVector) {
    Surface(color = color.copy(alpha = 0.12f), shape = RoundedCornerShape(12.dp), modifier = Modifier.fillMaxWidth()) {
        Row(modifier = Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, tint = color, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(8.dp))
            Text(text, color = TextPrimary, style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
private fun PreviewSection(videoInfo: VideoInfo?, viewModel: DownloadViewModel) {
    if (videoInfo == null) return
    var showFullscreen by remember { mutableStateOf(false) }
    var fullscreenIndex by remember { mutableIntStateOf(0) }

    Surface(color = Panel, shape = RoundedCornerShape(16.dp), modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Default.PlayCircle, null, tint = Cyan)
                Text(
                    text = if (videoInfo.mediaType == MediaType.VIDEO) "视频就绪" else "图文就绪",
                    color = TextPrimary,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                )
            }

            videoInfo.title?.takeIf { it.isNotBlank() }?.let { title ->
                Text(title, color = TextSecondary, style = MaterialTheme.typography.bodySmall, maxLines = 2)
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
                            color = TextSecondary,
                            style = MaterialTheme.typography.bodySmall,
                        )
                        LazyVerticalGrid(
                            columns = GridCells.Adaptive(minSize = 82.dp),
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

            Button(
                onClick = { viewModel.saveMedia() },
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(10.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Lime, contentColor = Color(0xFF102000)),
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

private data class AutomationStatus(
    val title: String,
    val detail: String,
    val color: Color,
)

private fun automationStatus(state: UiState): AutomationStatus {
    return when (state.clipboardAutomationState) {
        ClipboardAutomationState.IDLE -> AutomationStatus("雷达已关闭", "手动粘贴后仍可下载", TextSecondary)
        ClipboardAutomationState.WATCHING -> AutomationStatus("正在监听剪贴板", "复制分享链接后会自动下载并保存", Cyan)
        ClipboardAutomationState.DETECTING -> AutomationStatus("正在扫描", "确认剪贴板里是否有新链接", Amber)
        ClipboardAutomationState.DOWNLOADING -> AutomationStatus("正在下载", "媒体文件进入本地缓存", Cyan)
        ClipboardAutomationState.SAVING -> AutomationStatus("正在保存", "写入系统相册/媒体库", Amber)
        ClipboardAutomationState.SAVED -> AutomationStatus("已保存", "相册里可以直接查看", Lime)
        ClipboardAutomationState.FAILED -> AutomationStatus("任务异常", "查看下方提示后重试", Rose)
    }
}
