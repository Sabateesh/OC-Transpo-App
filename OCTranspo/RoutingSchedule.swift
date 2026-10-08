import CoreLocation
import Foundation
import Darwin

struct RoutingCall: Codable, Equatable {
    let stop: Int
    let sequence: Int
    var arrival: Date
    var departure: Date
    let pickup: Bool
    let dropoff: Bool
    var shapeDistance: Double? = nil

    init(stop: Int, sequence: Int, arrival: Date, departure: Date, pickup: Bool, dropoff: Bool, shapeDistance: Double? = nil) {
        self.stop = stop; self.sequence = sequence
        self.arrival = arrival; self.departure = departure
        self.pickup = pickup; self.dropoff = dropoff
        self.shapeDistance = shapeDistance
    }

    private enum CodingKeys: String, CodingKey { case stop, sequence, arrival, departure, pickup, dropoff, shapeDistance }
    init(from decoder: Decoder) throws {
        if var values = try? decoder.unkeyedContainer() {
            stop = try values.decode(Int.self); sequence = try values.decode(Int.self)
            arrival = try values.decode(Date.self); departure = try values.decode(Date.self)
            pickup = try values.decode(Bool.self); dropoff = try values.decode(Bool.self)
            shapeDistance = values.isAtEnd ? nil : try values.decodeIfPresent(Double.self)
        } else {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            stop = try values.decode(Int.self, forKey: .stop); sequence = try values.decode(Int.self, forKey: .sequence)
            arrival = try values.decode(Date.self, forKey: .arrival); departure = try values.decode(Date.self, forKey: .departure)
            pickup = try values.decode(Bool.self, forKey: .pickup); dropoff = try values.decode(Bool.self, forKey: .dropoff)
            shapeDistance = try values.decodeIfPresent(Double.self, forKey: .shapeDistance)
        }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.unkeyedContainer()
        try values.encode(stop); try values.encode(sequence)
        try values.encode(arrival); try values.encode(departure)
        try values.encode(pickup); try values.encode(dropoff)
        try values.encode(shapeDistance)
    }
}

struct RoutingTrip: Codable, Equatable {
    let id: String
    let routeID: String
    let headsign: String
    let serviceDate: String
    var calls: [RoutingCall]
    var live = false
    var shapeID: String? = nil
    var scheduledCalls: [RoutingCall]? = nil
    var wheelchairAccessible: WheelchairAccess? = nil
}

struct RoutingTimetable: Codable, Equatable {
    let stops: [Stop]
    let routes: [String: Route]
    let trips: [RoutingTrip]
    let day: String
    var schemaVersion: Int? = 2

    init(stops: [Stop], routes: [String: Route], trips: [RoutingTrip], day: String) {
        self.stops = stops; self.routes = routes; self.trips = trips; self.day = day
    }

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }

    static func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", parts.year!, parts.month!, parts.day!)
    }

    static func seconds(_ value: String) -> Int? {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3, parts[0] >= 0, (0..<60).contains(parts[1]), (0..<60).contains(parts[2]) else { return nil }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    init(files: [String: Data], date: Date) throws {
        try self.init(prepared: PreparedTransitFeed(files: files), date: date)
    }
    init(prepared: PreparedTransitFeed, date: Date) throws {
        stops = prepared.stops; routes = prepared.routes; day = Self.dayKey(date)
        let days = (-1...1).map { offset -> (String, Set<String>, Date) in
            let serviceDay = Self.calendar.date(byAdding: .day, value: offset, to: date)!
            let noon = Self.calendar.date(bySettingHour: 12, minute: 0, second: 0, of: serviceDay)!
            return (Self.dayKey(serviceDay), prepared.activeServices(on: serviceDay), noon.addingTimeInterval(-12 * 3600))
        }
        var expanded: [RoutingTrip] = []
        for trip in prepared.trips {
            for (key, active, base) in days where active.contains(trip.serviceID) {
                var calls: [RoutingCall] = []; calls.reserveCapacity(trip.packedCalls.count / 28)
                trip.forEachCall { call in
                    calls.append(.init(stop: call.stop, sequence: call.sequence, arrival: base.addingTimeInterval(Double(call.arrival)), departure: base.addingTimeInterval(Double(call.departure)), pickup: call.pickup, dropoff: call.dropoff, shapeDistance: call.shapeDistance))
                }
                expanded.append(.init(id: trip.id, routeID: trip.routeID, headsign: trip.headsign, serviceDate: key, calls: calls, shapeID: trip.shapeID, wheelchairAccessible: trip.wheelchairAccessible))
            }
        }
        trips = expanded
        guard !stops.isEmpty, !trips.isEmpty else { throw RoutingError.noService }
    }
}

enum RoutingError: LocalizedError {
    case noService
    var errorDescription: String? { "The downloaded timetable has no service for this date. Choose another date or refresh the timetable." }
}

actor RoutingStore {
    static let shared = RoutingStore()
    private let source: TransitFeedStore
    private var networks: [String: RoutingNetwork] = [:]
    private var preparing: [String: Task<RoutingNetwork, Error>] = [:]
    private var version: String?
    private var geometry: Task<RoutingGeometry, Never>?

    init(folder: URL? = nil, source: TransitFeedStore? = nil) {
        self.source = source ?? (folder.map { TransitFeedStore(folder: $0) } ?? .shared)
    }
    func load(for date: Date, refresh: Bool = false) async throws -> RoutingTimetable {
        try await network(for: date, refresh: refresh).timetable
    }
    func network(for date: Date, refresh: Bool = false) async throws -> RoutingNetwork {
        let snapshot = try await source.load(for: date, refresh: refresh)
        let day = RoutingTimetable.dayKey(date), key = snapshot.version + ":" + RoutingTimetable.dayKey(date)
        if version != snapshot.version {
            networks = [:]; version = snapshot.version
            geometry = Task.detached(priority: .userInitiated) { RoutingGeometry(stops: snapshot.feed.stops) }
        }
        if let network = networks[day] { return network }
        if let task = preparing[key] { return try await task.value }
        let geometry = geometry!
        let task = Task.detached(priority: .userInitiated) {
            let table = try RoutingTimetable(prepared: snapshot.feed, date: date)
            return RoutingNetwork(timetable: table, index: RoutingIndex(table, geometry: await geometry.value), version: snapshot.version)
        }
        preparing[key] = task
        do {
            let value = try await task.value; preparing[key] = nil
            if version == snapshot.version {
                if networks.count >= 3 { networks = [:] }
                networks[day] = value
            }
            return value
        } catch { preparing[key] = nil; throw error }
    }
    func flushCache() async { await source.flushCache() }
}
