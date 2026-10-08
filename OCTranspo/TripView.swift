import MapKit
import SwiftUI

struct TripRef: Hashable {
    let id: String
    var boardingStopCode: String? = nil
}

struct TripView: View {
    let tripID: String
    var boardingStopCode: String? = nil
    @Environment(Transit.self) private var transit
    @State private var position = MapCameraPosition.automatic
    @State private var alreadyAboard = false
    @State private var showGuide = false
    @State private var starting = false
    @State private var startError: String?
    @State private var path: [CLLocationCoordinate2D]?
    @State private var pendingDestination: Destination?
    @State private var replanDestination: Destination?
    @State private var replanOrigin: Destination?

    var body: some View {
        let trip = transit.live.trips[tripID]
        let route = transit.schedule.route(trip?.routeID ?? "")
        let headsign = transit.headsign(for: tripID) ?? ""
        let vehicle = transit.vehicle(onTrip: tripID)
        let stops = remainingStops(trip)
        let lineColor = Color(hex: route.color) ?? .accentColor
        let detours = transit.alerts.filter { alert in
            alert.routes.contains(route.name) && alert.activeFrom.map { $0 <= Date.now } == true
                && (alert.activeThrough.map { Date.now <= $0 } == true || alert.details?.localizedCaseInsensitiveContains("until further notice") == true)
        }
        let closed = Set(detours.flatMap { Array($0.closedStops ?? []) })
        let alternatives = Set(detours.flatMap { Array($0.alternativeStops ?? []) })

        VStack(spacing: 0) {
            Map(position: $position) {
                UserAnnotation()
                if let path, path.count > 1 {
                    if detours.isEmpty { MapPolyline(coordinates: path).stroke(lineColor, lineWidth: 4) }
                    else { MapPolyline(coordinates: path).stroke(.orange, style: StrokeStyle(lineWidth: 4, dash: [8, 6])) }
                }
                ForEach(stops) { item in
                    Annotation(item.stop.name, coordinate: item.stop.coordinate) {
                        Image(systemName: closed.contains(item.stop.code) ? "xmark.circle.fill" : "circle.fill")
                            .foregroundStyle(closed.contains(item.stop.code) ? .orange : lineColor)
                            .background(Circle().fill(.white)).frame(width: 14, height: 14)
                    }
                    .annotationTitles(.hidden)
                }
                ForEach(alternatives.sorted(), id: \.self) { code in
                    if let stop = transit.schedule.stop(code: code) {
                        Marker("Alternative stop \(code)", systemImage: "figure.walk.circle", coordinate: stop.coordinate).tint(.green)
                    }
                }
                if let vehicle {
                    Annotation(route.name, coordinate: vehicle.coordinate) {
                        RouteBadge(route: route).shadow(radius: 3)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .frame(height: 300)
            if !detours.isEmpty {
                Text("Dashed line shows the scheduled path. Check the published detour map for the temporary route.")
                    .font(.caption).foregroundStyle(.orange).padding(.horizontal)
                ForEach(detours.filter { $0.publishedMap != nil }) { alert in
                    if let map = alert.publishedMap { Link("Open published detour map", destination: map).font(.caption.bold()) }
                }
            } else if path == nil {
                Text("Stop markers shown while the published route shape loads.").font(.caption).foregroundStyle(.secondary)
            }

            List {
                Section {
                    Toggle("I'm already on this bus", isOn: $alreadyAboard)
                    Text(alreadyAboard ? "Choose where you'll get off. Guidance begins on board." : "Choose where to get off after boarding at \(boardingStopCode ?? stops.first?.stop.code ?? "your stop").")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Stops and guidance") {
                    ForEach(Array(stops.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 10) {
                            NavigationLink(value: item.stop) {
                                HStack { Text(item.stop.name); Spacer(); Text(arrivalLabel(item.time)).monospacedDigit().foregroundStyle(.secondary) }
                            }
                            if index > boardingIndex(in: stops) {
                                Button("GO") { Task { await startJourney(to: item.stop, trip: trip) } }
                                    .buttonStyle(.borderedProminent).disabled(starting)
                                    .accessibilityLabel("Start guidance to \(item.stop.name)")
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .overlay {
            if trip == nil {
                ContentUnavailableView("This trip is done",
                                       systemImage: "flag.checkered",
                                       description: Text("It's no longer in OC Transpo's live feed."))
            }
        }
        .navigationTitle(headsign.isEmpty ? "Route \(route.name)" : "\(route.name) \(headsign)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem {
                Button { transit.togglePinnedRoute(route.name) } label: {
                    Image(systemName: transit.pinnedRoutes.contains(route.name) ? "pin.fill" : "pin")
                }.accessibilityLabel(transit.pinnedRoutes.contains(route.name) ? "Unpin route" : "Pin route")
            }
        }
        .refreshable { await transit.refreshLive() }
        .task(id: tripID) { await loadPath() }
        .alert("Couldn't start guidance", isPresented: Binding(get: { startError != nil }, set: { if !$0 { startError = nil } })) {
            Button("OK") { startError = nil }
        } message: { Text(startError ?? "") }
        .fullScreenCover(isPresented: $showGuide, onDismiss: {
            replanDestination = pendingDestination
            pendingDestination = nil
        }) {
            JourneyGuideView { here in
                pendingDestination = JourneySession.shared.destination
                replanOrigin = here.map { location in
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
                    item.name = "Current location"
                    return Destination(item: item)
                }
            }
        }
        .sheet(item: $replanDestination) { destination in
            DestinationView(destination: destination, startingPoint: replanOrigin)
        }
    }

    private struct TripStop: Identifiable {
        let stop: Stop
        let time: Date
        var id: String { stop.code + "@\(time.timeIntervalSince1970)" }
    }

    private func remainingStops(_ trip: LiveTrips.Trip?) -> [TripStop] {
        var result: [TripStop] = []
        let cutoff = Date.now.addingTimeInterval(-10)
        for stopTime in trip?.stops ?? [] where stopTime.time > cutoff {
            guard let stop = transit.schedule.stop(id: stopTime.stopID), stop.code != result.last?.stop.code else { continue }
            result.append(TripStop(stop: stop, time: stopTime.time))
        }
        return result
    }
    private func boardingIndex(in stops: [TripStop]) -> Int {
        if alreadyAboard { return 0 }
        return stops.firstIndex(where: { $0.stop.code == boardingStopCode }) ?? 0
    }
    @MainActor private func startJourney(to alight: Stop, trip: LiveTrips.Trip?) async {
        guard let trip, !transit.live.isCanceled(tripID: trip.id, serviceDate: trip.serviceDate ?? RoutingTimetable.dayKey(.now), now: .now) else {
            startError = "This departure is no longer available. Refresh the line and choose another."; return
        }
        starting = true; defer { starting = false }
        let table = try? await RoutingStore.shared.network(for: .now).timetable
        guard let journey = JourneyQuickStart.make(trip: trip, schedule: transit.schedule, alightCode: alight.code,
                                                    boardingCode: boardingStopCode, alreadyAboard: alreadyAboard,
                                                    timetable: table) else {
            startError = "Choose a stop later on this trip, then try again."; return
        }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: alight.coordinate)); item.name = alight.name
        JourneySession.shared.start(journey, destination: Destination(item: item))
        if alreadyAboard { JourneySession.shared.board() }
        showGuide = true
    }
    @MainActor private func loadPath() async {
        guard let trip = transit.live.trips[tripID], let first = remainingStops(trip).first,
              let last = remainingStops(trip).last else { return }
        let table = try? await RoutingStore.shared.network(for: .now).timetable
        guard let journey = JourneyQuickStart.make(trip: trip, schedule: transit.schedule, alightCode: last.stop.code,
                                                    boardingCode: first.stop.code, alreadyAboard: false, timetable: table),
              let shaped = await RouteShapes.shared.apply(to: [journey]).first,
              shaped.legs.first?.followsShape == true else { return }
        path = shaped.legs.first?.coordinates
    }
}
