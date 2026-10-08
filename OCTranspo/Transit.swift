import Foundation
import Observation
import WidgetKit

@MainActor @Observable
final class Transit {
    static let shared = Transit()

    private(set) var schedule = Schedule()
    private(set) var loadError: String?
    private(set) var scheduleValidThrough: String?

    private(set) var live = LiveTrips()
    private(set) var vehicles: [Vehicle] = []
    private(set) var liveUpdated: Date?
    private(set) var liveError: String?

    private(set) var alerts: [ServiceAlert] = []
    private(set) var alertsFailed = false
    private(set) var alertsUpdated: Date?
    @ObservationIgnored private var loadingAlerts: Task<Void, Never>?
    @ObservationIgnored private var lastAlertRequest = Date.distantPast

    init() {
        if let saved = ServiceAlertSnapshot.load() {
            alerts = saved.alerts; alertsUpdated = saved.updatedAt
        }
    }

    var favourites = Transit.savedFavourites() {
        didSet { saveFavourites() }
    }
    var pinnedRoutes = Set(AppGroup.defaults.stringArray(forKey: "pinnedRoutes") ?? []) {
        didSet { AppGroup.defaults.set(Array(pinnedRoutes).sorted(), forKey: "pinnedRoutes") }
    }

    @ObservationIgnored private var loadingSchedule: Task<Void, Never>?
    @ObservationIgnored private var refreshing: Task<Void, Never>?


    @ObservationIgnored private var scheduleVersion: String?
    func loadSchedule(force: Bool = false) async {
        if let loadingSchedule { return await loadingSchedule.value }
        let task = Task {
            loadError = nil
            do {
                let snapshot = try await TransitFeedStore.shared.load(refresh: force)
                scheduleValidThrough = snapshot.feed.validThrough
                if scheduleVersion != snapshot.version {
                    schedule = await Task.detached(priority: .userInitiated) { Schedule(snapshot.feed) }.value
                    scheduleVersion = snapshot.version
                    await TransitFeedStore.shared.flushCache()
                    syncWidget()
                }
            } catch { if schedule.stops.isEmpty || force { loadError = error.localizedDescription } }
        }
        loadingSchedule = task; await task.value; loadingSchedule = nil
    }

    func loadScheduleIfNeeded() async {
        if schedule.stops.isEmpty { await loadSchedule() }
    }


    func refreshLive() async {
        if let refreshing { return await refreshing.value }
        let task = Task {
            do {
                async let trips = Feed.download(Feed.tripUpdates)
                async let positions = try? Feed.download(Feed.vehiclePositions)
                let (tripFeed, positionFeed) = try await (trips, positions)
                let decoded = await Task.detached {
                    (LiveTrips(tripFeed), positionFeed.map(Vehicle.decode) ?? [])
                }.value
                live = decoded.0
                vehicles = decoded.1
                liveUpdated = .now
                liveError = nil
            } catch {
                liveError = error.localizedDescription
            }
        }
        refreshing = task
        await task.value
        refreshing = nil
    }

    func upcoming(at stop: Stop) -> [Upcoming] {
        live.upcoming(at: stop.ids, route: schedule.route, headsign: headsign(for:))
    }

    func headsign(for tripID: String) -> String? {
        schedule.headsigns[tripID]
            ?? live.trips[tripID]?.stops.last.flatMap { schedule.stop(id: $0.stopID)?.name }
    }

    func route(of vehicle: Vehicle) -> Route {
        schedule.route(vehicle.routeID.isEmpty ? live.trips[vehicle.tripID]?.routeID ?? "" : vehicle.routeID)
    }

    func vehicle(onTrip tripID: String) -> Vehicle? {
        vehicles.first { $0.tripID == tripID }
    }
    func crowding(for tripID: String) -> String? {
        guard liveError == nil, let liveUpdated, Date.now.timeIntervalSince(liveUpdated) < 120,
              let vehicle = vehicle(onTrip: tripID), let timestamp = vehicle.timestamp,
              abs(Date.now.timeIntervalSince(timestamp)) < 120 else { return nil }
        return vehicle.occupancy?.label
    }

    func togglePinnedRoute(_ route: String) {
        if pinnedRoutes.contains(route) { pinnedRoutes.remove(route) }
        else { pinnedRoutes.insert(route) }
    }


    func loadAlerts(force: Bool = false) async {
        if let loadingAlerts { await loadingAlerts.value; return }
        guard force || Date.now.timeIntervalSince(lastAlertRequest) >= 300 else { return }
        lastAlertRequest = .now
        let task = Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: ServiceAlert.feed)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let parsed = AlertFeedParser.parse(data) else { throw URLError(.badServerResponse) }
                alerts = parsed; alertsUpdated = .now; alertsFailed = false
                ServiceAlertSnapshot(alerts: parsed, updatedAt: .now).save()
            } catch { alertsFailed = true }
        }
        loadingAlerts = task; await task.value; loadingAlerts = nil
    }

    func alerts(for journey: Journey, startingAt index: Int = 0) -> [ServiceAlert] {
        alerts.filter { $0.affects(journey, startingAt: index) }
    }

    func alerts(for stop: Stop, routes: Set<String>) -> [ServiceAlert] {
        alerts.filter { !$0.routes.isDisjoint(with: routes) || $0.stops.contains(stop.code) }
    }


    func isFavourite(_ stop: Stop) -> Bool {
        favourites.contains { $0.code == stop.code }
    }

    func toggleFavourite(_ stop: Stop) {
        if let i = favourites.firstIndex(where: { $0.code == stop.code }) {
            favourites.remove(at: i)
        } else {
            favourites.append(Favourite(code: stop.code))
        }
    }

    func rename(_ favourite: Favourite, to name: String) {
        guard let i = favourites.firstIndex(of: favourite) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        favourites[i].nickname = trimmed.isEmpty ? nil : trimmed
    }

    func title(for favourite: Favourite) -> String {
        favourite.nickname ?? schedule.stop(code: favourite.code)?.name ?? "Stop \(favourite.code)"
    }

    private func saveFavourites() {
        AppGroup.defaults.set(try? JSONEncoder().encode(favourites), forKey: "favourites")
        syncWidget()
    }

    private func syncWidget() {
        guard !schedule.stops.isEmpty else { return }
        AppGroup.pinnedStops = favourites.compactMap { favourite in
            schedule.stop(code: favourite.code).map { PinnedStop(title: favourite.nickname ?? $0.name, stop: $0) }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func savedFavourites() -> [Favourite] {
        if let data = AppGroup.defaults.data(forKey: "favourites"),
           let saved = try? JSONDecoder().decode([Favourite].self, from: data) {
            return saved
        }
        let old = UserDefaults.standard.stringArray(forKey: "favourites")
            ?? UserDefaults.standard.stringArray(forKey: "FavoriteStops")
            ?? []
        return old.map { Favourite(code: $0) }
    }
}
