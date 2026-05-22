import Foundation

enum GPXExporter {
    static func makeGPX(for location: SavedLocation) -> String {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
        let escapedName = escapeXML(location.name)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="DouyinDownLoad" xmlns="http://www.topografix.com/GPX/1/1">
          <wpt lat="\(location.latitude)" lon="\(location.longitude)">
            <name>\(escapedName)</name>
            <time>\(timestamp)</time>
          </wpt>
        </gpx>
        """
    }

    static func writeToTempFile(_ location: SavedLocation) throws -> URL {
        let xml = makeGPX(for: location)
        let safeName = location.name.replacingOccurrences(
            of: "[^A-Za-z0-9一-龥_-]",
            with: "_",
            options: .regularExpression
        )
        let fileName = (safeName.isEmpty ? "location" : safeName) + ".gpx"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try xml.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    private static func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
