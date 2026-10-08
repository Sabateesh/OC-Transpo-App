import Foundation
import MapKit

@MainActor private final class WalkingGate {
    var pending: [(JourneyWalk, CheckedContinuation<WalkingResult, Never>)] = []
    var immediate = false
    func check(_ walk: JourneyWalk) async -> WalkingResult {
        if immediate { var result = walk; result.verified = true; return .route(result) }
        return await withCheckedContinuation { pending.append((walk, $0)) }
    }
    func release(blocked: Bool = false) {
        immediate = true
        let batch = pending
        pending = []
        for (walk, continuation) in batch {
            var verified = walk; verified.verified = true
            continuation.resume(returning: blocked ? .blocked : .route(verified))
        }
    }
}

@main struct JourneySearchTests {
    @MainActor static func main() async throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = [
            "stops.txt": "stop_id,stop_code,stop_name,stop_lat,stop_lon\nA,A,Start,45.42,-75.70\nC,C,End,45.42,-75.64\n",
            "routes.txt": "route_id,route_short_name\n88,88\n6,6\n",
            "trips.txt": "route_id,service_id,trip_id,trip_headsign\n88,weekday,t1,East\n6,weekday,t2,East\n",
            "calendar.txt": "service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date\nweekday,1,1,1,1,1,1,1,20260901,20261031\n",
            "stop_times.txt": "trip_id,arrival_time,departure_time,stop_id,stop_sequence\nt1,08:05:00,08:05:00,A,1\nt1,08:25:00,08:25:00,C,2\nt2,08:30:00,08:30:00,A,1\nt2,08:50:00,08:50:00,C,2\n"
        ]
        for (name, content) in files { try Data(content.utf8).write(to: folder.appending(path:name)) }
        try files.keys.map { $0 + ":test" }.joined(separator:"|").write(to:folder.appending(path:"version"),atomically:true,encoding:.utf8)
        try String(Date.now.timeIntervalSince1970).write(to:folder.appending(path:"checked"),atomically:true,encoding:.utf8)
        let store = RoutingStore(folder: folder)
        let date = ISO8601DateFormatter().date(from:"2026-09-30T12:00:00Z")!
        async let sharedA = store.load(for: date)
        async let sharedB = store.load(for: date)
        let (tableA, tableB) = try await (sharedA, sharedB)
        precondition(tableA == tableB && !tableA.trips.isEmpty)
        await store.flushCache()
        let reopened = try await RoutingStore(folder: folder).load(for: date)
        precondition(reopened == tableA)
        print("PASS Concurrent timetable requests share preparation and deferred cache restores exactly")
        let nextDay = date.addingTimeInterval(86400)
        let tomorrow = try await store.load(for: nextDay)
        precondition(tomorrow.day == RoutingTimetable.dayKey(nextDay) && tomorrow.day != tableA.day)
        await store.flushCache()
        let current = try await store.load(for: date)
        precondition(current == tableA)
        await store.flushCache()
        print("PASS Date changes remain correct across deferred timetable writes")
        let start = CLLocationCoordinate2D(latitude:45.42,longitude:-75.70)
        let end = CLLocationCoordinate2D(latitude:45.42,longitude:-75.64)
        func waitForPending(_ gate: WalkingGate) async throws {
            for _ in 0..<300 {
                if gate.pending.count >= 2 { return }
                try await Task.sleep(for:.milliseconds(10))
            }
            fatalError("Search did not start walking checks")
        }
        let gate = WalkingGate()
        let search = JourneySearch(store:store,checkWalk:gate.check)
        let task = Task { await search.search(origin:start,destination:end,departure:date,live:nil) }
        try await waitForPending(gate)
        precondition(!search.loading && search.refining && !search.journeys.isEmpty,
                     "Routes must be visible while walking requests are still waiting")
        precondition(search.firstResultSeconds != nil)
        precondition(search.journeys[0].walks.allSatisfy { !$0.verified }, "Provisional walks remain marked as estimates")
        precondition(gate.pending.count == 2, "Deduplicate shared walking legs across alternatives")
        gate.release()
        await task.value
        precondition(!search.refining && search.error == nil && search.journeys[0].walks.allSatisfy(\.verified))
        print("PASS Routes appear before walking checks; refinement updates them afterward")

