import Foundation
import CoreLocation

private actor DownloadGate {
    var calls = 0
    var pending: CheckedContinuation<TransitFeedStore.Download, Error>?
    func fetch(_ version: String?) async throws -> TransitFeedStore.Download {
        calls += 1
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func finish(_ value: TransitFeedStore.Download) { pending?.resume(returning: value); pending = nil }
    func fail() { pending?.resume(throwing: URLError(.notConnectedToInternet)); pending = nil }
}

@main struct TransitSpeedTests {
    static func main() async throws {
        var count = 0
        func check(_ value: Bool, _ name: String) { precondition(value, name); count += 1; print("PASS", name) }
        func files(arrival: String = "08:25:00") -> [String: Data] {
            ["stops.txt": "stop_id,stop_code,stop_name,stop_lat,stop_lon\nA,A,Start,45.42,-75.70\nB,B,End,45.42,-75.64\n",
             "routes.txt": "route_id,route_short_name\n88,88\n",
             "trips.txt": "route_id,service_id,trip_id,trip_headsign\n88,weekday,t1,East\n",
             "calendar.txt": "service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date\nweekday,1,1,1,1,1,1,1,20260901,20261031\n",
             "calendar_dates.txt": "service_id,date,exception_type\nweekday,20261004,2\n",
             "stop_times.txt": "trip_id,arrival_time,departure_time,stop_id,stop_sequence,shape_dist_traveled\nt1,08:05:00,08:05:00,A,1,0\nt1,\(arrival),\(arrival),B,2,4000\n"].mapValues { Data($0.utf8) }
        }
        let date = ISO8601DateFormatter().date(from: "2026-10-03T12:00:00Z")!
        let expired = ISO8601DateFormatter().date(from: "2026-11-03T12:00:00Z")!
        let feed = try PreparedTransitFeed(files: files())
        let restored = try PreparedTransitFeed.decode(feed.encoded())
        check(try RoutingTimetable(prepared: restored, date: date) == RoutingTimetable(files: files(), date: date), "Packed feed preserves every timetable call")
        check(restored.covers(date) && !restored.covers(expired), "Bundled coverage expires at published calendar boundary")
        check(restored.activeServices(on: date.addingTimeInterval(86400)).isEmpty, "Bundled data retains calendar exceptions")
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appending(path: "Bundled.transit")
        try feed.encoded().write(to: bundle)
        let gate = DownloadGate()
        let source = TransitFeedStore(folder: root.appending(path: "cache"), bundleURL: bundle, downloader: { try await gate.fetch($0) })
        async let home = source.load()
        async let planner = source.load(for: date)
        let (homeFeed, plannerFeed) = try await (home, planner)
        check(homeFeed.version == plannerFeed.version && plannerFeed.bundled, "Home and planner share bundled feed without waiting on network")
        for _ in 0..<100 { if await gate.calls > 0 { break }; try await Task.sleep(for: .milliseconds(10)) }
        check(await gate.calls == 1, "Concurrent consumers coalesce background download")
        let store = RoutingStore(source: source)
        async let first = store.network(for: date)
        async let second = store.network(for: date)
        let (a, b) = try await (first, second)
        check(a.index === b.index, "Concurrent searches reuse one immutable routing index")
        let updated = try PreparedTransitFeed(files: files(arrival: "08:35:00"))
        await gate.finish(.init(feed: updated, version: "new"))
        var newest = a
        for _ in 0..<100 {
            newest = try await store.network(for: date)
            if newest.version == "new" { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        check(newest.version == "new" && newest.index !== a.index, "Background feed change replaces stale routing indexes")
        let newTrip = newest.timetable.trips.first { $0.serviceDate == "20261003" }!
        check(newTrip.calls.last!.arrival == date.addingTimeInterval(35 * 60), "Searches see refreshed trip times")
        await source.flushCache()
        let offline = TransitFeedStore(folder: root.appending(path: "cache"), bundleURL: nil, downloader: { _ in throw URLError(.notConnectedToInternet) })
        check(try await offline.load(for: date).version == "new", "Persisted prepared timetable reopens offline")
        let cachedFile = root.appending(path: "cache/prepared.plist")
        var disk = try PropertyListSerialization.propertyList(from: Data(contentsOf: cachedFile), format: nil) as! [String: Any]
        disk["checkedAt"] = Date.now.addingTimeInterval(-7 * 3600)
        try PropertyListSerialization.data(fromPropertyList: disk, format: .binary, options: 0).write(to: cachedFile)
        let staleGate = DownloadGate()
        let staleSource = TransitFeedStore(folder: root.appending(path: "cache"), bundleURL: nil, downloader: { try await staleGate.fetch($0) })
        let staleValue = try await staleSource.load(for: date)
        check(staleValue.version == "new", "A stale but valid disk timetable returns before its network check")
        for _ in 0..<100 { if await staleGate.calls > 0 { break }; try await Task.sleep(for: .milliseconds(10)) }
        await staleGate.fail()
        let afterFailure = try await staleSource.load(for: date)
        check(afterFailure.version == "new" && afterFailure.feed.covers(date), "Refresh failure preserves usable cached service")
        await staleSource.flushCache()
        let otherDay = try await store.network(for: date.addingTimeInterval(86400))
        check(otherDay.index.geometry === newest.index.geometry, "Different service dates reuse the same stop and transfer geometry")
        let expiredSource = TransitFeedStore(folder: root.appending(path: "expired"), bundleURL: bundle, downloader: { _ in throw URLError(.notConnectedToInternet) })
        do { _ = try await expiredSource.load(for: expired); check(false, "Expired bundle must not produce routes") }
        catch let error as TransitTimetableError {
            check(error.errorDescription?.contains("Oct 31, 2026") == true, "Expired bundle explains the last available service day")
        }
        catch { check(false, "Expired bundle must report timetable coverage") }
        await expiredSource.flushCache()
        let corruptFolder = root.appending(path: "corrupt")
        try FileManager.default.createDirectory(at: corruptFolder, withIntermediateDirectories: true)
        try Data("bad cache".utf8).write(to: corruptFolder.appending(path: "prepared.plist"))
        let corrupt = TransitFeedStore(folder: corruptFolder, bundleURL: bundle, downloader: { _ in throw URLError(.notConnectedToInternet) })
        check(try await corrupt.load(for: date).feed.covers(date), "Damaged disk cache falls back to a valid bundled timetable")
        await corrupt.flushCache()
        let legacyFolder = root.appending(path: "legacy")
        try FileManager.default.createDirectory(at: legacyFolder, withIntermediateDirectories: true)
        try "matching".write(to: bundle.deletingPathExtension().appendingPathExtension("version"), atomically: true, encoding: .utf8)
        try "matching".write(to: legacyFolder.appending(path: "version"), atomically: true, encoding: .utf8)
        try String(Date.now.timeIntervalSince1970).write(to: legacyFolder.appending(path: "checked"), atomically: true, encoding: .utf8)
        let legacy = TransitFeedStore(folder: legacyFolder, bundleURL: bundle, downloader: { _ in throw URLError(.notConnectedToInternet) })
        check(try await legacy.load(for: date).version == "matching", "Matching legacy version uses the bundle without parsing raw CSV")
        await legacy.flushCache()
        let oldFiles = files().mapValues { Data(String(decoding: $0, as: UTF8.self).replacingOccurrences(of: "20260901", with: "20260801").replacingOccurrences(of: "20261031", with: "20260831").replacingOccurrences(of: "20261004", with: "20260804").utf8) }
        let oldFeed = try PreparedTransitFeed(files: oldFiles)
        var oldDisk = disk; oldDisk["version"] = "expired"; oldDisk["payload"] = try oldFeed.encoded()
        try PropertyListSerialization.data(fromPropertyList: oldDisk, format: .binary, options: 0).write(to: legacyFolder.appending(path: "prepared.plist"))
        let upgraded = TransitFeedStore(folder: legacyFolder, bundleURL: bundle, downloader: { _ in throw URLError(.notConnectedToInternet) })
        check(try await upgraded.load(for: date).feed.covers(date), "New bundled service replaces an expired downloaded cache offline")
        await upgraded.flushCache()
        let point = CLLocation(latitude: 45.42, longitude: -75.7)
        let indexed = Set(a.index.geometry.near(point, radius: 1600).map(\.0))
        let brute = Set(a.index.geometry.points.indices.filter { point.distance(from: a.index.geometry.points[$0]) <= 1600 })
        check(indexed == brute, "Spatial index returns every stop inside walking radius")
        print("Passed \(count) transit speed scenarios")
    }
}
