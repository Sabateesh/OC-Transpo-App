import MapKit
import Observation

@MainActor @Observable
final class JourneySearch {
    private(set) var journeys: [Journey] = []
    private(set) var loading = false
    private(set) var refining = false
    private(set) var notices: [String] = []
    private(set) var updatedAt: Date?
    private(set) var refreshing = false
    private(set) var status = ""
    private(set) var error: String?
    private(set) var scheduledOnly = true
    private(set) var firstResultSeconds: TimeInterval?
    @ObservationIgnored private let store: RoutingStore
    @ObservationIgnored private let checkWalk: @MainActor (JourneyWalk) async throws -> WalkingResult
    private var generation = UUID()
    private var baselineJourneys: [Journey] = []
    private var timetableVersion: String?
    private var lastOrigin: CLLocationCoordinate2D?
    private var lastDestination: CLLocationCoordinate2D?
    private var lastDeadline: Date?
    private var lastSearchAt = Date.distantPast
    private var hadLive = false
    private var lastAccessibleVehiclesOnly = false
    private var lastAlertsSignature = ""
    private(set) var fullSearchCount = 0

    init(store: RoutingStore = .shared,
         checkWalk: (@MainActor (JourneyWalk) async throws -> WalkingResult)? = nil) {
        self.store = store
        self.checkWalk = checkWalk ?? { try await WalkingRoutes.shared.check($0) }
    }

    func search(origin: CLLocationCoordinate2D, destination: CLLocationCoordinate2D,
                departure: Date, live: LiveTrips?, refresh: Bool = false, arriveBy: Date? = nil, retainResults: Bool = false,
                accessibleVehiclesOnly: Bool = false, alerts: [ServiceAlert] = []) async {
        let token = UUID()
        let started = Date.now
        generation = token
        fullSearchCount += 1
        baselineJourneys = []
        lastOrigin = origin
        lastDestination = destination
        lastDeadline = arriveBy
        hadLive = live != nil
        lastAccessibleVehiclesOnly = accessibleVehiclesOnly
        lastSearchAt = .now
        lastAlertsSignature = Self.alertsSignature(alerts)
        let previous = journeys
        if !retainResults { notices = [] }
        if retainResults, let live {
            for message in previous.flatMap({ $0.cancellationNotices(in: live, now: .now) }) where !notices.contains(message) { notices.append(message) }
        }
        if retainResults {
            journeys.removeAll { !$0.canStart(at: departure, live: live) }
            if journeys.count < previous.count && notices.isEmpty { notices = ["Departures you can no longer catch have been removed."] }
        } else { journeys = [] }
        loading = journeys.isEmpty
        refreshing = retainResults
        refining = false
        firstResultSeconds = nil
        error = nil
        scheduledOnly = live == nil
        status = "Loading the timetable…"
        defer {
            if generation == token {
                loading = false
                refining = false
                refreshing = false
            }
        }
        var filteredForDetour = false
        do {
            let network = try await store.network(for: arriveBy ?? departure, refresh: refresh)
            let timetable = network.timetable
            try Task.checkCancellation()
            guard generation == token else { return }
            timetableVersion = network.version + ":" + timetable.day
            var walks: [WalkKey: JourneyWalk] = [:]
            var blocked: Set<WalkKey> = []
            for pass in 0..<3 {
                status = pass == 0 ? "Comparing routes and transfers…" : "Updating walking connections…"
                let knownWalks = walks, blockedWalks = blocked
                let worker = Task.detached(priority: .userInitiated) {
                    JourneyPlanner.plan(timetable: timetable, origin: origin, destination: destination,
                                        departure: departure, walks: knownWalks, blocked: blockedWalks, live: live, arriveBy: arriveBy, index: network.index, accessibleVehiclesOnly: accessibleVehiclesOnly)
                }
                let options = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                guard generation == token else { return }
                let allowed = options.filter { trip in
                    !alerts.contains(where: { $0.closesJourneyStop(trip) })
                }
                filteredForDetour = filteredForDetour || allowed.count < options.count
                journeys = JourneyRanking.distinctOptions(allowed)
                updatedAt = .now
                scheduledOnly = !journeys.contains { $0.legs.contains { $0.live } }
                if !journeys.isEmpty && firstResultSeconds == nil { firstResultSeconds = Date.now.timeIntervalSince(started) }
                loading = false
                refining = !journeys.isEmpty && pass < 2
                if pass == 2 || journeys.isEmpty { break }
                status = "Checking walking connections — routes may update"
                var pending: [JourneyWalk] = []
                var seen: Set<WalkKey> = []
                for journey in journeys.prefix(3) {
                    for walk in journey.walks where walks[walk.key] == nil && !blocked.contains(walk.key) && seen.insert(walk.key).inserted {
                        pending.append(walk)
                    }
                }
                var changed = false
                for start in stride(from: 0, to: pending.count, by: 3) {
                    try Task.checkCancellation()
                    guard generation == token else { return }
                    let batch = Array(pending[start..<min(start + 3, pending.count)])
                    let checkWalk = checkWalk
                    let results = try await withThrowingTaskGroup(of: (JourneyWalk, WalkingResult).self) { group in
                        for walk in batch {
                            group.addTask { @MainActor in (walk, try await checkWalk(walk)) }
                        }
                        var results: [(JourneyWalk, WalkingResult)] = []
                        for try await result in group { results.append(result) }
                        return results
                    }
                    try Task.checkCancellation()
                    guard generation == token else { return }
                    for (walk, result) in results {
                        switch result {
                        case .blocked:
                            blocked.insert(walk.key)
                            changed = true
                        case .route(let verified):
                            if verified.duration > (walk.key.from == -1 || walk.key.to == -2 ? 25 * 60 : 12 * 60) {
                                blocked.insert(walk.key)
                                changed = true
                            } else {
                                walks[walk.key] = verified
                                changed = changed || verified.verified
                            }
                        }
                    }
                }
                if !changed { break }
            }
            baselineJourneys = journeys
            if journeys.isEmpty {
                error = accessibleVehiclesOnly
                    ? "No trip with a confirmed wheelchair-accessible vehicle fits this search. Try another time or turn off the vehicle filter. Stop and walking access may still be unknown."
                    : filteredForDetour
                        ? "No safe boarding and alighting stop remains among these connections. A published detour may have closed a stop; check the alert and try another stop or time."
                        : arriveBy == nil ? "No connection fits this starting point and departure time in the next 24 hours. Try a different time or starting point." : "No trip can reach your destination by that time. Try a later arrival or a different starting point."
            }
        } catch is CancellationError {
            return
        } catch {
            if generation == token { self.error = "Couldn't load the timetable. \(error.localizedDescription)" }
        }
    }

