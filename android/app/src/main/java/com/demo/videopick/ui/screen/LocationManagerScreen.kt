package com.demo.videopick.ui.screen

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.demo.videopick.data.model.SavedLocation
import com.demo.videopick.data.repository.GpxAssetImporter
import com.demo.videopick.viewmodel.LocationManagerViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LocationManagerScreen(
    onBack: () -> Unit,
    onEdit: (SavedLocation?) -> Unit,
) {
    val vm: LocationManagerViewModel = viewModel()
    val locations by vm.locations.collectAsState()
    val running by vm.running.collectAsState()
    val activeId by vm.activeId.collectAsState()
    val context = LocalContext.current
    var showHelp by remember { mutableStateOf(false) }
    var pendingStart by remember { mutableStateOf<SavedLocation?>(null) }

    val requiredPermissions = remember {
        buildList {
            add(Manifest.permission.ACCESS_FINE_LOCATION)
            add(Manifest.permission.ACCESS_COARSE_LOCATION)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                add(Manifest.permission.POST_NOTIFICATIONS)
            }
        }.toTypedArray()
    }

    val permLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { granted ->
        val ok = granted[Manifest.permission.ACCESS_FINE_LOCATION] == true
        val target = pendingStart
        pendingStart = null
        if (!ok) {
            Toast.makeText(context, "缺少定位权限，无法启动模拟", Toast.LENGTH_SHORT).show()
            return@rememberLauncherForActivityResult
        }
        if (!vm.isMockLocationAppSelected()) {
            Toast.makeText(context, "请先在开发者选项中选中本 app 为模拟位置应用", Toast.LENGTH_LONG).show()
            return@rememberLauncherForActivityResult
        }
        target?.let { vm.startMock(it) }
    }

    fun requestStart(loc: SavedLocation) {
        val missing = requiredPermissions.any {
            ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing) {
            pendingStart = loc
            permLauncher.launch(requiredPermissions)
        } else {
            if (!vm.isMockLocationAppSelected()) {
                Toast.makeText(context, "请先在开发者选项中选中本 app 为模拟位置应用", Toast.LENGTH_LONG).show()
                return
            }
            vm.startMock(loc)
        }
    }

    LaunchedEffect(Unit) { vm.reload() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("坐标管家") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, null)
                    }
                },
                actions = {
                    IconButton(onClick = { onEdit(null) }) {
                        Icon(Icons.Default.Add, "新增")
                    }
                }
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Card {
                    Column(Modifier.padding(16.dp)) {
                        Text("使用前置", style = MaterialTheme.typography.titleSmall)
                        Spacer(Modifier.height(4.dp))
                        Text(
                            "1. 设置 → 关于手机 → 连点 7 次版本号开启「开发者选项」\n" +
                                "2. 开发者选项 → 选择模拟位置应用 → 选 VideoPick\n" +
                                "完成后点下方坐标项的 ▶ 即可全局生效。",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Spacer(Modifier.height(8.dp))
                        Row {
                            TextButton(onClick = {
                                runCatching {
                                    context.startActivity(
                                        Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
                                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    )
                                }.onFailure {
                                    context.startActivity(
                                        Intent(Settings.ACTION_DEVICE_INFO_SETTINGS)
                                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    )
                                }
                            }) { Text("打开开发者选项") }
                            TextButton(onClick = { showHelp = !showHelp }) {
                                Text(if (showHelp) "收起" else "查看预置坐标")
                            }
                        }
                        if (showHelp) {
                            Spacer(Modifier.height(4.dp))
                            GpxAssetImporter.presets.forEach { preset ->
                                AssistChip(
                                    onClick = { vm.importPreset(preset) },
                                    label = { Text("导入：${preset.displayName}") }
                                )
                            }
                        }
                    }
                }
            }

            if (running) {
                item {
                    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.tertiaryContainer)) {
                        Row(
                            Modifier.fillMaxWidth().padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text("正在模拟定位", style = MaterialTheme.typography.titleSmall)
                                val active = locations.firstOrNull { it.id == activeId }
                                Text(
                                    active?.name ?: "%.6f, %.6f".format(
                                        MockLocationServiceCurrentLat,
                                        MockLocationServiceCurrentLng,
                                    ),
                                    style = MaterialTheme.typography.bodySmall,
                                )
                            }
                            FilledTonalButton(onClick = { vm.stopMock() }) {
                                Icon(Icons.Default.Stop, null); Spacer(Modifier.width(4.dp)); Text("停止")
                            }
                        }
                    }
                }
            }

            if (locations.isEmpty()) {
                item {
                    Text(
                        "还没有保存坐标，点右上角 + 新增；或点上方「查看预置坐标」一键导入。",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            } else {
                items(locations, key = { it.id }) { loc ->
                    LocationRow(
                        location = loc,
                        active = loc.id == activeId && running,
                        onStart = { requestStart(loc) },
                        onStop = { vm.stopMock() },
                        onEdit = { onEdit(loc) },
                        onDelete = { vm.delete(loc.id) },
                    )
                }
            }
        }
    }
}

@Composable
private fun LocationRow(
    location: SavedLocation,
    active: Boolean,
    onStart: () -> Unit,
    onStop: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
) {
    Card {
        Row(
            Modifier.fillMaxWidth().padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(location.name, style = MaterialTheme.typography.titleMedium)
                Text(
                    location.coordinateText,
                    style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                )
            }
            if (active) {
                IconButton(onClick = onStop) { Icon(Icons.Default.Stop, "停止") }
            } else {
                IconButton(onClick = onStart) { Icon(Icons.Default.PlayArrow, "启动") }
            }
            IconButton(onClick = onEdit) { Icon(Icons.Default.Edit, "编辑") }
            IconButton(onClick = onDelete) { Icon(Icons.Default.Delete, "删除") }
        }
    }
}

private val MockLocationServiceCurrentLat: Double
    get() = com.demo.videopick.service.MockLocationService.CURRENT_LAT
private val MockLocationServiceCurrentLng: Double
    get() = com.demo.videopick.service.MockLocationService.CURRENT_LNG
