import Foundation

struct Schedule: Codable {
    private(set) var stops: [Stop] = []
    private(set) var routes: [String: Route] = [:]
    private(set) var headsigns: [String: String] = [:]
    private var byCode: [String: Int] = [:]
    private var byID: [String: Int] = [:]

    init() {}

    init(_ files: [String: Data]) {
        stops = Self.stops(from: files["stops.txt"])
        for (i, stop) in stops.enumerated() {
            byCode[stop.code] = i
            for id in stop.ids { byID[id] = i }
        }
        routes = Self.routes(from: files["routes.txt"])
        headsigns = Self.headsigns(from: files["trips.txt"])
    }

    func stop(code: String) -> Stop? {
        byCode[code].map { stops[$0] }
    }

    func stop(id: String) -> Stop? {
        byID[id].map { stops[$0] }
    }

    func route(_ id: String) -> Route {
        Self.route(id, in: routes)
    }

    var routeNames: [String] {
        Set(routes.values.map(\.name)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }


    init(_ feed: PreparedTransitFeed) {
        stops = feed.displayStops; routes = feed.routes
        headsigns = Dictionary(feed.trips.map { ($0.id, $0.headsign) }, uniquingKeysWith: { _, last in last })
        for (i, stop) in stops.enumerated() {
            byCode[stop.code] = i
            for id in stop.ids { byID[id] = i }
        }
    }

    static func stops(from data: Data?) -> [Stop] {
        var byCode: [String: Stop] = [:]
        var stationAccess: [String: WheelchairAccess] = [:]
        readCSV(data) { col in
            if col("location_type") == "1" { stationAccess[col("stop_id")] = WheelchairAccess(feedValue: col("wheelchair_boarding")) }
        }
        readCSV(data) { col in
            let code = col("stop_code")
            guard !code.isEmpty else { return }
            if byCode[code] == nil || col("location_type") == "1" {
                byCode[code] = Stop(code: code,
                                    name: col("stop_name").titleCased,
                                    latitude: Double(col("stop_lat")) ?? 0,
                                    longitude: Double(col("stop_lon")) ?? 0,
                                    ids: byCode[code]?.ids ?? [],
                                    wheelchairBoarding: WheelchairAccess(feedValue: col("wheelchair_boarding")))
            }
            byCode[code]!.ids.append(col("stop_id"))
        }
        return byCode.values.sorted { $0.code < $1.code }
    }

    static func routes(from data: Data?) -> [String: Route] {
        var routes: [String: Route] = [:]
        readCSV(data) { col in
            routes[col("route_id")] = Route(name: col("route_short_name"),
                                            color: col("route_color"),
                                            textColor: col("route_text_color"))
        }
        return routes
    }

    static func headsigns(from data: Data?, only trips: Set<String>? = nil) -> [String: String] {
        var headsigns: [String: String] = [:]
        if trips == nil { headsigns.reserveCapacity(150_000) }
        readCSV(data) { col in
            let id = col("trip_id")
            if trips?.contains(id) ?? true {
                headsigns[id] = col("trip_headsign")
            }
        }
        return headsigns
    }

    static func route(_ id: String, in routes: [String: Route]) -> Route {
        routes[id] ?? Route(name: String(id.prefix { $0 != "-" }), color: "", textColor: "")
    }
}

enum StaticFeed {
    static let url = URL(string: "https://oct-gtfs-emasagcnfmcgeham.z01.azurefd.net/public-access/GTFSExport.zip")!
}

struct RemoteZip {
    struct Entry {
        let name: String
        let method: Int
        let crc: Int
        let packedSize: Int
        let offset: Int
    }

    let url: URL
    private(set) var entries: [String: Entry] = [:]
    private var whole: Data?

