import MapKit
import SwiftUI

struct DestinationView: View {
    let destination: Destination
    @Environment(Transit.self) private var transit
    @Environment(Location.self) private var location
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var target: Destination?
    @State private var origin: Destination?
    @State private var search = JourneySearch()
    @State private var departure = Date.now
    @State private var timeMode = JourneyTimeMode.now
    @State private var revision = 0
    @State private var refresh = false
    @State private var picker: PlaceField?
    @State private var selectedJourney: String?
    @State private var customized: Journey?
    @State private var departureSelection: LegSelection?
    @State private var shaped: Journey?
    @State private var showGuide = false
    @State private var companion = JourneySession.shared
    @State private var originError: String?
    @State private var saved = SavedDestinations.shared
    @State private var accessibleVehiclesOnly = UserDefaults.standard.bool(forKey: "accessibleVehiclesOnly")

    init(destination: Destination, startingPoint: Destination? = nil) {
        self.destination = destination
        _origin = State(initialValue: startingPoint)
    }

    private enum PlaceField: String, Identifiable { case from, to; var id: String { rawValue } }
    private struct LegSelection: Identifiable {
        let index: Int
        let journey: Journey
        var id: String { journey.id + ":" + String(index) }
    }
    private var end: Destination { target ?? destination }
    private var startCoordinate: CLLocationCoordinate2D? { origin?.item.placemark.coordinate ?? location.current?.coordinate }
    private var selected: Journey? { search.journeys.first { $0.id == selectedJourney } ?? search.journeys.first }
    private var freshLive: LiveTrips? {
        guard let updated = transit.liveUpdated, Date.now.timeIntervalSince(updated) < 120, transit.liveError == nil else { return nil }
        return transit.live
    }
    private func mapJourney(_ journey: Journey) -> Journey {
        guard let shaped, shaped.id == journey.id else { return journey }
        var result = journey
        for i in result.legs.indices where i < shaped.legs.count {
            result.legs[i].coordinates = shaped.legs[i].coordinates
            result.legs[i].followsShape = shaped.legs[i].followsShape
        }
        return result
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let searched = search.journeys.filter { $0.canStart(at: context.date, live: freshLive) }
                let choices = (customized.map { trip in
                    var updated = trip
                    updated.legs = trip.legs.map { $0.withPredictions(freshLive) }
                    let valid = updated.canStart(at: context.date, live: freshLive)
                        && !JourneyConnection.all(in: updated).contains(where: \.isMissed)
                        && !transit.alerts.contains(where: { $0.closesJourneyStop(updated) })
                    return valid ? [updated] : []
                } ?? [])
                    + searched.filter { $0.id != customized?.id }
                let selection = choices.first { $0.id == selectedJourney } ?? choices.first
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        journeyFields
                        ForEach(search.notices, id: \.self) { notice in
                            Label(notice, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(.orange)
                        }
                        if originError != nil {
                            LocationRecoveryView { picker = .from }
                        } else if search.loading {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text(search.status).font(.headline)
                                Text("Preparing Ottawa's timetable. Future searches use the saved copy.")
                                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }.frame(maxWidth: .infinity).padding(.vertical, 35)
                        } else if let error = search.error, choices.isEmpty {
                            ContentUnavailableView("Let's adjust your trip", systemImage: "bus", description: Text(error))
                            Button("Refresh timetable & retry") { refresh = true; revision += 1 }.buttonStyle(.borderedProminent)
                        } else {
                            PredictionStatusView(status: .init(hasPredictions: choices.contains { $0.legs.contains { $0.live } },
                                                               feedAvailable: freshLive != nil, updatedAt: transit.liveUpdated, predictionsAreCurrent: choices.contains { $0.legs.contains { $0.matchingUpdate(freshLive)?.stops.isEmpty == false } }))
                            if search.refining || search.refreshing {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text(search.refining ? search.status : "Refreshing departures…").font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            if let selection {
                                let display = mapJourney(selection)
                                JourneyMap(journey: display).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 18)).id(selection.id)
                                if !display.legs.allSatisfy(\.followsShape) {
                                    Text("Stop markers shown where route paths are unavailable or still loading.").font(.caption).foregroundStyle(.secondary)
                                }
                                Button {
                                    if !companion.matches(display, destination: end) { companion.start(display, destination: end) }
                                    showGuide = true
                                } label: {
                                    HStack {
                                        Image(systemName: "location.north.fill")
                                        Text(companion.matches(display, destination: end) ? "Resume journey" : "GO · Start journey").fontWeight(.bold)
                                        Spacer()
                                        Image(systemName: "arrow.right")
                                    }.padding(.vertical, 8)
                                }.buttonStyle(.borderedProminent).controlSize(.large)
                            }
                            HStack {
                                Text("Suggested trips").font(.title2.bold())
                                Spacer()
                                if let updated = search.updatedAt {
                                    Text("Updated \(updated, style: .relative) ago").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if choices.isEmpty {
                                Text(accessibleVehiclesOnly ? "No wheelchair-accessible vehicle trips are confirmed for this search. Try another time or review all trips." : "These departures have passed. Finding your next options…").foregroundStyle(.secondary)
                                Button("Refresh now") { revision += 1 }
                            }
                            ForEach(choices) { journey in
                                JourneyCard(journey: journey, labels: JourneyRanking.labels(for: journey, among: choices), liveAvailable: freshLive != nil,
                                            expanded: selection?.id == journey.id, changeDeparture: { index in
                                    departureSelection = LegSelection(index: index, journey: journey)
                                }) {
                                    withAnimation { selectedJourney = journey.id }
                                }
                            }
                        }
                        Button("Open transit directions in Apple Maps", systemImage: "arrow.up.right.square") {
                            MKMapItem.openMaps(with: [origin?.item ?? .forCurrentLocation(), end.item], launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeTransit])
                        }.font(.subheadline)
                        Text("OC Transpo buses and trains • Up to 3 transfers • Walks up to 25 minutes at each end. Walking estimates are checked in the background.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Plan a trip").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $picker) { field in
                PlacePicker(title: field == .from ? "Starting point" : "Destination", allowCurrentLocation: field == .from) { place in
                    if field == .from { origin = place; if place == nil { location.retry() } } else if let place { target = place }
                    selectedJourney = nil; revision += 1
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { JourneyCompanionBar { showGuide = true } }
            .fullScreenCover(isPresented: $showGuide) {
                JourneyGuideView { here in
                    if let activeDestination = companion.destination { target = activeDestination }
                    if let here {
                        let item = MKMapItem(placemark: MKPlacemark(coordinate: here.coordinate)); item.name = "Current location"
                        origin = Destination(item: item)
                    } else { origin = nil }
                    timeMode = .now; revision += 1
                }
            }
            .sheet(item: $departureSelection) { selection in
                DepartureChoicesView(journey: selection.journey, legIndex: selection.index) { chosen in
                    customized = chosen
                    selectedJourney = chosen.id
                    shaped = nil
                }
            }
            .task(id: "\(revision)-\(scenePhase)") {
                guard scenePhase == .active else { return }
                await location.update()
                await plan(retainResults: false)
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(20)) } catch { return }
                    if transit.liveUpdated.map({ Date.now.timeIntervalSince($0) > 20 }) ?? true { await transit.refreshLive() }
                    guard !Task.isCancelled else { return }
                    await transit.loadAlerts()
                    await plan(retainResults: true)
                }
            }
            .task(id: selected?.id) {
                guard let selection = selected else { shaped = nil; return }
                let result = await RouteShapes.shared.apply(to: [selection]).first
                guard !Task.isCancelled else { return }
                shaped = result
            }
            .onChange(of: location.current) { old, new in
                if origin == nil && old == nil && new != nil { revision += 1 }
            }
            .onChange(of: revision) { _, _ in customized = nil }
        }
        .presentationDetents([.large]).presentationDragIndicator(.visible)
    }

    private var journeyFields: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 12) {
                    Button { picker = .from } label: {
                        Label(origin?.title ?? "Current location", systemImage: "circle.circle.fill")
                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider()
                    Button { picker = .to } label: {
                        Label(end.title, systemImage: "mappin.circle.fill")
                            .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .tint(.primary)
                Button {
                    guard let coordinate = startCoordinate else { picker = .from; return }
                    let item = origin?.item ?? MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
                    if origin == nil { item.name = "Previous starting point" }
                    origin = end; target = Destination(item: item); revision += 1
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .background(Color(.tertiarySystemGroupedBackground), in: Circle())
                }
                    .accessibilityLabel("Swap starting point and destination")
            }
            Divider()
            Picker("Time", selection: $timeMode) {
                ForEach(JourneyTimeMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
                .onChange(of: timeMode) { _, _ in departure = max(departure, .now); revision += 1 }
            if timeMode != .now {
                DatePicker(timeMode == .arrive ? "Arrive by" : "Depart at", selection: $departure, in: Date.now...Date.now.addingTimeInterval(6 * 86400))
                    .onChange(of: departure) { _, _ in revision += 1 }
            }
            HStack(spacing: 12) {
                Menu("Save place", systemImage: "star") {
                    ForEach(SavedDestinations.Slot.allCases) { slot in
                        Button("Save as \(slot.rawValue)", systemImage: slot.symbol) { saved.save(end, as: slot) }
                    }
                }
                Spacer(minLength: 0)
                Toggle("Accessible vehicle", isOn: $accessibleVehiclesOnly)
                    .fixedSize()
                    .onChange(of: accessibleVehiclesOnly) { _, value in
                        UserDefaults.standard.set(value, forKey: "accessibleVehiclesOnly")
                        selectedJourney = nil; revision += 1
                    }
            }
            .font(.caption.weight(.medium))
            if accessibleVehiclesOnly {
                Text("Vehicle access is confirmed by the timetable; stop and walking access may be unknown.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .font(.subheadline.weight(.medium))
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    @MainActor private func plan(retainResults: Bool) async {
        originError = nil
        guard let coordinate = startCoordinate else {
            originError = "Use a place or address as your starting point, or allow location access in Settings."; return
        }
        let shouldRefresh = refresh; refresh = false
        let start = timeMode == .depart ? max(departure, .now) : Date.now
        if retainResults && !shouldRefresh {
            await search.refreshIfNeeded(origin: coordinate, destination: end.item.placemark.coordinate, departure: start, live: freshLive, arriveBy: timeMode == .arrive ? departure : nil, accessibleVehiclesOnly: accessibleVehiclesOnly, alerts: transit.alerts)
        } else {
            await search.search(origin: coordinate, destination: end.item.placemark.coordinate, departure: start, live: freshLive,
                                refresh: shouldRefresh, arriveBy: timeMode == .arrive ? departure : nil, retainResults: retainResults, accessibleVehiclesOnly: accessibleVehiclesOnly, alerts: transit.alerts)
        }
    }
}
private struct JourneyCard: View {
    let journey: Journey
    let labels: [String]
    let liveAvailable: Bool
    let expanded: Bool
    let changeDeparture: (Int) -> Void
    let select: () -> Void

    private func minutes(_ seconds: TimeInterval) -> Int { max(1, Int(ceil(seconds / 60))) }
    private func clock(_ date: Date) -> String {
        date.formatted(date: Calendar.current.isDate(date, inSameDayAs: journey.requestedDeparture) ? .omitted : .abbreviated, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: select) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(minutes(journey.duration)) min")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                            Text("Arrive \(clock(journey.arrival))")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Color(.tertiarySystemGroupedBackground), in: Circle())
                    }
                    if !labels.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(labels, id: \.self) { label in
                                    Text(label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.green)
                                        .padding(.horizontal, 9).padding(.vertical, 5)
                                        .background(Color.green.opacity(0.1), in: Capsule())
                                }
                            }
                        }
                    }
                    HStack {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(JourneyRanking.countdown(journey.legs[0].departure, now: context.date))
                                .font(.subheadline.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(Color.accentColor)
                        }
                        Spacer()
                        Text("Leave \(clock(journey.leave))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Image(systemName: "figure.walk")
                            ForEach(Array(journey.legs.enumerated()), id: \.offset) { _, leg in
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                                RouteBadge(route: leg.route)
                            }
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                            Image(systemName: "figure.walk")
                        }
                    }
                    Text("\(journey.legs.count == 1 ? "Direct" : "\(journey.legs.count - 1) transfers") · \(minutes(journey.walking)) min walk")
                        .font(.subheadline)
                    Text(journey.accessibilitySummary).font(.caption).foregroundStyle(.secondary)
                    if let tight = JourneyConnection.all(in: journey).first(where: { $0.isTight || $0.isMissed }) {
                        Label(tight.summary, systemImage: "clock.badge.exclamationmark")
                            .font(.caption.bold()).foregroundStyle(.orange)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            JourneyAlertsView(journey: journey)
            if expanded {
                Divider()
                ForEach(Array(journey.legs.enumerated()), id: \.offset) { index, leg in
                    if let connection = JourneyConnection.all(in: journey).first(where: { $0.nextLeg == index }) {
                        Text("Transfer: \(Int(ceil(connection.available / 60))) min available · \(Int(ceil(connection.walk / 60))) min walk · \(connection.summary)")
                            .font(.caption).foregroundStyle(connection.isTight || connection.isMissed ? .orange : .secondary)
                    }
                    walkRow(leg.walk, title: index == 0 ? "Walk to \(leg.board.name)" : "Transfer to \(leg.board.name)")
                    HStack(alignment: .top, spacing: 12) {
                        RouteBadge(route: leg.route, small: true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(leg.headsign.isEmpty ? "Take route \(leg.route.name)" : "Toward \(leg.headsign)").font(.subheadline.bold())
                            Text("\(clock(leg.departure)) · Board at \(leg.board.name)")
                            Text("\(clock(leg.arrival)) · Get off at \(leg.alight.name)")
                            Text(leg.live ? (liveAvailable ? "Live prediction" : "Last known prediction") : "Scheduled departure").foregroundStyle(leg.live && liveAvailable ? .green : .secondary)
                            Button("Change departure", systemImage: "clock.arrow.circlepath") { changeDeparture(index) }
                                .font(.caption.weight(.semibold))
                            if leg.delay >= 60 { Text("Delayed \(Int(ceil(leg.delay / 60))) min").foregroundStyle(.orange) }
                            else if leg.delay <= -60 { Text("Running \(Int(ceil(-leg.delay / 60))) min early").foregroundStyle(.orange) }
                        }
                        .font(.caption)
                    }
                }
                walkRow(journey.finalWalk, title: "Walk to your destination")
            }
        }
        .padding(16).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(expanded ? Color.accentColor : .clear, lineWidth: 2))
    }

    private func walkRow(_ walk: JourneyWalk, title: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "figure.walk").frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                Text("\(minutes(walk.duration)) min · \(Int(walk.distance.rounded())) m\(walk.verified ? "" : " · estimated walk")")
                    .font(.caption).foregroundStyle(.secondary)
                if !walk.instructions.isEmpty { WalkingInstructionsView(walk: walk, saved: false) }
            }
        }
    }
}