        let blockedGate = WalkingGate()
        let blockedSearch = JourneySearch(store:store,checkWalk:blockedGate.check)
        let blockedTask = Task { await blockedSearch.search(origin:start,destination:end,departure:date,live:nil) }
        try await waitForPending(blockedGate)
        precondition(!blockedSearch.journeys.isEmpty)
        blockedGate.release(blocked:true)
        await blockedTask.value
        precondition(blockedSearch.journeys.isEmpty && blockedSearch.error != nil, "Remove routes whose walk proves inaccessible")
        print("PASS Inaccessible walking connections remove provisional routes")

        let staleGate = WalkingGate()
        let changedSearch = JourneySearch(store:store,checkWalk:staleGate.check)
        let old = Task { await changedSearch.search(origin:start,destination:end,departure:date,live:nil) }
        try await waitForPending(staleGate)
        old.cancel()
        let laterDate = date.addingTimeInterval(600)
        let new = Task { await changedSearch.search(origin:start,destination:end,departure:laterDate,live:nil) }
        for _ in 0..<300 {
            if changedSearch.journeys.first?.requestedDeparture == laterDate { break }
            try await Task.sleep(for:.milliseconds(10))
        }
        staleGate.release()
        await old.value
        await new.value
        precondition(changedSearch.journeys.first?.requestedDeparture == laterDate)
        precondition(changedSearch.journeys.first?.legs.first?.tripID == "t2")
        precondition(!changedSearch.loading && !changedSearch.refining)
        print("PASS Cancelled searches cannot replace newer results")

        let descriptor: [UInt8] = [10, 2, 116, 49, 26, 8] + Array("20260930".utf8) + [32, 3]
        let update = [UInt8(10), UInt8(descriptor.count)] + descriptor
        let entity = [UInt8(26), UInt8(update.count)] + update
        let canceled = LiveTrips([18, UInt8(entity.count)] + entity)
        await search.search(origin:start,destination:end,departure:date,live:canceled,retainResults:true)
        precondition(search.journeys.allSatisfy { $0.legs.first?.tripID != "t1" })
        precondition(search.notices.contains { $0.contains("cancelled") } && search.updatedAt != nil && !search.refreshing)
        print("PASS Refresh removes canceled choices and explains why")
        await search.search(origin:start,destination:end,departure:date,live:nil,arriveBy:date.addingTimeInterval(30 * 60))
        precondition(!search.journeys.isEmpty && search.journeys.allSatisfy { $0.arrival <= date.addingTimeInterval(30 * 60) })
        precondition(search.notices.isEmpty)
        print("PASS Arrive-by refinement respects deadline and clears old notices")
        await search.search(origin:start,destination:end,departure:date.addingTimeInterval(600),live:nil,retainResults:true)
        precondition(search.journeys.allSatisfy { $0.leave >= date.addingTimeInterval(600) })
        precondition(search.notices.contains { $0.contains("no longer catch") })
        print("PASS Refresh removes departures that can no longer be caught")

        let beforeRefresh = search.fullSearchCount
        await search.refreshIfNeeded(origin: start, destination: end, departure: date.addingTimeInterval(610), live: nil)
        precondition(search.fullSearchCount == beforeRefresh && !search.journeys.isEmpty)
        print("PASS Unchanged departure refresh updates displayed trips without running the router")
        let descriptor2: [UInt8] = [10, 2, 116, 50, 26, 8] + Array("20260930".utf8) + [32, 3]
        let update2 = [UInt8(10), UInt8(descriptor2.count)] + descriptor2
        let entity2 = [UInt8(26), UInt8(update2.count)] + update2
        let canceled2 = LiveTrips([18, UInt8(entity2.count)] + entity2)
        await search.refreshIfNeeded(origin: start, destination: end, departure: date.addingTimeInterval(610), live: canceled2)
        precondition(search.fullSearchCount == beforeRefresh + 1 && search.journeys.allSatisfy { $0.legs.first?.tripID != "t2" })
        precondition(search.notices.contains { $0.contains("cancelled") })
        print("PASS Changed connections trigger routing and remove canceled departures")
        await store.flushCache()

    }
}
