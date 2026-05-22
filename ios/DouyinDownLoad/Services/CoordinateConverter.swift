import Foundation

enum CoordinateSystem: String, CaseIterable, Codable {
    case wgs84
    case gcj02
    case bd09

    var displayName: String {
        switch self {
        case .wgs84: return "WGS-84（GPS 原始 / Xcode）"
        case .gcj02: return "GCJ-02（高德 / 腾讯）"
        case .bd09:  return "BD-09（百度）"
        }
    }
}

enum CoordinateConverter {
    private static let pi = 3.1415926535897932384626
    private static let a  = 6378245.0
    private static let ee = 0.00669342162296594323
    private static let xPi = pi * 3000.0 / 180.0

    static func toWGS84(lat: Double, lng: Double, from system: CoordinateSystem) -> (lat: Double, lng: Double) {
        switch system {
        case .wgs84: return (lat, lng)
        case .gcj02: return gcj02ToWGS84(lat: lat, lng: lng)
        case .bd09:
            let g = bd09ToGCJ02(lat: lat, lng: lng)
            return gcj02ToWGS84(lat: g.lat, lng: g.lng)
        }
    }

    static func fromWGS84(lat: Double, lng: Double, to system: CoordinateSystem) -> (lat: Double, lng: Double) {
        switch system {
        case .wgs84: return (lat, lng)
        case .gcj02: return wgs84ToGCJ02(lat: lat, lng: lng)
        case .bd09:
            let g = wgs84ToGCJ02(lat: lat, lng: lng)
            return gcj02ToBD09(lat: g.lat, lng: g.lng)
        }
    }

    // MARK: - WGS84 ↔ GCJ02

    static func wgs84ToGCJ02(lat: Double, lng: Double) -> (lat: Double, lng: Double) {
        if !isInChina(lat: lat, lng: lng) { return (lat, lng) }
        var dLat = transformLat(x: lng - 105.0, y: lat - 35.0)
        var dLng = transformLng(x: lng - 105.0, y: lat - 35.0)
        let radLat = lat / 180.0 * pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * pi)
        dLng = (dLng * 180.0) / (a / sqrtMagic * cos(radLat) * pi)
        return (lat + dLat, lng + dLng)
    }

    static func gcj02ToWGS84(lat: Double, lng: Double) -> (lat: Double, lng: Double) {
        // 反向迭代逼近
        var wgsLat = lat
        var wgsLng = lng
        for _ in 0..<8 {
            let forward = wgs84ToGCJ02(lat: wgsLat, lng: wgsLng)
            wgsLat += lat - forward.lat
            wgsLng += lng - forward.lng
        }
        return (wgsLat, wgsLng)
    }

    // MARK: - GCJ02 ↔ BD09

    static func gcj02ToBD09(lat: Double, lng: Double) -> (lat: Double, lng: Double) {
        let z = sqrt(lng * lng + lat * lat) + 0.00002 * sin(lat * xPi)
        let theta = atan2(lat, lng) + 0.000003 * cos(lng * xPi)
        let bdLng = z * cos(theta) + 0.0065
        let bdLat = z * sin(theta) + 0.006
        return (bdLat, bdLng)
    }

    static func bd09ToGCJ02(lat: Double, lng: Double) -> (lat: Double, lng: Double) {
        let x = lng - 0.0065
        let y = lat - 0.006
        let z = sqrt(x * x + y * y) - 0.00002 * sin(y * xPi)
        let theta = atan2(y, x) - 0.000003 * cos(x * xPi)
        return (z * sin(theta), z * cos(theta))
    }

    // MARK: - Helpers

    private static func isInChina(lat: Double, lng: Double) -> Bool {
        // 粗粒度判定：中国大陆 + 港澳台范围内才偏移，境外保持 WGS-84
        return lng >= 72.004 && lng <= 137.8347 && lat >= 0.8293 && lat <= 55.8271
    }

    private static func transformLat(x: Double, y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * pi) + 40.0 * sin(y / 3.0 * pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * pi) + 320.0 * sin(y * pi / 30.0)) * 2.0 / 3.0
        return ret
    }

    private static func transformLng(x: Double, y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * pi) + 40.0 * sin(x / 3.0 * pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * pi) + 300.0 * sin(x / 30.0 * pi)) * 2.0 / 3.0
        return ret
    }
}
