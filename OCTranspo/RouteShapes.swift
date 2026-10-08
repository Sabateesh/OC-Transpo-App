import CoreLocation
import Foundation

struct RouteShapePoint {
    let coordinate: CLLocationCoordinate2D
    let distance: Double?
    let sequence: Int
}

enum RouteShapeGeometry {
    static func parse(_ data: Data) -> [String: [RouteShapePoint]] {
        var shapes: [String: [RouteShapePoint]] = [:]
        readCSV(data) { col in
            guard let lat = Double(col("shape_pt_lat")), let lon = Double(col("shape_pt_lon")),
                  let sequence = Int(col("shape_pt_sequence")) else { return }
            shapes[col("shape_id"), default: []].append(RouteShapePoint(coordinate: .init(latitude: lat, longitude: lon), distance: Double(col("shape_dist_traveled")), sequence: sequence))
        }
        for id in Array(shapes.keys) { shapes[id]!.sort { $0.sequence < $1.sequence } }
        return shapes
    }

    static func segment(_ points: [RouteShapePoint], start: Double, end: Double) -> [CLLocationCoordinate2D]? {
        guard points.count > 1, points.allSatisfy({ $0.distance != nil }),
              start >= points[0].distance!, end > start, end <= points.last!.distance! + 1 else { return nil }
        guard zip(points, points.dropFirst()).allSatisfy({ $0.distance! <= $1.distance! }) else { return nil }
        func coordinate(at distance: Double) -> CLLocationCoordinate2D {
            guard let upper = points.firstIndex(where: { $0.distance! >= distance }) else { return points.last!.coordinate }
            if upper == 0 { return points[0].coordinate }
            let a = points[upper - 1], b = points[upper]
            let ratio = max(0, min(1, (distance - a.distance!) / max(0.0001, b.distance! - a.distance!)))
            return .init(latitude: a.coordinate.latitude + ratio * (b.coordinate.latitude - a.coordinate.latitude),
                         longitude: a.coordinate.longitude + ratio * (b.coordinate.longitude - a.coordinate.longitude))
        }
        return [coordinate(at: start)] + points.filter { $0.distance! > start && $0.distance! < end }.map(\.coordinate) + [coordinate(at: end)]
    }

    static func segment(_ points: [RouteShapePoint], stops: [JourneyCallingPoint]) -> [CLLocationCoordinate2D]? {
        guard points.count > 1, stops.count > 1 else { return nil }
        struct Match { let position: Double; let coordinate: CLLocationCoordinate2D; let error: Double }
        var rows: [[Match]] = []
        for stop in stops {
            let target = CLLocation(latitude: stop.stop.latitude, longitude: stop.stop.longitude)
            let scale = cos(stop.stop.latitude * .pi / 180)
            var matches: [Match] = []
            for i in 0..<(points.count - 1) {
                let a = points[i].coordinate, b = points[i + 1].coordinate
                let dx = (b.longitude - a.longitude) * scale, dy = b.latitude - a.latitude
                let tx = (target.coordinate.longitude - a.longitude) * scale, ty = target.coordinate.latitude - a.latitude
                let fraction = max(0, min(1, (tx * dx + ty * dy) / max(1e-15, dx * dx + dy * dy)))
                let point = CLLocationCoordinate2D(latitude: a.latitude + fraction * dy, longitude: a.longitude + fraction * (b.longitude - a.longitude))
                let distance = target.distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
                if distance < 200 { matches.append(Match(position: Double(i) + fraction, coordinate: point, error: distance * distance)) }
            }
            guard !matches.isEmpty else { return nil }
            rows.append(matches)
        }
        var costs = rows[0].map(\.error)
        var parents: [[Int]] = [Array(repeating: -1, count: rows[0].count)]
        for row in 1..<rows.count {
            var next = Array(repeating: Double.infinity, count: rows[row].count)
            var links = Array(repeating: -1, count: rows[row].count)
            for (j, match) in rows[row].enumerated() {
                for (k, previous) in rows[row - 1].enumerated() where previous.position < match.position {
                    let cost = costs[k] + match.error
                    if cost < next[j] { next[j] = cost; links[j] = k }
                }
            }
            costs = next; parents.append(links)
        }
        guard let lastIndex = costs.indices.min(by: { costs[$0] < costs[$1] }), costs[lastIndex].isFinite else { return nil }
        let end = rows.last![lastIndex]
        var firstIndex = lastIndex
        for row in stride(from: rows.count - 1, through: 1, by: -1) { firstIndex = parents[row][firstIndex] }
        let start = rows[0][firstIndex]
        let middle = points.enumerated().filter { Double($0.offset) > start.position && Double($0.offset) < end.position }.map { $0.element.coordinate }
        return [start.coordinate] + middle + [end.coordinate]
    }
}

actor RouteShapes {
    static let shared = RouteShapes()
    private var shapes: [String: [RouteShapePoint]]?
    private var loaded: Date?
    private var loading: Task<[String: [RouteShapePoint]], Error>?

    private func load() async throws -> [String: [RouteShapePoint]] {
        if let shapes, let loaded, Date.now.timeIntervalSince(loaded) < 6 * 3600 { return shapes }
        if let loading { return try await loading.value }
        let task = Task.detached(priority: .utility) {
            let folder = AppGroup.folder.appending(path: "route-shapes", directoryHint: .isDirectory)
            let path = folder.appending(path: "shapes.txt")
            let modified = (try? path.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, Date.now.timeIntervalSince(modified) < 6 * 3600,
               let data = try? Data(contentsOf: path, options: .mappedIfSafe) { return RouteShapeGeometry.parse(data) }
            let zip = try await RemoteZip(StaticFeed.url)
            guard let entry = zip.entries["shapes.txt"] else { throw URLError(.fileDoesNotExist) }
            let data = try await zip.read(entry)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: path, options: .atomic)
            return RouteShapeGeometry.parse(data)
        }
        loading = task
        do {
            let result = try await task.value
            shapes = result; loaded = .now; loading = nil
            return result
        } catch { loading = nil; throw error }
    }

    func apply(to journeys: [Journey]) async -> [Journey] {
        guard journeys.contains(where: { $0.legs.contains { $0.shapeID != nil } }),
              let shapes = try? await load() else { return journeys }
        return journeys.map { journey in
            var result = journey
            for i in result.legs.indices {
                let leg = result.legs[i]
                guard let id = leg.shapeID, let points = shapes[id] else { continue }
                let measured = leg.shapeStart.flatMap { start in leg.shapeEnd.flatMap { RouteShapeGeometry.segment(points, start: start, end: $0) } }
                guard let segment = measured ?? RouteShapeGeometry.segment(points, stops: leg.callingPoints),
                      let first = segment.first, let last = segment.last else { continue }
                let board = CLLocation(latitude: leg.board.latitude, longitude: leg.board.longitude)
                let alight = CLLocation(latitude: leg.alight.latitude, longitude: leg.alight.longitude)
                guard board.distance(from: CLLocation(latitude: first.latitude, longitude: first.longitude)) < 200,
                      alight.distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude)) < 200 else { continue }
                result.legs[i].coordinates = segment
                result.legs[i].followsShape = true
            }
            return result
        }
    }
}
