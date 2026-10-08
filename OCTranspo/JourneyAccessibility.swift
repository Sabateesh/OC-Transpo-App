import Foundation

extension Journey {
    var accessibilitySummary: String {
        let trips = legs.map { $0.wheelchairAccessible ?? .unknown }
        if trips.contains(.inaccessible) { return "Includes a vehicle without wheelchair access" }
        if trips.contains(.unknown) { return "Vehicle accessibility unknown for some legs" }
        let stops = legs.flatMap { [$0.board.wheelchairBoarding ?? .unknown, $0.alight.wheelchairBoarding ?? .unknown] }
        if stops.contains(.inaccessible) { return "Vehicle accessible · A stop is marked inaccessible" }
        if stops.contains(.unknown) { return "Vehicles accessible · Stop access unknown · Walking path unverified" }
        return "Vehicles and stops marked accessible · Walking path unverified"
    }
}
