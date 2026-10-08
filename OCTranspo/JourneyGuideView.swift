import MapKit
import SwiftUI

struct JourneyGuideView: View {
    let replan: (CLLocation?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var session = JourneySession.shared
    @State private var expanded = false
    @State private var showSettings = false
    @State private var departureSelection: LegSelection?
    @State private var confirmEnd = false
    @State private var camera: MapCameraPosition = .automatic

    private var accent: Color { session.cue?.phase == .getOff ? .orange : Color(hex: session.leg?.route.color ?? "") ?? .accentColor }
    private struct LegSelection: Identifiable {
        let index: Int
        let journey: Journey
        var id: String { journey.id + ":" + String(index) }
    }

    var body: some View {
        GeometryReader { geometry in
            if let journey = session.currentJourney, let destination = session.destination, let cue = session.cue {
                map(journey)
                    .safeAreaInset(edge: .top, spacing: 0) { header(journey, destination: destination) }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        VStack(spacing: 0) {
                            Button {
                                withAnimation(.snappy) { expanded.toggle() }
                            } label: {
                                VStack(spacing: 4) {
                                    Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 38, height: 5)
                                    Text(expanded ? "Hide trip details" : "Trip details").font(.caption2).foregroundStyle(Color.secondary)
                                }.frame(maxWidth: .infinity).padding(.top, 10).padding(.bottom, 6)
                            }.tint(.primary).accessibilityLabel(expanded ? "Collapse journey details" : "Expand journey details")
                            ScrollView {
                                VStack(alignment: .leading, spacing: 18) {
                                    actionCard(cue, journey: journey)
                                    PredictionStatusView(status: .init(hasPredictions: journey.legs.dropFirst(session.progress.legIndex).contains { $0.live },
                                                                       feedAvailable: session.live != nil, updatedAt: session.predictionsUpdatedAt, predictionsAreCurrent: journey.legs.dropFirst(session.progress.legIndex).contains { $0.matchingUpdate(session.live)?.stops.isEmpty == false }))
                                    JourneyAlertsView(journey: journey, startingAt: session.progress.legIndex)
                                    if let warning = session.disruption {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Label(warning, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                            if session.findingReplacement { ProgressView("Finding a replacement…") }
                                            if let replacement = session.replacement {
                                                Text(session.replacementLabel ?? "Replacement trip").font(.caption)
                                                Text(replacement.legs.dropFirst(session.progress.onBoard ? 1 : 0).map { $0.route.name }.joined(separator: " → ")).font(.headline)
                                                Text("Arrive \(replacement.arrival.formatted(date: .omitted, time: .shortened))").font(.subheadline)
                                                Button("Switch to this trip") { session.switchToReplacement(); expanded = false }
                                                    .buttonStyle(.borderedProminent).disabled(!session.replacementReady)
                                                if !session.replacementReady { Text("This connection is no longer available. Checking again…").font(.caption) }
                                            }
                                            if let message = session.recoveryMessage { Text(message).font(.caption) }
                                            Button("Search another starting point") { findAnotherTrip() }.fontWeight(.semibold)
                                        }.padding().frame(maxWidth: .infinity, alignment: .leading)
                                            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                                    }
                                    if let message = session.boardingMessage {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Label(message, systemImage: "checkmark.circle")
                                            Button("I'm not on this vehicle") { session.undoBoarding() }
                                        }.font(.subheadline)
                                    }
                                    if let leg = session.leg { nextStep(leg, journey: journey) }
                                    Text(journey.accessibilitySummary).font(.caption).foregroundStyle(.secondary)
                                    if expanded {
                                        itinerary(journey)
                                        statusNotes
                                        Button("End journey", role: .destructive) { confirmEnd = true }.frame(maxWidth: .infinity)
                                    }
                                }.padding(.horizontal, 20).padding(.bottom, 20)
                            }.clipped()
                        }
                        .frame(maxHeight: geometry.size.height * (expanded ? 0.76 : 0.53))
                        .background {
                            UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26)
                                .fill(.regularMaterial).ignoresSafeArea(edges: .bottom)
                        }
                        .shadow(color: .black.opacity(0.12), radius: 16, y: -4)
                    }
                    .overlay(alignment: .trailing) {
                        if !expanded {
                            Button { focusMap() } label: { Image(systemName: "location.fill").padding(13).background(.regularMaterial, in: Circle()) }
                                .accessibilityLabel("Focus on current journey step").padding(.trailing, 16).offset(y: -40)
                        }
                    }
                    .onAppear {
                        focusMap()
                        #if DEBUG
                        if JourneyPreview.enabled && ProcessInfo.processInfo.arguments.contains("--details") { expanded = true }
                        #endif
                    }
                    .onChange(of: session.progress.legIndex) { _, _ in focusMap() }
                    .onChange(of: session.progress.onBoard) { _, _ in focusMap() }
                    .sensoryFeedback(.warning, trigger: cue.phase == .getOff)
            } else {
                ContentUnavailableView("No active journey", systemImage: "bus", description: Text("Choose a trip to start guidance."))
                    .onAppear { dismiss() }
            }
        }
        .background(Color(.systemGroupedBackground))
        .confirmationDialog("End this journey?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End journey", role: .destructive) { session.end(); dismiss() }
            Button("Keep going", role: .cancel) { }
        }
        .sheet(isPresented: $showSettings) { settings }
        .sheet(item: $departureSelection) { selection in
            DepartureChoicesView(journey: selection.journey, legIndex: selection.index) { choice in
                _ = session.changeDeparture(to: choice, legIndex: selection.index)
            }
        }
    }

    private func header(_ journey: Journey, destination: Destination) -> some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { Image(systemName: "chevron.down").font(.headline).frame(width: 40, height: 40) }
                .accessibilityLabel("Minimize journey")
            VStack(alignment: .leading, spacing: 3) {
                Text(destination.title).font(.headline).lineLimit(1)
                HStack(spacing: 5) {
                    Text(session.progress.finished ? "Journey complete" : "Arrive \(journey.arrival.formatted(date: .omitted, time: .shortened))")
                    if !session.progress.finished { Text("· \(max(0, Int(ceil(journey.arrival.timeIntervalSince(session.now) / 60)))) min") }
                }.font(.caption).foregroundStyle(Color.secondary).monospacedDigit()
            }
            Spacer(minLength: 0)
            Button { showSettings = true } label: {
                Image(systemName: session.remindersEnabled ? "bell.badge.fill" : "bell").frame(width: 40, height: 40)
            }.accessibilityLabel("Journey reminders and settings")
        }.tint(.primary).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22)).padding(.horizontal, 12).padding(.top, 8)
    }

    @ViewBuilder private func actionCard(_ cue: JourneyCue, journey: Journey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: cue.symbol).font(.title2.bold()).foregroundStyle(accent)
                .frame(width: 52, height: 52).background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 6) {
                Text(cue.title).font(.system(.title, design: .rounded, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                Text(cue.detail).font(.headline).foregroundStyle(Color.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        if let leg = session.leg {
            HStack(spacing: 12) {
                RouteBadge(route: leg.route)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Toward \(leg.headsign)").font(.subheadline.weight(.semibold))
                    if session.progress.onBoard {
                        Text(cue.estimated ? "Stop count estimated from times" : "Stop progress confirmed near stops by GPS").font(.caption).foregroundStyle(Color.secondary)
                    } else {
                        Text(JourneyRanking.countdown(leg.departure, now: session.now)).font(.subheadline).monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
                if leg.live && session.live != nil { Label("Live", systemImage: "dot.radiowaves.left.and.right").font(.caption).foregroundStyle(.green) }
            }
            if leg.delay >= 60 { Text("Running \(Int(ceil(leg.delay / 60))) min late").font(.caption.bold()).foregroundStyle(.orange) }
            if session.progress.onBoard {
                ProgressView(value: Double(max(0, leg.callingPoints.count - 1 - session.progress.remainingStops(leg, now: session.now))), total: Double(max(1, leg.callingPoints.count - 1)))
                    .tint(accent).accessibilityLabel("Progress toward your stop")
                primary("I got off", symbol: "figure.walk") { session.alight(); expanded = false }
            } else {
                if cue.phase != .wait {
                    let remaining = remainingWalk(leg.walk)
                    Label("\(remaining) min walk · Stop \(leg.board.code)", systemImage: "figure.walk").font(.subheadline)
                } else { Text("Board at \(leg.board.name) · Stop \(leg.board.code)").font(.subheadline) }
                primary("I'm on board", symbol: "checkmark") { session.board(); expanded = false }
                    .disabled(session.live?.isCanceled(tripID: leg.tripID, serviceDate: leg.serviceDate, now: session.now) == true || leg.skips(leg.callingPoints.first, live: session.live))
                if let current = session.currentJourney {
                    Button("Choose another departure", systemImage: "clock.arrow.circlepath") {
                        departureSelection = LegSelection(index: session.progress.legIndex, journey: current)
                    }.font(.subheadline.weight(.semibold))
                }
                WalkingInstructionsView(walk: leg.walk)
                if cue.phase != .wait { walkingButton(to: .init(placemark: MKPlacemark(coordinate: leg.walk.to))) }
            }
        } else if cue.phase == .arrived {
            primary("Done", symbol: "checkmark") { session.end(); dismiss() }
        } else if let destination = session.destination {
            Label("About \(remainingWalk(journey.finalWalk)) min on foot", systemImage: "figure.walk").font(.subheadline)
            primary("I've arrived", symbol: "flag.checkered") { session.finish() }
            WalkingInstructionsView(walk: journey.finalWalk)
            walkingButton(to: destination.item)
        }
    }

    private func remainingWalk(_ walk: JourneyWalk) -> Int {
        if let fix = JourneyGuidanceProgress.usable(session.location, now: session.now),
           fix.distance(from: CLLocation(latitude: walk.to.latitude, longitude: walk.to.longitude)) < 60 { return 1 }
        return max(1, Int(ceil(walk.duration / 60)))
    }

    @ViewBuilder private func nextStep(_ leg: JourneyLeg, journey: Journey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("UP NEXT").font(.caption2.bold()).foregroundStyle(Color.secondary)
            if !session.progress.onBoard {
                Text("Ride \(leg.route.name) to \(leg.alight.name)").font(.subheadline.weight(.semibold))
            } else if session.progress.legIndex + 1 < journey.legs.count {
                let next = journey.legs[session.progress.legIndex + 1]
                HStack { RouteBadge(route: next.route, small: true); Text("\(next.departure.formatted(date: .omitted, time: .shortened)) · Toward \(next.headsign)").font(.subheadline.weight(.semibold)) }
                Text("Transfer at \(next.board.name) · \(max(1, Int(ceil(next.walk.duration / 60)))) min walk").font(.caption).foregroundStyle(Color.secondary)
                if let connection = JourneyConnection.all(in: journey).first(where: { $0.nextLeg == session.progress.legIndex + 1 }) {
                    Label(connection.summary, systemImage: "clock.badge.exclamationmark")
                        .font(.caption.weight(connection.isTight || connection.isMissed ? .semibold : .regular))
                        .foregroundStyle(connection.isTight || connection.isMissed ? Color.orange : Color.secondary)
                }
            } else { Text("Walk to \(session.destination?.title ?? "your destination")").font(.subheadline.weight(.semibold)) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func itinerary(_ journey: Journey) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your trip, step by step").font(.title3.bold())
            ForEach(Array(journey.legs.enumerated()), id: \.offset) { index, leg in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: index < session.progress.legIndex ? "checkmark.circle.fill" : "figure.walk").foregroundStyle(Color.secondary)
                        Text("\(index == 0 ? "Walk" : "Transfer") to \(leg.board.name)").font(.subheadline)
                    }
                    WalkingInstructionsView(walk: leg.walk)
                    HStack { RouteBadge(route: leg.route, small: true); Text("Toward \(leg.headsign)").font(.headline); Spacer() }
                    if index >= session.progress.legIndex + (session.progress.onBoard ? 1 : 0) {
                        Button("Change departure") { departureSelection = LegSelection(index: index, journey: journey) }
                            .font(.caption.weight(.semibold))
                    }
                    ForEach(Array(leg.callingPoints.enumerated()), id: \.offset) { pointIndex, point in
                        let passed = index < session.progress.legIndex || (index == session.progress.legIndex && pointIndex < (session.progress.observedStop ?? 0))
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: passed ? "checkmark.circle.fill" : "circle.fill").font(.system(size: 9)).frame(width: 22, height: 20)
                                .foregroundStyle(passed ? Color.secondary : Color(hex: leg.route.color) ?? .accentColor)
                            Text(point.stop.name).font(.subheadline).foregroundStyle(passed ? Color.secondary : Color.primary)
                            Spacer()
                            Text(point.time, style: .time).font(.caption).foregroundStyle(Color.secondary).monospacedDigit()
                        }
                    }
                    if index == session.progress.legIndex && session.progress.onBoard {
                        Button("I'm not on this vehicle") { session.undoBoarding() }.font(.caption)
                    }
                }.opacity(index < session.progress.legIndex ? 0.55 : 1)
                Divider()
            }
            Label(session.destination?.title ?? "Destination", systemImage: "flag.checkered").font(.headline)
            WalkingInstructionsView(walk: journey.finalWalk)
        }
    }

    private var statusNotes: some View {
        VStack(alignment: .leading, spacing: 8) {
            if session.live == nil { Label("Live updates unavailable. Times are scheduled or last known estimates.", systemImage: "wifi.slash") }
            if let message = session.locationMessage { Label(message, systemImage: "location.slash") }
            Text("Boarding is detected when your movement and the live vehicle agree. You can always confirm boarding and getting off yourself.")
            Text("Journey location updates continue with the screen locked. Follow the next step on your Lock Screen or Dynamic Island, and tap to reopen your trip. Reopening restores an unfinished journey.")
        }.font(.caption).foregroundStyle(Color.secondary)
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section("Journey reminders") {
                    Button { Task { await session.toggleReminders() } } label: {
                        Label(session.remindersEnabled ? "Turn off reminders" : "Enable journey reminders", systemImage: session.remindersEnabled ? "bell.slash" : "bell.badge")
                    }
                    if let message = session.reminderMessage { Text(message).foregroundStyle(.orange) }
                    Picker("Remind me to leave", selection: Binding(get: { session.leaveReminderMinutes }, set: { session.setReminderMinutes(leave: $0) })) {
                        ForEach([1, 3, 5, 10], id: \.self) { Text("\($0) min early").tag($0) }
                    }
                    Picker("Remind me to get off", selection: Binding(get: { session.getOffReminderMinutes }, set: { session.setReminderMinutes(getOff: $0) })) {
                        ForEach([1, 2, 3, 5], id: \.self) { Text("\($0) min early").tag($0) }
                    }
                    Picker("Remind me to transfer", selection: Binding(get: { session.transferReminderMinutes }, set: { session.setReminderMinutes(transfer: $0) })) {
                        ForEach([1, 2, 3, 5], id: \.self) { Text("\($0) min early").tag($0) }
                    }
                    Text("Enable notifications for leaving, transfers, and getting off. Boarding confirms ride reminders. Times update as predictions arrive; without live data, prompts use the last known times.")
                        .font(.footnote).foregroundStyle(Color.secondary)
                }
                Section("Spoken guidance") {
                    Toggle("Speak journey prompts", isOn: Binding(get: { session.voiceEnabled }, set: { session.setVoiceEnabled($0) }))
                    Toggle("Headphones only", isOn: Binding(get: { session.voiceHeadphonesOnly }, set: { session.setVoiceHeadphonesOnly($0) }))
                        .disabled(!session.voiceEnabled)
                    Text("Speaks key actions and the last two stops during an active journey. Your phone's notification settings control alerts when speech is unavailable.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Boarding") {
                    Toggle("Detect boarding automatically", isOn: Binding(get: { session.automaticBoarding }, set: { _ in session.toggleAutomaticBoarding() }))
                    Text("Requires accurate location, movement along the route, and a nearby live vehicle. When evidence is uncertain, use ‘I’m on board’.").font(.footnote).foregroundStyle(Color.secondary)
                }
                Section { statusNotes }
                #if DEBUG
                Section("Journey measurement") {
                    Button(JourneyReliabilityRecorder.shared.running ? "Stop measurement" : "Start measurement") {
                        if JourneyReliabilityRecorder.shared.running {
                            JourneyReliabilityRecorder.shared.stop(reason: "manual")
                        } else if let archive = JourneyArchiveStore().load() {
                            JourneyReliabilityRecorder.shared.start(sessionID: archive.sessionID)
                        }
                    }
                    if let report = JourneyReliabilityRecorder.shared.reportURL {
                        ShareLink("Export measurement summary", item: report)
                    }
                    if let events = JourneyReliabilityRecorder.shared.eventsURL {
                        ShareLink("Export detailed measurements", item: events)
                    }
                    Text("Records update timing, battery level, feed status and GPS accuracy without saving coordinates. Results are stored in Documents/journey-measurement.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                #endif
                Section { Button("End journey", role: .destructive) { showSettings = false; confirmEnd = true } }
            }.navigationTitle("Journey settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSettings = false } } }
        }.presentationDetents([.medium, .large])
    }

    private func map(_ journey: Journey) -> some View {
        let alerts = Transit.shared.alerts(for: journey, startingAt: session.progress.legIndex)
            .filter { $0.closesJourneyStop(journey, startingAt: session.progress.legIndex, onBoard: session.progress.onBoard) }
        let closed = Set(alerts.flatMap { Array($0.closedStops ?? []) })
        let alternatives = Set(alerts.flatMap { Array($0.alternativeStops ?? []) })
        let hasPublishedDetour = Transit.shared.alerts(for: journey, startingAt: session.progress.legIndex).contains { $0.publishedMap != nil }
        return Map(position: $camera) {
            UserAnnotation()
            ForEach(Array(journey.legs.enumerated()), id: \.offset) { index, leg in
                if index >= session.progress.legIndex {
                    if leg.followsShape {
                        if closed.contains(leg.board.code) || closed.contains(leg.alight.code) {
                            MapPolyline(coordinates: leg.coordinates).stroke(.orange, style: StrokeStyle(lineWidth: 5, dash: [8, 6]))
                        } else {
                            MapPolyline(coordinates: leg.coordinates).stroke((Color(hex: leg.route.color) ?? .accentColor).opacity(index == session.progress.legIndex ? 1 : 0.3), lineWidth: index == session.progress.legIndex ? 6 : 3)
                        }
                    }
                    ForEach(leg.callingPoints.filter { closed.contains($0.stop.code) }, id: \.sequence) { point in
                        Marker("Stop \(point.stop.code) closed", systemImage: "xmark.circle.fill", coordinate: point.stop.coordinate).tint(.orange)
                    }
                    if index == session.progress.legIndex {
                        MapPolyline(coordinates: leg.walk.coordinates.isEmpty ? [leg.walk.from, leg.walk.to] : leg.walk.coordinates).stroke(.secondary, style: StrokeStyle(lineWidth: 4, dash: [4, 6]))
                        Marker(leg.board.name, systemImage: "bus.fill", coordinate: .init(latitude: leg.board.latitude, longitude: leg.board.longitude))
                        Marker(leg.alight.name, systemImage: "arrow.down", coordinate: .init(latitude: leg.alight.latitude, longitude: leg.alight.longitude)).tint(.orange)
                    }
                }
            }
            ForEach(alternatives.sorted(), id: \.self) { code in
                if let stop = Transit.shared.schedule.stop(code: code) {
                    Marker("Alternative stop \(code)", systemImage: "figure.walk.circle", coordinate: stop.coordinate).tint(.green)
                }
            }
            if let vehicle = session.vehicle {
                Annotation("Your vehicle", coordinate: .init(latitude: vehicle.latitude, longitude: vehicle.longitude)) {
                    Image(systemName: "bus.fill").foregroundStyle(.white).padding(10).background(accent, in: Circle()).overlay(Circle().stroke(.white, lineWidth: 3)).shadow(radius: 3)
                }
            }
            MapPolyline(coordinates: journey.finalWalk.coordinates.isEmpty ? [journey.finalWalk.from, journey.finalWalk.to] : journey.finalWalk.coordinates)
                .stroke(.secondary, style: StrokeStyle(lineWidth: 3, dash: [4, 6]))
            Marker(session.destination?.title ?? "Destination", systemImage: "flag.checkered", coordinate: journey.finalWalk.to).tint(.green)
        }.mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll)).mapControls { MapCompass() }
            .overlay(alignment: .topLeading) {
                if !closed.isEmpty || hasPublishedDetour {
                    Text("Scheduled path shown · See published detour map in trip alerts")
                        .font(.caption2).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9)).padding(8)
                }
            }
    }

    private func focusMap() {
        guard let journey = session.currentJourney else { return }
        let fix = JourneyGuidanceProgress.usable(session.location, now: session.now)?.coordinate
        let leg = session.leg
        let target: CLLocationCoordinate2D
        if let leg { target = session.progress.onBoard ? .init(latitude: leg.alight.latitude, longitude: leg.alight.longitude) : leg.walk.to }
        else { target = journey.finalWalk.to }
        let start = fix ?? leg?.walk.from ?? journey.finalWalk.from
        let region = MKCoordinateRegion(center: .init(latitude: (start.latitude + target.latitude) / 2, longitude: (start.longitude + target.longitude) / 2),
                                        span: .init(latitudeDelta: max(0.006, abs(start.latitude - target.latitude) * 1.6), longitudeDelta: max(0.009, abs(start.longitude - target.longitude) * 1.6)))
        withAnimation { camera = .region(region) }
    }
    private func primary(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8) }
            .buttonStyle(.borderedProminent).tint(accent).controlSize(.large)
            .foregroundStyle(session.cue?.phase == .getOff ? Color.black : Color(hex: session.leg?.route.textColor ?? "FFFFFF") ?? .white)
    }
    private func walkingButton(to item: MKMapItem) -> some View {
        Button("Open walking directions", systemImage: "arrow.up.right.square") {
            MKMapItem.openMaps(with: [.forCurrentLocation(), item], launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
        }.font(.subheadline).frame(maxWidth: .infinity)
    }
    private func findAnotherTrip() {
        replan(JourneyGuidanceProgress.usable(session.location, now: session.now))
        session.end(); dismiss()
    }
}
