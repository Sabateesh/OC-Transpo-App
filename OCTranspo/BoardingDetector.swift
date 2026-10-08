import CoreLocation
import Foundation

struct BoardingDetector {
    private var first: CLLocation?
    private var firstVehicle: CLLocation?
    private var lastTimestamp: Date?
    private var samples = 0
    mutating func reset() { self = BoardingDetector() }
    mutating func observe(_ fix: CLLocation, vehicle: Vehicle?, leg: JourneyLeg, now: Date) -> Bool {
        guard let vehicle, vehicle.tripID == leg.tripID,
              vehicle.serviceDate == leg.serviceDate || (vehicle.serviceDate == nil && leg.serviceDate == RoutingTimetable.dayKey(now)),
              let timestamp = vehicle.timestamp, abs(now.timeIntervalSince(timestamp)) <= 60,
              abs(now.timeIntervalSince(fix.timestamp)) <= 15, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 35,
              fix.speed >= 2.5, abs(now.timeIntervalSince(leg.departure)) <= 20 * 60,
              leg.followsShape, Self.distance(fix, to: leg.coordinates) < 65 else { reset(); return false }
        let position = CLLocation(latitude: vehicle.latitude, longitude: vehicle.longitude)
        guard fix.distance(from: position) < 100 else { reset(); return false }
        if let lastTimestamp, fix.timestamp.timeIntervalSince(lastTimestamp) < 5 { return false }
        if let lastTimestamp, fix.timestamp.timeIntervalSince(lastTimestamp) > 30 { reset() }
        if first == nil { first = fix; firstVehicle = position }
        lastTimestamp = fix.timestamp; samples += 1
        guard let first, let firstVehicle else { return false }
        let board = CLLocation(latitude: leg.board.latitude, longitude: leg.board.longitude)
        return samples >= 4 && fix.timestamp.timeIntervalSince(first.timestamp) >= 15 &&
            fix.distance(from: first) >= 100 && position.distance(from: firstVehicle) >= 80 && fix.distance(from: board) >= 120
    }
    static func distance(_ location: CLLocation, to points: [CLLocationCoordinate2D]) -> Double {
        guard points.count > 1 else { return .infinity }
        let c = location.coordinate, scale = cos(c.latitude * .pi / 180)
        var closest = Double.infinity
        for (a, b) in zip(points, points.dropFirst()) {
            let dx = (b.longitude - a.longitude) * scale, dy = b.latitude - a.latitude
            let t = max(0, min(1, ((c.longitude - a.longitude) * scale * dx + (c.latitude - a.latitude) * dy) / max(1e-15, dx * dx + dy * dy)))
            closest = min(closest, location.distance(from: CLLocation(latitude: a.latitude + t * dy, longitude: a.longitude + t * (b.longitude - a.longitude))))
        }
        return closest
    }
}
