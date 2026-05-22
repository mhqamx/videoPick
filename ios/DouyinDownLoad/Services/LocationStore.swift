import Foundation

nonisolated final class LocationStore: @unchecked Sendable {
    static let shared = LocationStore()

    private let defaults = UserDefaults.standard
    private let storageKey = "saved_locations_v1"

    private init() {}

    func all() -> [SavedLocation] {
        guard let data = defaults.data(forKey: storageKey),
              let list = try? JSONDecoder().decode([SavedLocation].self, from: data) else {
            return []
        }
        return list.sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ location: SavedLocation) {
        var list = all()
        if let idx = list.firstIndex(where: { $0.id == location.id }) {
            list[idx] = location
        } else {
            list.append(location)
        }
        persist(list)
    }

    func delete(id: UUID) {
        var list = all()
        list.removeAll { $0.id == id }
        persist(list)
    }

    private func persist(_ list: [SavedLocation]) {
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
