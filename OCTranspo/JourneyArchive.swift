import CoreLocation
import Foundation

struct JourneyArchive: Codable {
    struct Point: Codable {
        let latitude: Double
        let longitude: Double
        init(_ value: CLLocationCoordinate2D) { latitude = value.latitude; longitude = value.longitude }
        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    }
    struct Walk: Codable {
        let fromIndex: Int
        let toIndex: Int
        let from: Point
        let to: Point
        let duration: Double
        let distance: Double
        let verified: Bool
        let coordinates: [Point]
        let instructions: [WalkingInstruction]?
        init(_ value: JourneyWalk) {
            fromIndex = value.key.from; toIndex = value.key.to; from = Point(value.from); to = Point(value.to)
            duration = value.duration; distance = value.distance; verified = value.verified
            coordinates = value.coordinates.map(Point.init); instructions = value.instructions
        }
        var value: JourneyWalk { .init(key: .init(from: fromIndex, to: toIndex), from: from.coordinate, to: to.coordinate, duration: duration, distance: distance, verified: verified, coordinates: coordinates.map(\.coordinate), instructions: instructions ?? []) }
    }
    struct Leg: Codable {
        let tripID: String
        let route: Route
        let headsign: String
        let board: Stop
        let alight: Stop
        let departure: Date
        let arrival: Date
        let walk: Walk
        let live: Bool
        let serviceDate: String
        let scheduledDeparture: Date?
        let shapeID: String?
        let shapeStart: Double?
        let shapeEnd: Double?
        let callingPoints: [JourneyCallingPoint]
        let wheelchairAccessible: WheelchairAccess?
        init(_ leg: JourneyLeg) {
            tripID = leg.tripID; route = leg.route; headsign = leg.headsign; board = leg.board; alight = leg.alight
            departure = leg.departure; arrival = leg.arrival; walk = Walk(leg.walk); live = leg.live
            serviceDate = leg.serviceDate; scheduledDeparture = leg.scheduledDeparture
            shapeID = leg.shapeID; shapeStart = leg.shapeStart; shapeEnd = leg.shapeEnd; callingPoints = leg.callingPoints; wheelchairAccessible = leg.wheelchairAccessible
        }
        var value: JourneyLeg { .init(tripID: tripID, route: route, headsign: headsign, board: board, alight: alight, departure: departure, arrival: arrival, walk: walk.value, live: live, coordinates: [], serviceDate: serviceDate, scheduledDeparture: scheduledDeparture, shapeID: shapeID, shapeStart: shapeStart, shapeEnd: shapeEnd, callingPoints: callingPoints, wheelchairAccessible: wheelchairAccessible) }
    }
    let version: Int
    let sessionID: UUID
    let savedAt: Date
    let expiresAt: Date
    let legs: [Leg]
    let finalWalk: Walk
    let requestedDeparture: Date
    let destinationTitle: String
    let destination: Point
    let progress: JourneyGuidanceProgress
    let automaticBoardingSuppressed: Bool
    let predictionsUpdatedAt: Date?
    let actionToken: UUID?

    init(journey: Journey, title: String, destination: CLLocationCoordinate2D, progress: JourneyGuidanceProgress, sessionID: UUID, suppressed: Bool, now: Date = .now, predictionsUpdatedAt: Date? = nil, actionToken: UUID? = nil) {
        self.predictionsUpdatedAt = predictionsUpdatedAt; self.actionToken = actionToken
        version = 1; self.sessionID = sessionID; savedAt = now
        expiresAt = journey.arrival.addingTimeInterval(2 * 3600)
        legs = journey.legs.map(Leg.init); finalWalk = Walk(journey.finalWalk); requestedDeparture = journey.requestedDeparture
        destinationTitle = title; self.destination = Point(destination); self.progress = progress; automaticBoardingSuppressed = suppressed
    }
    func restored(at now: Date) -> Journey? {
        guard version == 1, savedAt <= now.addingTimeInterval(60), expiresAt > now, !progress.finished,
              !legs.isEmpty, legs.count <= 8, progress.legIndex >= 0, progress.legIndex <= legs.count,
              !progress.onBoard || progress.legIndex < legs.count,
              CLLocationCoordinate2DIsValid(destination.coordinate),
              legs.allSatisfy({ !$0.board.ids.isEmpty && !$0.alight.ids.isEmpty && $0.arrival >= $0.departure && $0.walk.duration >= 0 && CLLocationCoordinate2DIsValid($0.walk.from.coordinate) && CLLocationCoordinate2DIsValid($0.walk.to.coordinate) }),
              finalWalk.duration >= 0 else { return nil }
        if let index = progress.observedStop {
            guard progress.legIndex < legs.count, index >= 0, index < legs[progress.legIndex].callingPoints.count else { return nil }
        }
        return .init(legs: legs.map(\.value), finalWalk: finalWalk.value, requestedDeparture: requestedDeparture)
    }
}

struct JourneyArchiveStore {
    let url: URL
    init(url: URL = URL.applicationSupportDirectory.appending(path: "active-journey.json")) { self.url = url }
    func load() -> JourneyArchive? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(JourneyArchive.self, from: data)
    }
    func save(_ archive: JourneyArchive) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(archive)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
    func clear() { try? FileManager.default.removeItem(at: url) }
}
