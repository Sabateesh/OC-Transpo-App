#if DEBUG
import MapKit

@MainActor enum JourneyPreview {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--journey-preview") }
    static func start(track: Bool = false) {
        let now = Date.now
        let nearing = ProcessInfo.processInfo.arguments.contains("--get-off")
        let riding = nearing || ProcessInfo.processInfo.arguments.contains("--riding")
        let stops = [
            Stop(code: "Rideau", name: "Rideau", latitude: 45.4255, longitude: -75.6901, ids: ["preview-a"]),
            Stop(code: "Parliament", name: "Parliament", latitude: 45.4215, longitude: -75.6992, ids: ["preview-b"]),
            Stop(code: "Lyon", name: "Lyon", latitude: 45.4185, longitude: -75.7055, ids: ["preview-c"]),
            Stop(code: "Pimisi", name: "Pimisi", latitude: 45.4136, longitude: -75.7146, ids: ["preview-d"]),
            Stop(code: "Bayview", name: "Bayview", latitude: 45.4088, longitude: -75.7225, ids: ["preview-e"]),
            Stop(code: "Tunney's", name: "Tunney's Pasture", latitude: 45.4038, longitude: -75.7351, ids: ["preview-f"])
        ]
        func point(_ stop: Stop) -> CLLocationCoordinate2D { .init(latitude: stop.latitude, longitude: stop.longitude) }
        let board = now.addingTimeInterval(riding ? -240 : 360)
        let arrival = now.addingTimeInterval(nearing ? 30 : 720)
        let walk = JourneyWalk(key: .init(from: -1, to: 0), from: .init(latitude: 45.427, longitude: -75.692), to: point(stops[0]), duration: 180, distance: 220, verified: true)
        let first = JourneyLeg(tripID: "preview-1", route: .init(name: "1", color: "D52228", textColor: "FFFFFF"), headsign: "Tunney's Pasture", board: stops[0], alight: stops[5], departure: board, arrival: arrival, walk: walk, live: false, coordinates: [], serviceDate: RoutingTimetable.dayKey(now), shapeID: "10736", callingPoints: stops.enumerated().map { index, stop in
            .init(stop: stop, time: board.addingTimeInterval(arrival.timeIntervalSince(board) * Double(index) / 5), sequence: index + 1)
        })
        let end = Stop(code: "Algonquin", name: "Algonquin Station", latitude: 45.3488, longitude: -75.7549, ids: ["preview-g"])
        let transfer = JourneyWalk(key: .init(from: 5, to: 6), from: point(stops[5]), to: point(stops[5]), duration: 180, distance: 220, verified: true)
        let second = JourneyLeg(tripID: "preview-75", route: .init(name: "75", color: "126545", textColor: "FFFFFF"), headsign: "Barrhaven Centre", board: stops[5], alight: end, departure: arrival.addingTimeInterval(480), arrival: arrival.addingTimeInterval(1800), walk: transfer, live: false, coordinates: [], serviceDate: RoutingTimetable.dayKey(now), callingPoints: [.init(stop: stops[5], time: arrival.addingTimeInterval(480), sequence: 1), .init(stop: end, time: arrival.addingTimeInterval(1800), sequence: 2)])
        let final = JourneyWalk(key: .init(from: 7, to: -2), from: point(end), to: .init(latitude: 45.3479, longitude: -75.7587), duration: 300, distance: 375, verified: true)
        let item = MKMapItem(placemark: MKPlacemark(coordinate: final.to)); item.name = "Algonquin College · Preview"
        JourneySession.shared.start(.init(legs: [first, second], finalWalk: final, requestedDeparture: now), destination: .init(item: item), track: track)
        if riding { JourneySession.shared.board() }
    }
}
#endif
