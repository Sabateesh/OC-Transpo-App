import Foundation

enum TransitError: LocalizedError {
    case missingKey, badKey, unavailable

    var errorDescription: String? {
        switch self {
        case .missingKey: "Add your OC Transpo API key to Secrets.swift."
        case .badKey: "OC Transpo didn't accept the API key in Secrets.swift."
        case .unavailable: "OC Transpo's live feed isn't responding. Try again in a minute."
        }
    }
}

enum Feed {
    static let tripUpdates = URL(string: "https://nextrip-public-api.azure-api.net/octranspo/gtfs-rt-tp/beta/v1/TripUpdates")!
    static let vehiclePositions = URL(string: "https://nextrip-public-api.azure-api.net/octranspo/gtfs-rt-vp/beta/v1/VehiclePositions")!

    static func download(_ url: URL) async throws -> [UInt8] {
        guard !Secrets.octranspoKey.isEmpty else { throw TransitError.missingKey }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue(Secrets.octranspoKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        let (data, response) = try await URLSession.shared.data(for: request)

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: return [UInt8](data)
        case 401, 403: throw TransitError.badKey
        default: throw TransitError.unavailable
        }
    }
}

struct StopTime {
    let stopID: String
    let time: Date
    var arrival: Date? = nil
    var skipped = false
    var sequence: Int? = nil
}

struct StopVisit {
    let tripID: String
    let time: Date
}

struct LiveTrips {
    struct Trip {
        let id: String
        let routeID: String
        let vehicleID: String?
        let stops: [StopTime]
        var serviceDate: String? = nil
        var canceled = false
        var skippedStopIDs: Set<String> = []
        var skippedSequences: Set<Int> = []
    }

    private(set) var trips: [String: Trip] = [:]
    private(set) var canceledTripIDs: Set<String> = []
    private(set) var canceledTripDates: [String: Set<String>] = [:]
    private(set) var byStop: [String: [StopVisit]] = [:]

    init() {}

    init(_ feed: [UInt8], only stopIDs: Set<String>? = nil) {
        var message = ProtoReader(feed)
        while let (field, wire) = message.next() {
            guard field == 2, wire == 2 else { message.skip(wire); continue }
            var entity = message.message()
            while let (field, wire) = entity.next() {
                guard field == 3, wire == 2 else { entity.skip(wire); continue }
                guard let trip = Self.trip(entity.message()) else { continue }
                if trip.canceled {
                    canceledTripIDs.insert(trip.id)
                    canceledTripDates[trip.id, default: []].insert(trip.serviceDate ?? "")
                    continue
                }
                if let stopIDs, !trip.stops.contains(where: { stopIDs.contains($0.stopID) }) { continue }

                trips[trip.id] = trip
                for stop in trip.stops where stopIDs?.contains(stop.stopID) ?? true {
                    byStop[stop.stopID, default: []].append(StopVisit(tripID: trip.id, time: stop.time))
                }
            }
        }
    }

    func upcoming(at stopIDs: [String], now: Date = .now,
                  route: (String) -> Route, headsign: (String) -> String?) -> [Upcoming] {
        let cutoff = now.addingTimeInterval(-10)
        let visits = stopIDs
            .flatMap { byStop[$0] ?? [] }
            .filter { $0.time > cutoff }
            .sorted { $0.time < $1.time }

        var lines: [String: Upcoming] = [:]
        var order: [String] = []
        var seen: Set<String> = []
        for visit in visits {
            guard seen.insert(visit.tripID).inserted, let trip = trips[visit.tripID] else { continue }
            let r = route(trip.routeID)
            let h = headsign(trip.id) ?? ""
            let key = r.name + "|" + h
            if lines[key] == nil {
                lines[key] = Upcoming(route: r, headsign: h, live: trip.vehicleID != nil)
                order.append(key)
            }
            lines[key]!.times.append(visit.time)
            lines[key]!.tripIDs.append(trip.id)
        }
        return order.compactMap { lines[$0] }
    }

    private static func trip(_ update: ProtoReader) -> Trip? {
        var update = update
        var tripID = "", routeID = ""
        var vehicleID: String?
        var canceled = false
        var serviceDate: String?
        var stops: [StopTime] = []

        while let (field, wire) = update.next() {
            switch (field, wire) {
            case (1, 2):
                var trip = update.message()
                while let (field, wire) = trip.next() {
                    switch (field, wire) {
                    case (1, 2): tripID = trip.string()
                    case (5, 2): routeID = trip.string()
                    case (3, 2): serviceDate = trip.string()
                    case (4, 0): canceled = trip.varint() == 3
                    default: trip.skip(wire)
                    }
                }
            case (2, 2):
                if let stop = stopTime(update.message()) {
                    stops.append(stop)
                }
            case (3, 2):
                var vehicle = update.message()
                vehicleID = ""
                while let (field, wire) = vehicle.next() {
                    if field == 1, wire == 2 { vehicleID = vehicle.string() } else { vehicle.skip(wire) }
                }
            default:
                update.skip(wire)
            }
        }

        guard !tripID.isEmpty else { return nil }
        return Trip(id: tripID, routeID: routeID, vehicleID: vehicleID, stops: stops.filter { !$0.skipped },
                    serviceDate: serviceDate, canceled: canceled, skippedStopIDs: Set(stops.filter { $0.skipped && $0.sequence == nil }.map(\.stopID)),
                    skippedSequences: Set(stops.filter(\.skipped).compactMap(\.sequence)))
    }

