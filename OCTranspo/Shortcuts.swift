import AppIntents

struct NextBusIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Bus"

    @Parameter(title: "Route")
    var route: RouteEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let transit = Transit.shared
        await transit.loadScheduleIfNeeded()
        await transit.refreshLive()
        if let error = transit.liveError {
            return .result(dialog: "\(error)")
        }

        let stops = transit.favourites.compactMap { favourite in
            transit.schedule.stop(code: favourite.code).map { (transit.title(for: favourite), $0) }
        }
        guard !stops.isEmpty else {
            return .result(dialog: "Add a favourite stop in the app first, then ask me again.")
        }

        for (title, stop) in stops {
            let lines = transit.upcoming(at: stop).filter { route == nil || $0.route.name == route?.id }
            guard let next = lines.first else { continue }
            let destination = next.headsign.isEmpty ? "" : " to \(next.headsign)"
            var answer = "The next \(next.route.name)\(destination) at \(title) is \(spoken(next.times[0]))."
            if next.times.count > 1 {
                answer += " The one after is \(spoken(next.times[1]))."
            }
            return .result(dialog: "\(answer)")
        }

        if let route {
            return .result(dialog: "There's no \(route.id) coming to your favourite stops right now.")
        }
        return .result(dialog: "Nothing's coming to your favourite stops right now.")
    }

    private func spoken(_ time: Date) -> String {
        let minutes = Int(time.timeIntervalSinceNow / 60)
        if minutes < 1 { return "due now" }
        if minutes == 1 { return "in 1 minute" }
        if minutes < 60 { return "in \(minutes) minutes" }
        return "at " + time.formatted(date: .omitted, time: .shortened)
    }
}

struct RouteEntity: AppEntity {
    let id: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Route"
    static let defaultQuery = RouteQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }
}

struct RouteQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [RouteEntity] {
        identifiers.map { RouteEntity(id: $0) }
    }

    func entities(matching string: String) async throws -> [RouteEntity] {
        await allRoutes().filter { $0.id.localizedCaseInsensitiveContains(string) }
    }

    func suggestedEntities() async throws -> [RouteEntity] {
        await allRoutes()
    }

    @MainActor
    private func allRoutes() async -> [RouteEntity] {
        await Transit.shared.loadScheduleIfNeeded()
        return Transit.shared.schedule.routeNames.map { RouteEntity(id: $0) }
    }
}

struct OCTranspoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NextBusIntent(),
                    phrases: [
                        "When's my next \(\.$route) in \(.applicationName)",
                        "Next \(\.$route) in \(.applicationName)",
                        "When's my bus in \(.applicationName)",
                        "Next bus in \(.applicationName)",
                    ],
                    shortTitle: "Next Bus",
                    systemImageName: "bus")
    }
}
