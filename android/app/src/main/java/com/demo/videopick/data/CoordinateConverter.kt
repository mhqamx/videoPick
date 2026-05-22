package com.demo.videopick.data

import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

enum class CoordinateSystem(val displayName: String) {
    WGS84("WGS-84（GPS 原始）"),
    GCJ02("GCJ-02（高德 / 腾讯）"),
    BD09("BD-09（百度）");
}

object CoordinateConverter {
    private const val PI = 3.1415926535897932384626
    private const val A = 6378245.0
    private const val EE = 0.00669342162296594323
    private const val X_PI = PI * 3000.0 / 180.0

    data class LatLng(val lat: Double, val lng: Double)

    fun toWGS84(lat: Double, lng: Double, from: CoordinateSystem): LatLng = when (from) {
        CoordinateSystem.WGS84 -> LatLng(lat, lng)
        CoordinateSystem.GCJ02 -> gcj02ToWGS84(lat, lng)
        CoordinateSystem.BD09 -> {
            val g = bd09ToGCJ02(lat, lng); gcj02ToWGS84(g.lat, g.lng)
        }
    }

    fun fromWGS84(lat: Double, lng: Double, to: CoordinateSystem): LatLng = when (to) {
        CoordinateSystem.WGS84 -> LatLng(lat, lng)
        CoordinateSystem.GCJ02 -> wgs84ToGCJ02(lat, lng)
        CoordinateSystem.BD09 -> {
            val g = wgs84ToGCJ02(lat, lng); gcj02ToBD09(g.lat, g.lng)
        }
    }

    fun wgs84ToGCJ02(lat: Double, lng: Double): LatLng {
        if (!isInChina(lat, lng)) return LatLng(lat, lng)
        var dLat = transformLat(lng - 105.0, lat - 35.0)
        var dLng = transformLng(lng - 105.0, lat - 35.0)
        val radLat = lat / 180.0 * PI
        var magic = sin(radLat); magic = 1 - EE * magic * magic
        val sm = sqrt(magic)
        dLat = dLat * 180.0 / ((A * (1 - EE)) / (magic * sm) * PI)
        dLng = dLng * 180.0 / (A / sm * cos(radLat) * PI)
        return LatLng(lat + dLat, lng + dLng)
    }

    fun gcj02ToWGS84(lat: Double, lng: Double): LatLng {
        var wLat = lat; var wLng = lng
        repeat(8) {
            val f = wgs84ToGCJ02(wLat, wLng)
            wLat += lat - f.lat; wLng += lng - f.lng
        }
        return LatLng(wLat, wLng)
    }

    fun gcj02ToBD09(lat: Double, lng: Double): LatLng {
        val z = sqrt(lng * lng + lat * lat) + 0.00002 * sin(lat * X_PI)
        val theta = atan2(lat, lng) + 0.000003 * cos(lng * X_PI)
        return LatLng(z * sin(theta) + 0.006, z * cos(theta) + 0.0065)
    }

    fun bd09ToGCJ02(lat: Double, lng: Double): LatLng {
        val x = lng - 0.0065; val y = lat - 0.006
        val z = sqrt(x * x + y * y) - 0.00002 * sin(y * X_PI)
        val theta = atan2(y, x) - 0.000003 * cos(x * X_PI)
        return LatLng(z * sin(theta), z * cos(theta))
    }

    private fun isInChina(lat: Double, lng: Double): Boolean =
        lng in 72.004..137.8347 && lat in 0.8293..55.8271

    private fun transformLat(x: Double, y: Double): Double {
        var r = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(kotlin.math.abs(x))
        r += (20.0 * sin(6.0 * x * PI) + 20.0 * sin(2.0 * x * PI)) * 2.0 / 3.0
        r += (20.0 * sin(y * PI) + 40.0 * sin(y / 3.0 * PI)) * 2.0 / 3.0
        r += (160.0 * sin(y / 12.0 * PI) + 320.0 * sin(y * PI / 30.0)) * 2.0 / 3.0
        return r
    }

    private fun transformLng(x: Double, y: Double): Double {
        var r = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(kotlin.math.abs(x))
        r += (20.0 * sin(6.0 * x * PI) + 20.0 * sin(2.0 * x * PI)) * 2.0 / 3.0
        r += (20.0 * sin(x * PI) + 40.0 * sin(x / 3.0 * PI)) * 2.0 / 3.0
        r += (150.0 * sin(x / 12.0 * PI) + 300.0 * sin(x / 30.0 * PI)) * 2.0 / 3.0
        return r
    }
}
