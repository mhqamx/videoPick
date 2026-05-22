package com.demo.videopick.ui.screen

import android.os.Bundle
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.viewmodel.compose.viewModel
import com.amap.api.maps.AMap
import com.amap.api.maps.CameraUpdateFactory
import com.amap.api.maps.MapView
import com.amap.api.maps.model.LatLng as AMapLatLng
import com.amap.api.maps.model.MarkerOptions
import com.demo.videopick.data.CoordinateConverter
import com.demo.videopick.data.CoordinateSystem
import com.demo.videopick.data.model.SavedLocation
import com.demo.videopick.viewmodel.LocationManagerViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LocationEditorScreen(
    original: SavedLocation?,
    onBack: () -> Unit,
) {
    val vm: LocationManagerViewModel = viewModel()

    var name by remember { mutableStateOf(original?.name ?: "") }
    var system by remember { mutableStateOf(CoordinateSystem.GCJ02) }
    val initialDisplay = remember(original, system) {
        original?.let {
            CoordinateConverter.fromWGS84(it.latitude, it.longitude, system)
        }
    }
    var latText by remember(original) { mutableStateOf(initialDisplay?.lat?.let { "%.6f".format(it) } ?: "") }
    var lngText by remember(original) { mutableStateOf(initialDisplay?.lng?.let { "%.6f".format(it) } ?: "") }

    // 地图选点（高德 SDK 输入/输出 GCJ-02）
    var mapView by remember { mutableStateOf<MapView?>(null) }
    val center = original?.let {
        val gcj = CoordinateConverter.wgs84ToGCJ02(it.latitude, it.longitude)
        AMapLatLng(gcj.lat, gcj.lng)
    } ?: AMapLatLng(38.988982, 121.590568) // 默认大连中南大厦 GCJ-02

    val isValid = name.isNotBlank() && latText.toDoubleOrNull() != null && lngText.toDoubleOrNull() != null
    val wgsPreview = remember(latText, lngText, system) {
        val lat = latText.toDoubleOrNull(); val lng = lngText.toDoubleOrNull()
        if (lat != null && lng != null) {
            val w = CoordinateConverter.toWGS84(lat, lng, system)
            "→ WGS-84: %.6f, %.6f".format(w.lat, w.lng)
        } else null
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (original == null) "新增坐标" else "编辑坐标") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, null)
                    }
                },
                actions = {
                    TextButton(
                        enabled = isValid,
                        onClick = {
                            val lat = latText.toDouble(); val lng = lngText.toDouble()
                            val w = CoordinateConverter.toWGS84(lat, lng, system)
                            vm.upsert(
                                SavedLocation(
                                    id = original?.id ?: java.util.UUID.randomUUID().toString(),
                                    name = name.trim(),
                                    latitude = w.lat,
                                    longitude = w.lng,
                                    createdAt = original?.createdAt ?: System.currentTimeMillis(),
                                )
                            )
                            onBack()
                        }
                    ) { Text("保存") }
                }
            )
        }
    ) { padding ->
        Column(
            Modifier.padding(padding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("名称") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            Text("输入坐标系", style = MaterialTheme.typography.labelMedium)
            SystemSelector(system = system, onSelect = { newSystem ->
                val lat = latText.toDoubleOrNull(); val lng = lngText.toDoubleOrNull()
                if (lat != null && lng != null) {
                    val w = CoordinateConverter.toWGS84(lat, lng, system)
                    val d = CoordinateConverter.fromWGS84(w.lat, w.lng, newSystem)
                    latText = "%.6f".format(d.lat); lngText = "%.6f".format(d.lng)
                }
                system = newSystem
            })

            OutlinedTextField(
                value = latText,
                onValueChange = { latText = it },
                label = { Text("纬度 lat") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = lngText,
                onValueChange = { lngText = it },
                label = { Text("经度 lng") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            wgsPreview?.let {
                Text(it, style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace))
            }

            Text("地图点选（高德，GCJ-02）", style = MaterialTheme.typography.labelMedium)
            AndroidView(
                modifier = Modifier.fillMaxWidth().height(280.dp),
                factory = { ctx ->
                    MapView(ctx).also { mv ->
                        mv.onCreate(Bundle())
                        mapView = mv
                        val map: AMap = mv.map
                        map.moveCamera(CameraUpdateFactory.newLatLngZoom(center, 16f))
                        map.addMarker(MarkerOptions().position(center).title(name.ifBlank { "目标" }))
                        map.setOnMapClickListener { p ->
                            // p 是 GCJ-02
                            map.clear()
                            map.addMarker(MarkerOptions().position(p).title(name.ifBlank { "目标" }))
                            // 把高德点击坐标按当前选择的输入系反算填入文本框
                            val w = CoordinateConverter.gcj02ToWGS84(p.latitude, p.longitude)
                            val d = CoordinateConverter.fromWGS84(w.lat, w.lng, system)
                            latText = "%.6f".format(d.lat); lngText = "%.6f".format(d.lng)
                        }
                    }
                },
            )

            DisposableEffect(Unit) {
                onDispose { mapView?.onDestroy() }
            }

            Text(
                "提示：高德地图未填写 API Key 时不显示瓦片，但坐标输入依然可用。\n" +
                    "保存时统一折算成 WGS-84 落库；模拟定位下发到 LocationManager 也是 WGS-84。",
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}

@Composable
private fun SystemSelector(system: CoordinateSystem, onSelect: (CoordinateSystem) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        CoordinateSystem.values().forEach { s ->
            FilterChip(
                selected = s == system,
                onClick = { onSelect(s) },
                label = { Text(s.displayName) },
            )
        }
    }
}