    init(_ url: URL) async throws {
        self.url = url

        let (tail, response) = try await fetch("bytes=-65536")
        var fileSize = tail.count
        if response.statusCode == 206,
           let total = response.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last.flatMap({ Int($0) }) {
            fileSize = total
        } else {
            whole = tail
        }

        guard tail.count >= 22,
              let end = stride(from: tail.count - 22, through: 0, by: -1).first(where: { tail.u32($0) == 0x0605_4b50 })
        else { throw URLError(.cannotParseResponse) }

        let dirSize = tail.u32(end + 12)
        let dirOffset = tail.u32(end + 16)
        let tailStart = fileSize - tail.count
        let dir: Data
        if dirOffset >= tailStart {
            dir = tail.slice(dirOffset - tailStart, dirSize)
        } else {
            dir = try await bytes(dirOffset, dirSize)
        }

        var p = 0
        while p + 46 <= dir.count, dir.u32(p) == 0x0201_4b50 {
            let nameLength = dir.u16(p + 28)
            let name = String(decoding: dir.slice(p + 46, nameLength), as: UTF8.self)
            entries[name] = Entry(name: name,
                                  method: dir.u16(p + 10),
                                  crc: dir.u32(p + 16),
                                  packedSize: dir.u32(p + 20),
                                  offset: dir.u32(p + 42))
            p += 46 + nameLength + dir.u16(p + 30) + dir.u16(p + 32)
        }
    }

    func read(_ entry: Entry) async throws -> Data {
        let chunk = try await bytes(entry.offset, 30 + 1024 + entry.packedSize)
        guard chunk.count >= 30, chunk.u32(0) == 0x0403_4b50 else { throw URLError(.cannotParseResponse) }

        let packed = chunk.slice(30 + chunk.u16(26) + chunk.u16(28), entry.packedSize)
        guard packed.count == entry.packedSize else { throw URLError(.cannotParseResponse) }

        switch entry.method {
        case 0: return packed
        case 8: return try (packed as NSData).decompressed(using: .zlib) as Data
        default: throw URLError(.cannotDecodeContentData)
        }
    }

    private func bytes(_ offset: Int, _ length: Int) async throws -> Data {
        if let whole { return whole.slice(offset, length) }
        return try await fetch("bytes=\(offset)-\(offset + length - 1)").0
    }

    private func fetch(_ range: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue(range, forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, [200, 206].contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

private extension Data {
    func u16(_ i: Int) -> Int {
        Int(self[startIndex + i]) | Int(self[startIndex + i + 1]) << 8
    }

    func u32(_ i: Int) -> Int {
        u16(i) | u16(i + 2) << 16
    }

    func slice(_ i: Int, _ length: Int) -> Data {
        let lower = Swift.min(i, count), upper = Swift.min(i + length, count)
        return Data(self[(startIndex + lower)..<(startIndex + upper)])
    }
}

func readCSV(_ data: Data?, row: ((String) -> String) -> Void) {
    guard let data else { return }

    var columns: [String: Int]?
    var fields: [String] = []
    var field: [UInt8] = []
    var quoted = false, justClosedQuote = false

    data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
        let start = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        for i in start...bytes.count {
            let byte = i < bytes.count ? bytes[i] : UInt8(ascii: "\n")

            if byte == UInt8(ascii: "\"") {
                if !quoted && justClosedQuote { field.append(byte) }
                quoted.toggle()
                justClosedQuote = !quoted
                continue
            }
            justClosedQuote = false

            if quoted {
                field.append(byte)
                continue
            }

            switch byte {
            case UInt8(ascii: "\r"):
                continue
            case UInt8(ascii: ","), UInt8(ascii: "\n"):
                fields.append(String(decoding: field, as: UTF8.self))
                field.removeAll(keepingCapacity: true)
                guard byte == UInt8(ascii: "\n") else { continue }

                if let columns {
                    if fields != [""] {
                        row { name in
                            guard let column = columns[name], column < fields.count else { return "" }
                            return fields[column]
                        }
                    }
                } else {
                    columns = Dictionary(fields.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
                }
                fields.removeAll(keepingCapacity: true)
            default:
                field.append(byte)
            }
        }
    }
}

extension String {
    var titleCased: String {
        guard self == uppercased() else { return self }
        var out = ""
        var afterLetter = false
        for ch in self {
            out += afterLetter ? ch.lowercased() : ch.uppercased()
            afterLetter = ch.isLetter || ch == "'"
        }
        return out
    }
}
