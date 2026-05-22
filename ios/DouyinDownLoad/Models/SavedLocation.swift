import Foundation

struct SavedLocation: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var createdAt: Date

    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
    }

    var coordinateText: String {
        String(format: "%.6f,%.6f", latitude, longitude)
    }
}
