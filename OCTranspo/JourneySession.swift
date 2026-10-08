import CoreLocation
import MapKit
import Observation
import UserNotifications

@MainActor @Observable
final class JourneySession {
    static let shared = JourneySession()
    private(set) var journey: Journey?
    private(set) var destination: Destination?
    private(set) var progress = JourneyGuidanceProgress()
    private(set) var location: CLLocation?
    private(set) var now = Date.now
    private(set) var remindersEnabled = UserDefaults.standard.bool(forKey: "journeyReminders")
    private(set) var automaticBoarding = UserDefaults.standard.object(forKey: "automaticBoarding") as? Bool ?? true
    private(set) var voiceEnabled = UserDefaults.standard.bool(forKey: "journeyVoiceEnabled")
    private(set) var voiceHeadphonesOnly = UserDefaults.standard.object(forKey: "journeyVoiceHeadphonesOnly") as? Bool ?? true
    private(set) var leaveReminderMinutes = UserDefaults.standard.object(forKey: "journeyLeaveReminderMinutes") as? Int ?? 1
    private(set) var getOffReminderMinutes = UserDefaults.standard.object(forKey: "journeyGetOffReminderMinutes") as? Int ?? 1
    private(set) var transferReminderMinutes = UserDefaults.standard.object(forKey: "journeyTransferReminderMinutes") as? Int ?? 3
    private(set) var boardingMessage: String?
    private(set) var replacement: Journey?
    private(set) var replacementLabel: String?
    private(set) var findingReplacement = false
    private(set) var recoveryMessage: String?
    var openRequested = false
    private(set) var reminderMessage: String?
    private(set) var locationMessage: String?
    private(set) var predictionsUpdatedAt: Date?
    @ObservationIgnored private var actionToken = UUID()
    @ObservationIgnored private var walking: Task<Void, Never>?
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private let locator = JourneyLocationService()
    @ObservationIgnored private let archive: JourneyArchiveStore = {
        #if DEBUG
        if JourneyDiagnostics.enabled { return JourneyArchiveStore(url: URL.documentsDirectory.appending(path: "journey-diagnostics/active.json")) }
        #endif
        return JourneyArchiveStore()
    }()
    @ObservationIgnored private var detector = BoardingDetector()
    @ObservationIgnored private let voice = JourneyVoiceGuidance()
    @ObservationIgnored private var boardingSuppressed = false
    @ObservationIgnored private var restored = false
    @ObservationIgnored private var recovering: Task<Void, Never>?
    @ObservationIgnored private var recoveryID = UUID()
    @ObservationIgnored private var recoveryKey: String?
    @ObservationIgnored private var lastRecovery = Date.distantPast
    @ObservationIgnored private var lastSaved = Date.distantPast
    @ObservationIgnored private var lastFeedRequest = Date.distantPast
    @ObservationIgnored private var lastActivity = Date.distantPast
    @ObservationIgnored private var activitySignature = ""
    @ObservationIgnored private var shaping: Task<Void, Never>?
    @ObservationIgnored private var notifying: Task<Void, Never>?
    @ObservationIgnored private var notificationIDs: [String] = []
    @ObservationIgnored private var scheduledReminders: [JourneyReminder] = []
    @ObservationIgnored private var token = UUID()
    @ObservationIgnored private var appActive = true
    @ObservationIgnored private var trackingEnabled = true

