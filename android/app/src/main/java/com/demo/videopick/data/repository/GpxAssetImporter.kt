package com.demo.videopick.data.repository

import android.content.Context
import com.demo.videopick.data.model.SavedLocation

/**
 * 从 assets/gpx 目录读取预置 GPX 文件。简单单点 wpt 解析（regex），不依赖 XML 库。
 */
object GpxAssetImporter {

    data class Preset(val displayName: String, val assetPath: String)

    val presets = listOf(
        Preset("大连中南大厦", "gpx/dalian_zhongnan.gpx"),
    )

    fun load(context: Context, preset: Preset): SavedLocation? {
        return try {
            val xml = context.assets.open(preset.assetPath).bufferedReader().use { it.readText() }
            val lat = Regex("""lat="([0-9.\-]+)"""").find(xml)?.groupValues?.get(1)?.toDoubleOrNull()
            val lng = Regex("""lon="([0-9.\-]+)"""").find(xml)?.groupValues?.get(1)?.toDoubleOrNull()
            val name = Regex("""<name>([^<]+)</name>""").find(xml)?.groupValues?.get(1)
                ?: preset.displayName
            if (lat == null || lng == null) return null
            SavedLocation(name = name, latitude = lat, longitude = lng)
        } catch (_: Exception) {
            null
        }
    }
}
