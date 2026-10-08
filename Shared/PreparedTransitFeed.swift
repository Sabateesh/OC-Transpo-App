import Foundation
import Darwin

struct PreparedTransitFeed: Codable {
    struct Service: Codable {
        let id: String
        let start: String
        let end: String
        let weekdays: [Bool]
    }
    struct Exception: Codable {
        let service: String
        let day: String
        let added: Bool
    }
    struct Call {
        let stop: Int
        let sequence: Int
        let arrival: Int
        let departure: Int
        let pickup: Bool
        let dropoff: Bool
        let shapeDistance: Double?
    }
    struct Trip: Codable {
        let id: String
        let routeID: String
        let serviceID: String
        let headsign: String
        let shapeID: String?
        let packedCalls: Data
        var wheelchairAccessible: WheelchairAccess? = nil
        func forEachCall(_ body: (Call) -> Void) {
            packedCalls.withUnsafeBytes { bytes in
                for offset in stride(from: 0, to: bytes.count, by: 28) {
                    func integer(_ field: Int) -> Int { Int(Int32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset + field * 4, as: Int32.self))) }
                    let flags = integer(4)
                    let distance = Double(bitPattern: UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: offset + 20, as: UInt64.self)))
                    body(Call(stop: integer(0), sequence: integer(1), arrival: integer(2), departure: integer(3), pickup: flags & 1 != 0, dropoff: flags & 2 != 0, shapeDistance: distance.isNaN ? nil : distance))
                }
            }
        }
    }
    let schema: Int
    let stops: [Stop]
    let displayStops: [Stop]
    let routes: [String: Route]
    let services: [Service]
    let exceptions: [Exception]
    let trips: [Trip]
    let validFrom: String
    let validThrough: String

    static var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "America/Toronto")!
        return result
    }
    static func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year!, c.month!, c.day!)
    }
    static func seconds(_ value: String) -> Int? {
        let p = value.split(separator: ":").compactMap { Int($0) }
        guard p.count == 3, (0...167).contains(p[0]), (0..<60).contains(p[1]), (0..<60).contains(p[2]) else { return nil }
        return p[0] * 3600 + p[1] * 60 + p[2]
    }
    func covers(_ date: Date) -> Bool { let day = Self.dayKey(date); return validFrom <= day && day <= validThrough }
    func activeServices(on date: Date) -> Set<String> {
        let day = Self.dayKey(date), weekday = Self.calendar.component(.weekday, from: date) - 1
        var result = Set(services.filter { $0.start <= day && $0.end >= day && $0.weekdays[weekday] }.map(\.id))
        for exception in exceptions where exception.day == day {
            if exception.added { result.insert(exception.service) } else { result.remove(exception.service) }
        }
        return result
    }
    var valid: Bool {
        guard schema == 1, !stops.isEmpty, !trips.isEmpty, validFrom <= validThrough, services.allSatisfy({ $0.weekdays.count == 7 }) else { return false }
        for trip in trips {
            guard trip.packedCalls.count >= 56, trip.packedCalls.count % 28 == 0 else { return false }
            var okay = true
            trip.forEachCall { if !stops.indices.contains($0.stop) || $0.arrival < 0 || $0.departure < $0.arrival { okay = false } }
            if !okay { return false }
        }
        return true
    }
    init(files: [String: Data]) throws {
        schema = 1
        var points: [Stop] = [], stopIndex: [String: Int] = [:]
        var stationAccess: [String: WheelchairAccess] = [:]
        readCSV(files["stops.txt"]) { col in
            if col("location_type") == "1" { stationAccess[col("stop_id")] = WheelchairAccess(feedValue: col("wheelchair_boarding")) }
        }
        readCSV(files["stops.txt"]) { col in
            guard col("location_type").isEmpty || col("location_type") == "0", let lat = Double(col("stop_lat")), let lon = Double(col("stop_lon")) else { return }
            let id = col("stop_id"); stopIndex[id] = points.count
            let local = WheelchairAccess(feedValue: col("wheelchair_boarding"))
            let access = local == .unknown ? stationAccess[col("parent_station")] ?? .unknown : local
            points.append(.init(code: col("stop_code").isEmpty ? id : col("stop_code"), name: col("stop_name").titleCased, latitude: lat, longitude: lon, ids: [id], wheelchairBoarding: access))
        }
        stops = points; displayStops = Schedule.stops(from: files["stops.txt"]); routes = Schedule.routes(from: files["routes.txt"])
        var calendars: [Service] = [], changes: [Exception] = []
        let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        readCSV(files["calendar.txt"]) { col in calendars.append(.init(id: col("service_id"), start: col("start_date"), end: col("end_date"), weekdays: weekdays.map { col($0) == "1" })) }
        readCSV(files["calendar_dates.txt"]) { col in changes.append(.init(service: col("service_id"), day: col("date"), added: col("exception_type") == "1")) }
        services = calendars; exceptions = changes
        validFrom = (calendars.map(\.start) + changes.filter(\.added).map(\.day)).min() ?? ""
        validThrough = (calendars.map(\.end) + changes.filter(\.added).map(\.day)).max() ?? ""
        struct Template { let id: String; let route: String; let service: String; let headsign: String; let shape: String?; let access: WheelchairAccess }
        var templates: [Template] = [], tripIndex: [String: Int] = [:]
        readCSV(files["trips.txt"]) { col in
            tripIndex[col("trip_id")] = templates.count
            templates.append(.init(id: col("trip_id"), route: col("route_id"), service: col("service_id"), headsign: col("trip_headsign"), shape: col("shape_id").isEmpty ? nil : col("shape_id"), access: WheelchairAccess(feedValue: col("wheelchair_accessible"))))
        }
        var calls = Array(repeating: [Call](), count: templates.count)
        readRoutingStopTimes(files["stop_times.txt"], tripIDs: Set(tripIndex.keys)) { col in
            guard let index = tripIndex[col("trip_id")], let stop = stopIndex[col("stop_id")], let sequence = Int(col("stop_sequence")),
                  let arrival = Self.seconds(col("arrival_time")), let departure = Self.seconds(col("departure_time")), departure >= arrival else { return }
            calls[index].append(.init(stop: stop, sequence: sequence, arrival: arrival, departure: departure, pickup: ["", "0"].contains(col("pickup_type")), dropoff: ["", "0"].contains(col("drop_off_type")), shapeDistance: Double(col("shape_dist_traveled"))))
        }
        trips = templates.enumerated().compactMap { index, template in
            guard calls[index].count > 1 else { return nil }
            var data = Data(capacity: calls[index].count * 28)
            for call in calls[index].sorted(by: { $0.sequence < $1.sequence }) {
                for value in [call.stop, call.sequence, call.arrival, call.departure, (call.pickup ? 1 : 0) | (call.dropoff ? 2 : 0)] {
                    var number = Int32(clamping: value).littleEndian; withUnsafeBytes(of: &number) { data.append(contentsOf: $0) }
                }
                var distance = (call.shapeDistance ?? .nan).bitPattern.littleEndian; withUnsafeBytes(of: &distance) { data.append(contentsOf: $0) }
            }
            return Trip(id: template.id, routeID: template.route, serviceID: template.service, headsign: template.headsign, shapeID: template.shape, packedCalls: data, wheelchairAccessible: template.access)
        }
        guard !stops.isEmpty, !trips.isEmpty, !validFrom.isEmpty else { throw URLError(.cannotParseResponse) }
    }
    func encoded() throws -> Data {
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        return try (encoder.encode(self) as NSData).compressed(using: .lzfse) as Data
    }
    static func decode(_ data: Data) throws -> Self {
        let unpacked = try (data as NSData).decompressed(using: .lzfse) as Data
        let value = try PropertyListDecoder().decode(Self.self, from: unpacked)
        guard value.valid else { throw URLError(.cannotParseResponse) }
        return value
    }
}