    private static func stopTime(_ update: ProtoReader) -> StopTime? {
        var update = update
        var stopID = ""
        var arrival: Int64?, departure: Int64?
        var sequence: Int?
        var skipped = false

        while let (field, wire) = update.next() {
            switch (field, wire) {
            case (1, 0): sequence = Int(update.varint())
            case (4, 2): stopID = update.string()
            case (2, 2): arrival = eventTime(update.message())
            case (3, 2): departure = eventTime(update.message())
            case (5, 0): skipped = update.varint() == 1
            default: update.skip(wire)
            }
        }
        if skipped { return StopTime(stopID: stopID, time: .distantPast, skipped: true, sequence: sequence) }
        guard let time = departure ?? arrival else { return nil }
        return StopTime(stopID: stopID, time: Date(timeIntervalSince1970: TimeInterval(time)),
                        arrival: arrival.map { Date(timeIntervalSince1970: TimeInterval($0)) }, sequence: sequence)
    }

    private static func eventTime(_ event: ProtoReader) -> Int64? {
        var event = event
        while let (field, wire) = event.next() {
            if field == 2, wire == 0 { return Int64(bitPattern: event.varint()) }
            event.skip(wire)
        }
        return nil
    }
}

struct Vehicle: Identifiable, Hashable {
    let id: String
    let tripID: String
    let routeID: String
    let latitude: Double
    let longitude: Double
    var timestamp: Date? = nil
    var serviceDate: String? = nil
    var occupancy: OccupancyStatus? = nil

    static func decode(_ feed: [UInt8]) -> [Vehicle] {
        var result: [Vehicle] = []
        var message = ProtoReader(feed)
        while let (field, wire) = message.next() {
            guard field == 2, wire == 2 else { message.skip(wire); continue }
            var entity = message.message()
            while let (field, wire) = entity.next() {
                guard field == 4, wire == 2 else { entity.skip(wire); continue }
                if let vehicle = vehicle(entity.message()) {
                    result.append(vehicle)
                }
            }
        }
        return result
    }

    private static func vehicle(_ position: ProtoReader) -> Vehicle? {
        var reader = position
        var id = "", tripID = "", routeID = ""
        var latitude: Float?, longitude: Float?
        var timestamp: Date?, serviceDate: String?, occupancy: OccupancyStatus?

        while let (field, wire) = reader.next() {
            switch (field, wire) {
            case (1, 2):
                var trip = reader.message()
                while let (field, wire) = trip.next() {
                    switch (field, wire) {
                    case (1, 2): tripID = trip.string()
                    case (3, 2): serviceDate = trip.string()
                    case (5, 2): routeID = trip.string()
                    default: trip.skip(wire)
                    }
                }
            case (2, 2):
                var point = reader.message()
                while let (field, wire) = point.next() {
                    switch (field, wire) {
                    case (1, 5): latitude = point.float()
                    case (2, 5): longitude = point.float()
                    default: point.skip(wire)
                    }
                }
            case (5, 0): timestamp = Date(timeIntervalSince1970: Double(reader.varint()))
            case (9, 0): occupancy = OccupancyStatus(rawValue: Int(reader.varint()))
            case (8, 2):
                var vehicle = reader.message()
                while let (field, wire) = vehicle.next() {
                    if field == 1, wire == 2 { id = vehicle.string() } else { vehicle.skip(wire) }
                }
            default:
                reader.skip(wire)
            }
        }

        guard let latitude, let longitude, latitude != 0 else { return nil }
        return Vehicle(id: id.isEmpty ? tripID : id, tripID: tripID, routeID: routeID,
                       latitude: Double(latitude), longitude: Double(longitude), timestamp: timestamp,
                       serviceDate: serviceDate, occupancy: occupancy)
    }
}

enum OccupancyStatus: Int, Hashable {
    case empty = 0, manySeats, fewSeats, standing, crowded, full, notAccepting, unavailable, notBoardable
    var label: String? {
        switch self {
        case .empty: "Empty"
        case .manySeats: "Seats available"
        case .fewSeats: "Few seats"
        case .standing: "Standing room"
        case .crowded: "Very crowded"
        case .full: "Full"
        case .notAccepting: "Not boarding"
        case .unavailable, .notBoardable: nil
        }
    }
}

struct ProtoReader {
    private let bytes: [UInt8]
    private var pos: Int
    private let end: Int

    init(_ bytes: [UInt8]) {
        self.init(bytes, 0, bytes.count)
    }

    private init(_ bytes: [UInt8], _ pos: Int, _ end: Int) {
        self.bytes = bytes
        self.pos = pos
        self.end = end
    }

    mutating func next() -> (Int, Int)? {
        guard pos < end else { return nil }
        let key = varint()
        return (Int(key >> 3), Int(key & 7))
    }

    mutating func varint() -> UInt64 {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while pos < end {
            let byte = bytes[pos]
            pos += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte < 0x80 { break }
            shift += 7
        }
        return value
    }

    mutating func float() -> Float {
        guard pos + 4 <= end else { pos = end; return 0 }
        var bits: UInt32 = 0
        for i in 0..<4 {
            bits |= UInt32(bytes[pos + i]) << (8 * i)
        }
        pos += 4
        return Float(bitPattern: bits)
    }

    mutating func message() -> ProtoReader {
        let n = length()
        defer { pos += n }
        return ProtoReader(bytes, pos, pos + n)
    }

    mutating func string() -> String {
        let n = length()
        defer { pos += n }
        return String(decoding: bytes[pos..<(pos + n)], as: UTF8.self)
    }

    mutating func skip(_ wireType: Int) {
        switch wireType {
        case 0: _ = varint()
        case 1: pos = min(pos + 8, end)
        case 2: let n = length(); pos += n
        case 5: pos = min(pos + 4, end)
        default: pos = end
        }
    }

    private mutating func length() -> Int {
        min(Int(clamping: varint()), end - pos)
    }
}
