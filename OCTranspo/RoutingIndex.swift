import CoreLocation
import Foundation

final class RoutingGeometry: @unchecked Sendable {
    struct Cell: Hashable { let x: Int; let y: Int }
    let points: [CLLocation]
    let grid: [Cell: [Int]]
    let transfers: [[(stop: Int, distance: Double)]]
    init(stops: [Stop]) {
        let points = stops.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        var grid: [Cell: [Int]] = [:]
        for i in points.indices { grid[Self.cell(points[i].coordinate), default: []].append(i) }
        self.points = points; self.grid = grid
        transfers = points.indices.map { i in
            let cell = Self.cell(points[i].coordinate)
            var result: [(Int, Double)] = []
            for dx in -1...1 { for dy in -1...1 {
                for j in grid[Cell(x: cell.x + dx, y: cell.y + dy)] ?? [] {
                    let distance = points[i].distance(from: points[j])
                    if distance <= 450 { result.append((j, distance)) }
                }
            } }
            return result
        }
    }
    static func cell(_ c: CLLocationCoordinate2D) -> Cell { .init(x: Int(floor(c.longitude / 0.01)), y: Int(floor(c.latitude / 0.01))) }
    func near(_ point: CLLocation, radius: Double) -> [(Int, Double)] {
        let cell = Self.cell(point.coordinate)
        let dx = Int(ceil(radius / (111_000 * max(0.1, cos(point.coordinate.latitude * .pi / 180)) * 0.01)))
        let dy = Int(ceil(radius / 1110))
        var result: [(Int, Double)] = []
        for x in -dx...dx { for y in -dy...dy {
            for i in grid[Cell(x: cell.x + x, y: cell.y + y)] ?? [] {
                let distance = point.distance(from: points[i])
                if distance <= radius { result.append((i, distance)) }
            }
        } }
        return result.sorted { $0.0 < $1.0 }
    }
}

final class RoutingIndex: @unchecked Sendable {
    struct Departure { let trip: Int; let time: Date }
    let geometry: RoutingGeometry
    let departures: [[Departure]]
    let tripKeys: [String]
    init(_ timetable: RoutingTimetable, geometry: RoutingGeometry? = nil) {
        self.geometry = geometry ?? RoutingGeometry(stops: timetable.stops)
        tripKeys = timetable.trips.map { Self.key($0) }
        var departures = Array(repeating: [Departure](), count: timetable.stops.count)
        for (index, trip) in timetable.trips.enumerated() {
            for call in trip.calls where call.pickup { departures[call.stop].append(.init(trip: index, time: call.departure)) }
        }
        self.departures = departures.map { $0.sorted { $0.time < $1.time } }
    }
    static func key(_ trip: RoutingTrip) -> String { trip.id + ":" + trip.serviceDate }
    func candidates(from stops: [(Int, Date)], live: Bool) -> [Int] {
        var trips: Set<Int> = []
        for (stop, time) in stops {
            let calls = departures[stop]
            var lower = 0, upper = calls.count
            if !live {
                while lower < upper {
                    let mid = (lower + upper) / 2
                    if calls[mid].time < time { lower = mid + 1 } else { upper = mid }
                }
            }
            for call in calls[lower...] { trips.insert(call.trip) }
        }
        return trips.sorted()
    }
}

struct RoutingNetwork {
    let timetable: RoutingTimetable
    let index: RoutingIndex
    let version: String
}
