import Foundation
import Combine

@MainActor
final class LocationManagerViewModel: ObservableObject {
    @Published var locations: [SavedLocation] = []

    private let store = LocationStore.shared

    init() {
        reload()
    }

    func reload() {
        locations = store.all()
    }

    func upsert(_ location: SavedLocation) {
        store.save(location)
        reload()
    }

    func delete(at offsets: IndexSet) {
        for idx in offsets {
            store.delete(id: locations[idx].id)
        }
        reload()
    }

    func delete(id: UUID) {
        store.delete(id: id)
        reload()
    }
}