struct JourneyMap: View {
    let journey: Journey
    @State private var transit = Transit.shared
    var body: some View {
        let alerts = transit.alerts(for: journey).filter { $0.closesJourneyStop(journey) }
        let closed = Set(alerts.flatMap { Array($0.closedStops ?? []) })
        let alternatives = Set(alerts.flatMap { Array($0.alternativeStops ?? []) })
        let hasPublishedDetour = transit.alerts(for: journey).contains { $0.publishedMap != nil }
        Map {
            ForEach(Array(journey.legs.enumerated()), id: \.offset) { _, leg in
                if leg.followsShape {
                    if closed.contains(leg.board.code) || closed.contains(leg.alight.code) {
                        MapPolyline(coordinates: leg.coordinates).stroke(.orange, style: StrokeStyle(lineWidth: 5, dash: [8, 6]))
                    } else {
                        MapPolyline(coordinates: leg.coordinates).stroke(Color(hex: leg.route.color) ?? .accentColor, lineWidth: 5)
                    }
                }
                Marker(leg.alight.name, coordinate: .init(latitude: leg.alight.latitude, longitude: leg.alight.longitude))
                Annotation(leg.board.name, coordinate: .init(latitude: leg.board.latitude, longitude: leg.board.longitude)) { RouteBadge(route: leg.route, small: true) }
                ForEach(leg.callingPoints.filter { closed.contains($0.stop.code) }, id: \.sequence) { point in
                    Marker("Stop \(point.stop.code) closed", systemImage: "xmark.circle.fill", coordinate: point.stop.coordinate).tint(.orange)
                }
            }
            ForEach(alternatives.sorted(), id: \.self) { code in
                if let stop = transit.schedule.stop(code: code) {
                    Marker("Alternative stop \(code)", systemImage: "figure.walk.circle", coordinate: stop.coordinate).tint(.green)
                }
            }
            ForEach(Array(journey.walks.enumerated()), id: \.offset) { _, walk in
                MapPolyline(coordinates: walk.coordinates.isEmpty ? [walk.from, walk.to] : walk.coordinates)
                    .stroke(.secondary, style: StrokeStyle(lineWidth: 3, dash: [5, 5]))
            }
            Marker("Destination", coordinate: journey.finalWalk.to).tint(.red)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .overlay(alignment: .bottomLeading) {
            if !closed.isEmpty || hasPublishedDetour {
                Text("Scheduled path shown. Open the published detour map below for the temporary route.")
                    .font(.caption2).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9)).padding(8)
            }
        }
    }
}