    var isRunning: Bool { journey != nil }
    func matches(_ trip: Journey, destination target: Destination) -> Bool {
        journey?.id == trip.id && destination?.item.placemark.coordinate.latitude == target.item.placemark.coordinate.latitude && destination?.item.placemark.coordinate.longitude == target.item.placemark.coordinate.longitude
    }
    var live: LiveTrips? {
        let transit = Transit.shared
        guard let updated = transit.liveUpdated, now.timeIntervalSince(updated) < 120, transit.liveError == nil else { return nil }
        return transit.live
    }
    var currentJourney: Journey? {
        guard var journey else { return nil }
        journey.legs = journey.legs.map { $0.withPredictions(live) }
        return journey
    }
    var leg: JourneyLeg? {
        guard let trip = currentJourney, progress.legIndex < trip.legs.count else { return nil }
        return trip.legs[progress.legIndex]
    }
    var cue: JourneyCue? {
        guard let trip = currentJourney, let destination else { return nil }
        return progress.cue(journey: trip, destination: destination.title, location: location, now: now)
    }
    var vehicle: Vehicle? {
        guard live != nil, let leg, leg.serviceDate == RoutingTimetable.dayKey(now) else { return nil }
        return Transit.shared.vehicle(onTrip: leg.tripID)
    }
    var disruption: String? {
        guard let leg else { return nil }
        if let trip = currentJourney, Transit.shared.alerts.contains(where: { $0.closesJourneyStop(trip, startingAt: progress.legIndex, onBoard: progress.onBoard) }) {
            return "A published detour closes a stop on your journey. Check the replacement connection."
        }
        if live?.isCanceled(tripID: leg.tripID, serviceDate: leg.serviceDate, now: now) == true { return "Route \(leg.route.name) was cancelled." }
        if leg.skips(leg.callingPoints.first, live: live) || leg.skips(leg.callingPoints.last, live: live) { return "This service is skipping one of your stops." }
        if !progress.onBoard && leg.departure < now { return "This departure may have left." }
        if let trip = currentJourney, progress.onBoard, progress.legIndex + 1 < trip.legs.count {
            let next = trip.legs[progress.legIndex + 1]
            for connection in trip.legs.dropFirst(progress.legIndex + 1) {
                if live?.isCanceled(tripID: connection.tripID, serviceDate: connection.serviceDate, now: now) == true { return "Your connecting route \(connection.route.name) was cancelled." }
                if connection.skips(connection.callingPoints.first, live: live) || connection.skips(connection.callingPoints.last, live: live) { return "Your connection is skipping one of your stops." }
            }
            if leg.arrival.addingTimeInterval(max(180, next.walk.duration + 120)) > next.departure { return "You may miss your connection to \(next.route.name)." }
        }
        return nil
    }

