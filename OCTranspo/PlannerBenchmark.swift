#if DEBUG
import Foundation
import MapKit

@MainActor enum PlannerBenchmark {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--planner-benchmark") }
    static func run() async {
        let root = URL.documentsDirectory.appending(path: "planner-benchmark", directoryHint: .isDirectory)
        let cache = root.appending(path: "cache", directoryHint: .isDirectory)
        let report = root.appending(path: "results.json")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let date = ISO8601DateFormatter().date(from: "2026-10-02T12:00:00Z")!
        let origin = CLLocationCoordinate2D(latitude: 45.4215, longitude: -75.6972)
        let destination = CLLocationCoordinate2D(latitude: 45.3488, longitude: -75.7549)
        var results: [[String: Any]] = []
        let store = RoutingStore(folder: cache)
        for index in 0..<3 {
            let search = JourneySearch(store: store, checkWalk: { .route($0) })
            let started = Date.now
            await search.search(origin: origin, destination: destination, departure: date, live: nil)
            results.append(["stage": index == 0 ? "cold" : "repeat-\(index)", "firstResultSeconds": search.firstResultSeconds ?? -1, "totalSeconds": Date.now.timeIntervalSince(started), "routes": search.journeys.count, "error": search.error ?? ""])
            if let data = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: report, options: .atomic) }
        }
        await store.flushCache()
        let search = JourneySearch(store: RoutingStore(folder: cache), checkWalk: { .route($0) })
        let started = Date.now
        await search.search(origin: origin, destination: destination, departure: date, live: nil)
        results.append(["stage": "disk-reopen", "firstResultSeconds": search.firstResultSeconds ?? -1, "totalSeconds": Date.now.timeIntervalSince(started), "routes": search.journeys.count, "error": search.error ?? ""])
        if let data = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: report, options: .atomic) }
    }
}
#endif