func readRoutingStopTimes(_ data: Data?, tripIDs: Set<String>, row: ((String) -> String) -> Void) {
    guard let data, !data.isEmpty else { return }
    let handled = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> Bool in
        readPlainRoutingRows(bytes, tripIDs: tripIDs, row: row)
    }
    if !handled {
        readCSV(data) { col in
            guard tripIDs.contains(col("trip_id")) else { return }
            let names = ["trip_id", "stop_id", "arrival_time", "departure_time", "stop_sequence", "pickup_type", "drop_off_type", "stop_headsign", "shape_dist_traveled", "timepoint"]
            var fields: [String: String] = [:]
            for name in names { fields[name] = col(name) }
            row { fields[$0] ?? "" }
        }
    }
}

private func readPlainRoutingRows(_ bytes: UnsafeRawBufferPointer, tripIDs: Set<String>, row: ((String) -> String) -> Void) -> Bool {
    guard let base = bytes.bindMemory(to: UInt8.self).baseAddress else { return true }
    guard memchr(base, 34, bytes.count) == nil else { return false }
    var position = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
    var columns: [String: Int] = [:]
    while position < bytes.count {
        let line = base.advanced(by: position)
        var end = bytes.count
        if let newline = memchr(line, 10, bytes.count - position) {
            end = UnsafeRawPointer(base).distance(to: UnsafeRawPointer(newline))
        }
        var length = end - position
        if length > 0 && base[end - 1] == 13 { length -= 1 }
        position = end + 1
        guard length > 0 else { continue }
        if columns.isEmpty {
            let header = String(decoding: UnsafeBufferPointer(start: line, count: length), as: UTF8.self)
            let fields = header.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.first == "trip_id" else { return false }
            for (index, name) in fields.enumerated() where columns[String(name)] == nil { columns[String(name)] = index }
            continue
        }
        guard let comma = memchr(line, 44, length) else { continue }
        let tripLength = UnsafeRawPointer(line).distance(to: UnsafeRawPointer(comma))
        let id = String(decoding: UnsafeBufferPointer(start: line, count: tripLength), as: UTF8.self)
        guard tripIDs.contains(id) else { continue }
        let record = String(decoding: UnsafeBufferPointer(start: line, count: length), as: UTF8.self)
        let fields = record.split(separator: ",", omittingEmptySubsequences: false)
        row { name in
            guard let column = columns[name], column < fields.count else { return "" }
            return String(fields[column])
        }
    }
    return true
}