    func restoreIfNeeded() async {
        guard !restored, journey == nil else { return }
        restored = true
        #if DEBUG
        if JourneyPreview.enabled { return }
        #endif
        guard let saved = archive.load(), let trip = saved.restored(at: .now) else {
            archive.clear()
            let id = token
            await JourneyActivityController.shared.removeOrphans(keeping: nil)
            let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
            guard token == id else { return }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: requests.filter { $0.identifier.hasPrefix("journey-") }.map(\.identifier))
            return
        }
        token = saved.sessionID; journey = trip; progress = saved.progress
        #if DEBUG
        JourneyReliabilityRecorder.shared.resume(sessionID: token)
        #endif
        boardingSuppressed = saved.automaticBoardingSuppressed
        voice.reset()
        predictionsUpdatedAt = saved.predictionsUpdatedAt
        actionToken = saved.actionToken ?? UUID()
        let item = MKMapItem(placemark: MKPlacemark(coordinate: saved.destination.coordinate)); item.name = saved.destinationTitle
        destination = Destination(item: item); now = .now
        let id = token
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        guard token == id else { return }
        let owned = requests.filter { $0.identifier.hasPrefix("journey-") }.map(\.identifier)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: owned)
        await reconcilePermission()
        guard token == id else { return }
        loadShapes(); loadWalkingInstructions(); resume(); changed()
    }

    func start(_ journey: Journey, destination: Destination, track: Bool = true) {
        end(clearSaved: track)
        restored = true; trackingEnabled = track
        self.journey = journey; self.destination = destination
        predictionsUpdatedAt = Transit.shared.liveUpdated
        progress = JourneyGuidanceProgress(); now = .now; actionToken = UUID()
        boardingSuppressed = false; boardingMessage = nil; detector.reset()
        voice.reset()
        loadShapes(); loadWalkingInstructions(); resume(); changed()
    }
    private func loadShapes() {
        shaping?.cancel()
        guard let journey else { return }
        let id = token
        shaping = Task {
            let result = await RouteShapes.shared.apply(to: [journey]).first
            guard !Task.isCancelled, token == id else { return }
            if let result, var current = self.journey {
                for index in current.legs.indices where index < result.legs.count {
                    current.legs[index].coordinates = result.legs[index].coordinates
                    current.legs[index].followsShape = result.legs[index].followsShape
                }
                self.journey = current
            }
        }
    }
    private func loadWalkingInstructions() {
        walking?.cancel()
        guard trackingEnabled, let trip = journey else { return }
        let id = token
        walking = Task {
            for (index, walk) in trip.walks.enumerated() where walk.instructions.isEmpty && walk.distance >= 25 {
                guard !Task.isCancelled, token == id else { return }
                guard let result = try? await WalkingRoutes.shared.check(walk) else { continue }
                guard !Task.isCancelled, token == id, var current = journey else { return }
                if case .route(let checked) = result, !checked.instructions.isEmpty {
                    if index < current.legs.count {
                        current.legs[index].walk.instructions = checked.instructions
                        current.legs[index].walk.coordinates = checked.coordinates
                    } else {
                        current.finalWalk.instructions = checked.instructions
                        current.finalWalk.coordinates = checked.coordinates
                    }
                    journey = current; save()
                }
            }
        }
    }
    func board(automatically: Bool = false) {
        guard let leg, !progress.finished, !progress.onBoard,
              live?.isCanceled(tripID: leg.tripID, serviceDate: leg.serviceDate, now: .now) != true,
              !leg.skips(leg.callingPoints.first, live: live) else { return }
        actionToken = UUID()
        progress.board(); detector.reset()
        boardingMessage = automatically ? "Boarding detected from your movement and the live vehicle." : nil
        changed()
    }
    func alight() { guard leg != nil, progress.onBoard, !progress.finished else { return }; actionToken = UUID(); progress.alight(); boardingSuppressed = false; boardingMessage = nil; detector.reset(); changed() }
    func undoBoarding() {
        guard leg != nil, progress.onBoard, !progress.finished else { return }
        actionToken = UUID()
        progress.onBoard = false; progress.observedStop = nil; progress.observedAt = nil
        boardingSuppressed = true; boardingMessage = nil; detector.reset(); changed()
    }
    func performActivityAction(sessionID: String, legIndex: Int, actionToken requestedToken: String, alighting: Bool) async -> Bool {
        guard let trip = currentJourney,
              JourneyActionValidation.accepts(sessionID: sessionID, expectedSessionID: token, legIndex: legIndex,
                  currentLegIndex: progress.legIndex, actionToken: requestedToken, expectedToken: actionToken,
                  alighting: alighting, onBoard: progress.onBoard, legCount: trip.legs.count,
                  finished: progress.finished, expiresAt: trip.arrival.addingTimeInterval(7200), now: .now) else { return false }
        let previousToken = actionToken
        if alighting { alight() } else { board() }
        guard actionToken != previousToken else { return false }
        await publishActivity(allowStart: false)
        return true
    }
    func toggleAutomaticBoarding() {
        automaticBoarding.toggle(); detector.reset()
        UserDefaults.standard.set(automaticBoarding, forKey: "automaticBoarding")
    }
    func setVoiceEnabled(_ enabled: Bool) {
        voiceEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "journeyVoiceEnabled")
        if !enabled { voice.reset() }
    }
    func setVoiceHeadphonesOnly(_ enabled: Bool) {
        voiceHeadphonesOnly = enabled
        UserDefaults.standard.set(enabled, forKey: "journeyVoiceHeadphonesOnly")
    }
    func setReminderMinutes(leave: Int? = nil, getOff: Int? = nil, transfer: Int? = nil) {
        if let leave { leaveReminderMinutes = leave; UserDefaults.standard.set(leave, forKey: "journeyLeaveReminderMinutes") }
        if let getOff { getOffReminderMinutes = getOff; UserDefaults.standard.set(getOff, forKey: "journeyGetOffReminderMinutes") }
        if let transfer { transferReminderMinutes = transfer; UserDefaults.standard.set(transfer, forKey: "journeyTransferReminderMinutes") }
        refreshReminders()
    }
    func finish() {
        #if DEBUG
        JourneyReliabilityRecorder.shared.stop(reason: "finished")
        #endif
        progress.finish(); walking?.cancel(); running?.cancel(); locator.stop(); recovering?.cancel()
        voice.reset()
        clearReminders(); if trackingEnabled { archive.clear() }
        let id = token
        Task { await JourneyActivityController.shared.end(sessionID: id) }
    }
    func end(clearSaved: Bool = true) {
        let old = token
        #if DEBUG
        JourneyReliabilityRecorder.shared.stop(reason: "ended")
        #endif
        token = UUID(); recoveryID = UUID()
        voice.reset()
        running?.cancel(); shaping?.cancel(); walking?.cancel(); recovering?.cancel(); locator.stop()
        running = nil; shaping = nil; recovering = nil
        clearReminders(); reminderMessage = nil; locationMessage = nil
        replacement = nil; replacementLabel = nil; recoveryMessage = nil; findingReplacement = false; recoveryKey = nil
        journey = nil; destination = nil; location = nil; predictionsUpdatedAt = nil
        if clearSaved { archive.clear() }
        Task { await JourneyActivityController.shared.end(sessionID: old) }
    }
    func setActive(_ active: Bool) {
        appActive = active; now = .now
        #if DEBUG
        JourneyReliabilityRecorder.shared.record("scene", ["active": active])
        #endif
        if active {
            updateActivity(force: true)
            resume()
            Task { await reconcilePermission(); refreshReminders() }
        } else { save(); updateActivity(force: true) }
    }
    private func resume() {
        guard appActive, trackingEnabled, journey != nil, !progress.finished else { return }
        locator.onLocation = { [weak self] fix in self?.receive(fix) }
        locator.onUnavailable = { [weak self] message in self?.locationMessage = message }
        locator.start()
        if running == nil || running!.isCancelled {
            let id = token
            running = Task {
                while !Task.isCancelled, token == id {
                    tick()
                    do { try await Task.sleep(for: .seconds(appActive ? 1 : 10)) } catch { return }
                }
            }
        }
    }
    private func receive(_ fix: CLLocation) {
        guard trackingEnabled, !progress.finished, JourneyGuidanceProgress.usable(fix, now: .now) != nil else { return }
        now = .now; location = fix; locationMessage = nil
        #if DEBUG
        JourneyReliabilityRecorder.shared.location(fix, active: appActive)
        #endif
        if let leg, !progress.onBoard, automaticBoarding, !boardingSuppressed,
           detector.observe(fix, vehicle: vehicle, leg: leg, now: now) { board(automatically: true) }
        let previousStop = progress.observedStop
        if let leg { progress.observe(fix, leg: leg, now: now) }
        if previousStop != progress.observedStop { save(); updateActivity(force: true) }
        tick()
    }
    private func tick() {
        guard journey != nil, !progress.finished else { return }
        now = .now
        if let cue, let trip = currentJourney {
            let due = cue.phase != .leave || trip.leave.timeIntervalSince(now) <= Double(leaveReminderMinutes) * 60
            if due { voice.announce(cue, leg: leg, legIndex: progress.legIndex, enabled: voiceEnabled, headphonesOnly: voiceHeadphonesOnly) }
        }
        #if DEBUG
        JourneyReliabilityRecorder.shared.sample(active: appActive)
        #endif
        if let trip = currentJourney, now > trip.arrival.addingTimeInterval(2 * 3600) { finish(); return }
        if now.timeIntervalSince(lastFeedRequest) >= 30 {
            lastFeedRequest = now
            let id = token
            Task { await Transit.shared.loadAlerts() }
            Task {
                await Transit.shared.refreshLive()
                #if DEBUG
                JourneyReliabilityRecorder.shared.feed(success: Transit.shared.liveError == nil,
                    age: Transit.shared.liveUpdated.map { Date.now.timeIntervalSince($0) })
                #endif
                guard token == id, !progress.finished else { return }
                now = .now
                if live != nil { predictionsUpdatedAt = Transit.shared.liveUpdated; journey = currentJourney }
                if var proposal = replacement { proposal.legs = proposal.legs.map { $0.withPredictions(live) }; replacement = proposal }
                refreshReminders(); evaluateRecovery(); save(); updateActivity(force: true)
            }
        }
        refreshReminders(); evaluateRecovery(); updateActivity()
        if now.timeIntervalSince(lastSaved) >= 30 { save() }
    }
    private func changed() {
        now = .now
        recoveryID = UUID(); recovering?.cancel(); recovering = nil; findingReplacement = false
        replacement = nil; recoveryKey = nil; lastRecovery = .distantPast
        refreshReminders(); evaluateRecovery(); save(); updateActivity(force: true)
    }
    private func save() {
        guard trackingEnabled, let trip = currentJourney, let destination, !progress.finished else { return }
        do {
            try archive.save(.init(journey: trip, title: destination.title, destination: destination.item.placemark.coordinate, progress: progress, sessionID: token, suppressed: boardingSuppressed, now: .now, predictionsUpdatedAt: predictionsUpdatedAt, actionToken: actionToken))
            lastSaved = .now
        } catch { recoveryMessage = "Couldn't save this journey for reopening." }
    }
    private func updateActivity(force: Bool = false) {
        guard trackingEnabled, !progress.finished, let trip = currentJourney, destination != nil, let cue else { return }
        let signature = "\(cue.title)|\(cue.detail)|\(trip.arrival)|\(leg?.departure.description ?? "")|\(disruption ?? "")"
        guard force || signature != activitySignature || now.timeIntervalSince(lastActivity) >= 30 else { return }
        lastActivity = now; activitySignature = signature
        Task { await publishActivity(allowStart: appActive) }
    }
    private func publishActivity(allowStart: Bool) async {
        guard trackingEnabled, !progress.finished, let trip = currentJourney, let destination, let cue else { return }
        let id = token
        let boardAllowed = leg.map { live?.isCanceled(tripID: $0.tripID, serviceDate: $0.serviceDate, now: now) != true && !$0.skips($0.callingPoints.first, live: live) } ?? false
        let state = JourneyActivityAttributes.ContentState(title: disruption ?? cue.title,
            detail: cue.detail + (live == nil || leg?.live != true ? " · Estimated times" : ""), route: leg?.route.name ?? "", symbol: cue.symbol,
            arrival: trip.arrival, departure: progress.onBoard ? nil : leg?.departure, stopsRemaining: cue.count, updatedAt: now, urgent: cue.phase == .getOff || disruption != nil,
            legIndex: leg == nil ? nil : progress.legIndex, actionToken: actionToken.uuidString, onBoard: progress.onBoard, canBoard: boardAllowed)
        #if DEBUG
        JourneyReliabilityRecorder.shared.record("activity", ["leg": progress.legIndex, "onBoard": progress.onBoard])
        #endif
        await JourneyActivityController.shared.update(sessionID: id, destination: destination.title, state: state, allowStart: allowStart)
    }
    private func reconcilePermission() async {
        let id = token
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard token == id else { return }
        let wanted = UserDefaults.standard.bool(forKey: "journeyReminders")
        let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        remindersEnabled = wanted && allowed
        if wanted && !allowed {
            clearReminders()
            reminderMessage = "Allow notifications in Settings to receive journey reminders."
        } else { reminderMessage = nil }
    }
    var replacementReady: Bool {
        guard let replacement, let trip = currentJourney,
              let context = JourneyRecoveryContext.make(journey: trip, progress: progress, location: location, now: now) else { return false }
        return context.accepts(replacement, live: live, now: now)
    }
    private func evaluateRecovery() {
        guard trackingEnabled, let reason = disruption, let trip = currentJourney, let destination,
              let context = JourneyRecoveryContext.make(journey: trip, progress: progress, location: location, now: now) else {
            recovering?.cancel(); recovering = nil; findingReplacement = false; replacement = nil; recoveryKey = nil
            return
        }
        let key = "\(progress.legIndex)|\(progress.onBoard)|\(reason)"
        if key == recoveryKey && (findingReplacement || now.timeIntervalSince(lastRecovery) < (replacement != nil && !replacementReady ? 10 : 60)) { return }
        recovering?.cancel(); recoveryID = UUID()
        let requestID = recoveryID, sessionID = token
        recoveryKey = key; lastRecovery = now; findingReplacement = true; replacement = nil; recoveryMessage = nil
        recovering = Task {
            let search = JourneySearch()
            await search.search(origin: context.origin, destination: destination.item.placemark.coordinate, departure: context.departure,
                                live: live, accessibleVehiclesOnly: UserDefaults.standard.bool(forKey: "accessibleVehiclesOnly"), alerts: Transit.shared.alerts)
            guard !Task.isCancelled, recoveryID == requestID, token == sessionID else { return }
            findingReplacement = false
            replacement = search.journeys.map(context.joining).first { context.accepts($0, live: live, now: .now) }
            replacementLabel = context.label
            if replacement == nil { recoveryMessage = search.error ?? "No replacement connection is available yet. You can search another starting point." }
        }
    }
    func switchToReplacement() {
        guard replacementReady, let replacement, let destination else { lastRecovery = .distantPast; evaluateRecovery(); return }
        let retainRide = progress.onBoard
        let observed = progress.observedStop, observedAt = progress.observedAt
        var updated = replacement; updated.legs = updated.legs.map { $0.withPredictions(live) }
        start(updated, destination: destination)
        if retainRide {
            progress.board(); progress.observedStop = observed; progress.observedAt = observedAt; changed()
        }
    }
    @discardableResult func changeDeparture(to updated: Journey, legIndex: Int) -> Bool {
        guard let current = currentJourney, current.legs.indices.contains(legIndex),
              updated.legs.count == current.legs.count,
              legIndex >= progress.legIndex + (progress.onBoard ? 1 : 0),
              updated.legs[..<legIndex].map(\.tripID) == current.legs[..<legIndex].map(\.tripID),
              updated.legs[legIndex].board.code == current.legs[legIndex].board.code,
              updated.legs[legIndex].alight.code == current.legs[legIndex].alight.code,
              updated.legs[legIndex].departure > Date.now,
              updated.legs.dropFirst(legIndex).allSatisfy({ live?.isCanceled(tripID: $0.tripID, serviceDate: $0.serviceDate, now: .now) != true }),
              !JourneyConnection.all(in: updated).dropFirst(max(0, legIndex - 1)).contains(where: \.isMissed) else { return false }
        journey = updated
        actionToken = UUID()
        detector.reset()
        if legIndex == progress.legIndex { progress.observedStop = nil; progress.observedAt = nil }
        loadShapes(); loadWalkingInstructions(); changed()
        return true
    }
    func toggleReminders() async {
        if remindersEnabled { remindersEnabled = false; UserDefaults.standard.set(false, forKey: "journeyReminders"); clearReminders(); return }
        let id = token
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            guard token == id, journey != nil else { return }
            remindersEnabled = granted
            UserDefaults.standard.set(granted, forKey: "journeyReminders")
            reminderMessage = granted ? nil : "Allow notifications for OC Transpo in Settings to receive journey reminders."
            refreshReminders()
        } catch { reminderMessage = "Couldn't enable journey reminders. Try again." }
    }
    private func clearReminders() {
        notifying?.cancel(); notifying = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: notificationIDs)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: notificationIDs)
        notificationIDs = []; scheduledReminders = []
    }
    private func refreshReminders() {
        guard trackingEnabled, remindersEnabled, let trip = currentJourney else { return }
        let desired = disruption == nil ? JourneyReminder.upcoming(journey: trip, progress: progress, now: now,
            leaveLead: Double(leaveReminderMinutes) * 60, getOffLead: Double(getOffReminderMinutes) * 60,
            transferLead: Double(transferReminderMinutes) * 60) : []
        guard desired != scheduledReminders else { return }
        clearReminders(); scheduledReminders = desired
        let ids = desired.map { "journey-\(token)-\($0.id)-\(UUID())" }
        notificationIDs = ids
        notifying = Task {
            let center = UNUserNotificationCenter.current()
            for (reminder, identifier) in zip(desired, ids) {
                guard !Task.isCancelled else { return }
                let content = UNMutableNotificationContent()
                content.title = reminder.title; content.body = reminder.body; content.sound = .default
                let interval = reminder.date.timeIntervalSinceNow
                guard interval > 0 else { continue }
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false))
                do { try await center.add(request) }
                catch { if !Task.isCancelled { reminderMessage = "Couldn't schedule a reminder. Keep the journey screen open for prompts." } }
                if Task.isCancelled { center.removePendingNotificationRequests(withIdentifiers: [identifier]); return }
            }
        }
    }
}
