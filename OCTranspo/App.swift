import SwiftUI

@main
struct OCTranspoApp: App {
    @State private var transit = Transit.shared
    @State private var location = Location()
    @State private var screen: Screen = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-map") { return .map }
        if ProcessInfo.processInfo.arguments.contains("--preview-alerts") { return .alerts }
        #endif
        return .home
    }()
    @State private var homePath = NavigationPath()
    @Environment(\.scenePhase) private var scenePhase

    enum Screen { case home, map, alerts }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $screen) {
                HomeTab(path: $homePath)
                    .modifier(JourneyCompanionHost(handlesDeepLinks: true))
                    .tabItem { Label("Home", systemImage: "house") }
                    .tag(Screen.home)
                MapTab()
                    .modifier(JourneyCompanionHost())
                    .tabItem { Label("Map", systemImage: "map") }
                    .tag(Screen.map)
                AlertsTab()
                    .modifier(JourneyCompanionHost())
                    .tabItem { Label("Alerts", systemImage: "exclamationmark.bubble") }
                    .tag(Screen.alerts)
            }
            .onChange(of: scenePhase) { _, phase in
                JourneySession.shared.setActive(phase == .active)
                if phase == .active { Task { await location.update() } }
            }
            .environment(transit)
            .environment(location)
            .task {
                #if DEBUG
                if PlannerBenchmark.enabled { await PlannerBenchmark.run(); return }
                if JourneyDiagnostics.enabled { await JourneyDiagnostics.run(); return }
                #endif
                await JourneySession.shared.restoreIfNeeded()
                await transit.loadSchedule()
                OCTranspoShortcuts.updateAppShortcutParameters()
            }
            .task {
                #if DEBUG
                if PlannerBenchmark.enabled { return }
                #endif
                _ = try? await RoutingStore.shared.load(for: .now)
            }
            .task(id: scenePhase) {
                #if DEBUG
                if PlannerBenchmark.enabled { return }
                #endif
                guard scenePhase == .active else { return }
                await transit.loadAlerts()
                while !Task.isCancelled {
                    await transit.refreshLive()
                    await transit.loadAlerts()
                    try? await Task.sleep(for: .seconds(30))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .transitTimetableChanged)) { _ in
                Task { await transit.loadSchedule() }
            }
            .onOpenURL { url in
                if url.host() == "journey" {
                    screen = .home
                    Task {
                        await JourneySession.shared.restoreIfNeeded()
                        JourneySession.shared.openRequested = true
                    }
                    return
                }
                guard url.host() == "stop" else { return }
                Task {
                    await transit.loadScheduleIfNeeded()
                    guard let stop = transit.schedule.stop(code: url.lastPathComponent) else { return }
                    screen = .home
                    homePath = NavigationPath([stop])
                }
            }
        }
    }
}

extension View {
    func transitDestinations() -> some View {
        navigationDestination(for: Stop.self) { StopView(stop: $0) }
            .navigationDestination(for: TripRef.self) { TripView(tripID: $0.id, boardingStopCode: $0.boardingStopCode) }
    }
}
