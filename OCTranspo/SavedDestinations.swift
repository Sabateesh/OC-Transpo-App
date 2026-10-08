import MapKit
import Observation

@MainActor @Observable
final class SavedDestinations {
    static let shared = SavedDestinations()
    enum Slot: String, CaseIterable, Identifiable, Codable {
        case home = "Home", work = "Work"
        var id: String { rawValue }
        var symbol: String { self == .home ? "house.fill" : "briefcase.fill" }
    }
    struct Place: Codable {
        let title: String
        let address: String
        let latitude: Double
        let longitude: Double
        var destination: Destination {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: latitude, longitude: longitude)))
            item.name = title
            return Destination(item: item)
        }
    }
    private(set) var places: [String: Place]
    @ObservationIgnored private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        places = defaults.data(forKey: "savedDestinations").flatMap { try? JSONDecoder().decode([String: Place].self, from: $0) } ?? [:]
    }
    func place(_ slot: Slot) -> Place? { places[slot.rawValue] }
    func save(_ destination: Destination, as slot: Slot) {
        let point = destination.item.placemark.coordinate
        places[slot.rawValue] = Place(title: destination.title, address: destination.subtitle, latitude: point.latitude, longitude: point.longitude)
        persist()
    }
    func remove(_ slot: Slot) { places.removeValue(forKey: slot.rawValue); persist() }
    private func persist() { defaults.set(try? JSONEncoder().encode(places), forKey: "savedDestinations") }
}