    func refreshIfNeeded(origin: CLLocationCoordinate2D, destination: CLLocationCoordinate2D, departure: Date, live: LiveTrips?, arriveBy: Date? = nil,
                         accessibleVehiclesOnly: Bool = false, alerts: [ServiceAlert] = []) async {
        guard !loading, !refining, !refreshing else { return }
        let token = generation
        func distance(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D) -> Double {
            guard let a else { return .infinity }
            return CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        }
        let network = try? await store.network(for: arriveBy ?? departure)
        guard token == generation, !Task.isCancelled else { return }
        var next = baselineJourneys.map { trip in
            var result = trip
            result.legs = trip.legs.map { $0.withPredictions(live) }
            return result
        }
        let canceled = live.map { feed in next.flatMap { $0.cancellationNotices(in: feed, now: departure) } } ?? []
        for message in canceled where !notices.contains(message) { notices.append(message) }
        let count = next.count
        next.removeAll { trip in
            if !trip.canStart(at: departure, live: live) || (arriveBy.map { trip.arrival > $0 } ?? false) || alerts.contains(where: { $0.closesJourneyStop(trip) }) { return true }
            if trip.legs.contains(where: { $0.skips($0.callingPoints.first, live: live) || $0.skips($0.callingPoints.last, live: live) }) { return true }
            return zip(trip.legs, trip.legs.dropFirst()).contains { first, second in first.arrival.addingTimeInterval(max(180, second.walk.duration + 120)) > second.departure }
        }
        let invalidated = next.count < count
        journeys = next
        updatedAt = .now
        scheduledOnly = live == nil || !next.contains { $0.legs.contains(where: \.live) }
        if invalidated && notices.isEmpty { notices = ["Departures you can no longer catch have been removed."] }
        let version = network.map { $0.version + ":" + $0.timetable.day }
        let changed = distance(lastOrigin, origin) > 75 || distance(lastDestination, destination) > 1 || lastDeadline != arriveBy || timetableVersion != version || hadLive != (live != nil) || lastAccessibleVehiclesOnly != accessibleVehiclesOnly || lastAlertsSignature != Self.alertsSignature(alerts)
        guard changed || invalidated || next.isEmpty || Date.now.timeIntervalSince(lastSearchAt) >= 120 else { return }
        await search(origin: origin, destination: destination, departure: departure, live: live, arriveBy: arriveBy, retainResults: true, accessibleVehiclesOnly: accessibleVehiclesOnly, alerts: alerts)
    }

    private static func alertsSignature(_ alerts: [ServiceAlert]) -> String {
        alerts.map { $0.id + ":" + ($0.closedStops ?? []).sorted().joined(separator: ",") }.sorted().joined(separator: "|")
    }

}
