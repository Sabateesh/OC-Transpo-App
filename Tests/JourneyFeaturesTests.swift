import Foundation
import MapKit

@main struct JourneyFeaturesTests {
    @MainActor static func main() throws {
        var count = 0
        func check(_ value: Bool, _ name: String) {
            if !value { FileHandle.standardError.write(Data("FAILED: \(name)\n".utf8)); exit(1) }
            count += 1; print("PASS", name)
        }
        let now = ISO8601DateFormatter().date(from: "2026-09-30T12:00:00Z")!
        let a = Stop(code: "A", name: "Start", latitude: 45.42, longitude: -75.70, ids: ["A"])
        let b = Stop(code: "B", name: "End", latitude: 45.42, longitude: -75.64, ids: ["B"])
        let start = CLLocationCoordinate2D(latitude: a.latitude, longitude: a.longitude)
        let end = CLLocationCoordinate2D(latitude: b.latitude, longitude: b.longitude)
        let walk = JourneyWalk(key: .init(from: -1, to: 0), from: start, to: start, duration: 120, distance: 150)
        let finalWalk = JourneyWalk(key: .init(from: 1, to: -2), from: end, to: end, duration: 60, distance: 75)
        let leg = JourneyLeg(tripID: "t1", route: .init(name: "88", color: "FF0000", textColor: "FFFFFF"), headsign: "East", board: a, alight: b,
                             departure: now.addingTimeInterval(300), arrival: now.addingTimeInterval(1500), walk: walk, live: false, coordinates: [],
                             serviceDate: "20260930", scheduledDeparture: now.addingTimeInterval(300), callingPoints: [
                                .init(stop: a, time: now.addingTimeInterval(300), sequence: 1),
                                .init(stop: b, time: now.addingTimeInterval(1500), sequence: 2)])
        let journey = Journey(legs: [leg], finalWalk: finalWalk, requestedDeparture: now)
        var slower = journey
        slower.legs[0].arrival.addTimeInterval(300)
        check(JourneyRanking.labels(for: journey, among: [journey, slower]).contains("Fastest"), "Label fastest duration")
        check(!JourneyRanking.labels(for: slower, among: [journey, slower]).contains("Fastest"), "Slower choice is not fastest")
        check(JourneyRanking.labels(for: journey, among: [journey, slower]).contains("Less walking"), "Label tied walking choices")
        var connecting = journey; connecting.legs.append(leg)
        check(!JourneyRanking.labels(for: connecting, among: [journey, connecting]).contains("Fewer transfers"), "Label fewer transfers accurately")
        check(JourneyRanking.countdown(now.addingTimeInterval(61), now: now) == "Departs in 2 min", "Round countdown up")
        check(JourneyRanking.countdown(now, now: now) == "Due now" && JourneyRanking.countdown(now.addingTimeInterval(-1), now: now) == "Departed", "Countdown boundary")
        check(journey.canStart(at: now) && !journey.canStart(at: now.addingTimeInterval(121)), "Remove journeys once walking and boarding buffer cannot fit")

        let suite = "OCTranspo-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let saved = SavedDestinations(defaults: defaults)
        let item = MKMapItem(placemark: MKPlacemark(coordinate: end)); item.name = "My destination"
        saved.save(Destination(item: item), as: .home)
        saved.save(Destination(item: item), as: .work)
        let restored = SavedDestinations(defaults: defaults)
        check(restored.place(.home)?.destination.title == "My destination" && restored.place(.work)?.longitude == end.longitude, "Persist Home and Work coordinates and titles")
        restored.remove(.home)
        check(SavedDestinations(defaults: defaults).place(.home) == nil && restored.place(.work) != nil, "Remove one shortcut independently")

        let typing = DestinationSearch(defaults: defaults, saved: restored)
        typing.update("work", near: nil)
        check(typing.suggestions.first?.destination?.title == "My destination", "Saved Work appears immediately without a network reply")
        typing.remember(Destination(item: item))
        typing.update("my dest", near: nil)
        check(typing.suggestions.contains { $0.title == "My destination" }, "Recent addresses match immediately as the user types")
        typing.update("my desti", near: nil)
        check(!typing.suggestions.isEmpty, "Extending the query retains matching suggestions")
        typing.update("", near: nil)
        check(typing.suggestions.isEmpty && !typing.recent.isEmpty && !typing.loading, "Clearing a query restores recent destinations and cancels pending autocomplete")
        let csv = "shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence,shape_dist_traveled\nloop,45,-75,3,200\nloop,46,-75,2,100\nloop,45,-75,1,0\nloop,45,-74,4,300\n"
        let points = RouteShapeGeometry.parse(Data(csv.utf8))["loop"]!
        let clipped = RouteShapeGeometry.segment(points, start: 150, end: 250)!
        check(clipped.count == 3 && clipped[0].latitude == 45.5 && clipped.last!.longitude == -74.5, "Clip loop using distances and interpolate endpoints")
        check(RouteShapeGeometry.segment(points, start: -1, end: 250) == nil && RouteShapeGeometry.segment(points, start: 250, end: 150) == nil, "Reject invalid shape ranges")

        let rail = RouteShapeGeometry.parse(Data("shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence,shape_dist_traveled\nrail,45.42,-75.70,1,\nrail,45.43,-75.67,2,\nrail,45.42,-75.64,3,\n".utf8))["rail"]!
        let railPath = RouteShapeGeometry.segment(rail, stops: leg.callingPoints)
        check(railPath?.count == 3 && railPath?[1].latitude == 45.43, "Use real rail geometry when shape distances are absent")
        check(RouteShapeGeometry.segment(rail, stops: leg.callingPoints.reversed()) == nil, "Reject backward stop order on a shape")

        var progress = JourneyGuidanceProgress()
        check(!progress.getOffHint(for: leg, location: nil, now: leg.arrival), "No get-off prompt before boarding")
        progress.board()
        check(progress.getOffHint(for: leg, location: nil, now: leg.arrival.addingTimeInterval(-30)), "Time-based get-off prompt without location")
        let during = now.addingTimeInterval(600)
        let fresh = CLLocation(coordinate: end, altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: during)
        let stale = CLLocation(coordinate: end, altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: now)
        check(progress.getOffHint(for: leg, location: fresh, now: during), "Nearby alighting stop prompts during ride")
        check(!progress.getOffHint(for: leg, location: stale, now: during), "Ignore stale GPS fix")
        progress.alight(); check(progress.legIndex == 1 && !progress.onBoard, "Advance to transfer or final walk")
        progress.finish(); check(progress.finished, "Finish journey explicitly")

        func varint(_ number: UInt64) -> [UInt8] {
            var value = number, bytes: [UInt8] = []
            while value >= 128 { bytes.append(UInt8(value & 127) | 128); value >>= 7 }
            return bytes + [UInt8(value)]
        }
        func number(_ field: Int, _ value: UInt64) -> [UInt8] { varint(UInt64(field << 3)) + varint(value) }
        func message(_ field: Int, _ value: [UInt8]) -> [UInt8] { varint(UInt64(field << 3 | 2)) + varint(UInt64(value.count)) + value }
        func text(_ field: Int, _ value: String) -> [UInt8] { message(field, Array(value.utf8)) }
        func feed(date: String = "20260930", canceled: Bool = false, skipped: Bool = false) -> LiveTrips {
            let descriptor = text(1, "t1") + text(3, date) + (canceled ? number(4, 3) : [])
            let update = text(4, "A") + number(1, 1) + message(3, number(2, UInt64(now.timeIntervalSince1970 + 900))) + (skipped ? number(5, 1) : [])
            return LiveTrips(message(2, message(3, message(1, descriptor) + message(2, update))))
        }
        let updated = leg.withPredictions(feed())
        check(updated.live && updated.delay == 600 && updated.arrival == leg.arrival.addingTimeInterval(600), "Guidance propagates delay to downstream stops")
        check(leg.withPredictions(feed(date: "20261001")).departure == leg.departure, "Ignore predictions for other service dates")
        check(!journey.canStart(at: now, live: feed(canceled: true)) && !journey.cancellationNotices(in: feed(canceled: true), now: now).isEmpty, "Canceled trip removed with explanation")
        check(leg.skips(leg.callingPoints.first, live: feed(skipped: true)), "Detect skipped boarding stop")
        var companion = JourneyGuidanceProgress()
        check(companion.cue(journey: journey, destination: "Home", location: nil, now: now).phase == .leave, "Tell rider when to leave before walking is due")
        let atStop = CLLocation(coordinate: start, altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: now)
        check(companion.cue(journey: journey, destination: "Home", location: atStop, now: now).phase == .wait, "Switch from walking to waiting near boarding stop")
        let oldFix = CLLocation(coordinate: start, altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: now.addingTimeInterval(-300))
        check(companion.cue(journey: journey, destination: "Home", location: oldFix, now: now).phase == .leave, "Stale position cannot imply rider is waiting at stop")
        check(companion.cue(journey: journey, destination: "Home", location: nil, now: now.addingTimeInterval(121)).phase == .walk, "Tell rider to walk when it is time to leave")
        let leaveReminders = JourneyReminder.upcoming(journey: journey, progress: companion, now: now)
        check(leaveReminders.count == 1 && leaveReminders[0].date == journey.leave, "Schedule leave alert with walk and boarding buffer")
        check(JourneyReminder.upcoming(journey: journey, progress: companion, now: now, leaveLead: 120).first?.date == journey.leave.addingTimeInterval(-60), "Custom leave reminder changes its scheduled time")
        check(JourneyReminder.upcoming(journey: journey, progress: companion, now: now.addingTimeInterval(121)).isEmpty, "Never schedule past leave alerts")
        companion.board()
        let stopCue = companion.cue(journey: journey, destination: "Home", location: nil, now: during)
        check(stopCue.title == "Your stop is next" && stopCue.estimated, "Next-stop message labels clock-based progress as estimated")
        let getOffReminders = JourneyReminder.upcoming(journey: journey, progress: companion, now: during)
        check(getOffReminders.count == 1 && getOffReminders[0].date == leg.arrival.addingTimeInterval(-60), "Schedule get-off alert only after boarding")
        check(JourneyReminder.upcoming(journey: journey, progress: companion, now: during, getOffLead: 180).first?.date == leg.arrival.addingTimeInterval(-180), "Custom get-off reminder changes its scheduled time")
        var transferTrip = journey
        let transferLeg = JourneyLeg(tripID: "t2", route: leg.route, headsign: "East", board: b, alight: b,
                                     departure: leg.arrival.addingTimeInterval(360), arrival: leg.arrival.addingTimeInterval(1260),
                                     walk: JourneyWalk(key: .init(from: 0, to: 1), from: end, to: end, duration: 0, distance: 0),
                                     live: false, coordinates: [], serviceDate: "20260930")
        transferTrip.legs.append(transferLeg)
        let transferReminders = JourneyReminder.upcoming(journey: transferTrip, progress: companion, now: during, transferLead: 300)
        check(transferReminders.first(where: { $0.id == "transfer" })?.date == leg.arrival.addingTimeInterval(-300), "Custom transfer reminder is scheduled before the connection")
        check(transferReminders.first(where: { $0.id == "transfer" })?.body.contains("route 88") == true, "Transfer reminder identifies the next route")
        let combined = JourneyReminder.upcoming(journey: transferTrip, progress: companion, now: during, transferLead: 60)
        check(combined.count == 1 && combined[0].body.contains("Then head to") , "Combine transfer and get-off alerts when due together")
        companion.observe(stale, leg: leg, now: during)
        check(companion.observedStop == nil, "Stale GPS never confirms a calling stop")
        companion.observe(fresh, leg: leg, now: during)
        check(companion.observedStop == 1 && companion.remainingStops(leg, now: during) == 0, "GPS confirms arrival at destination stop")
        let laterStart = CLLocation(coordinate: start, altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: during.addingTimeInterval(1))
        companion.observe(laterStart, leg: leg, now: during.addingTimeInterval(1))
        check(companion.observedStop == 1, "GPS cannot move stop progress backward")
        check(companion.cue(journey: journey, destination: "Home", location: nil, now: during.addingTimeInterval(180)).estimated, "GPS-confirmed progress becomes an estimate when fixes go stale")
        companion.alight()
        check(companion.observedStop == nil && companion.cue(journey: journey, destination: "Home", location: nil, now: during).phase == .finalWalk, "Getting off switches to final walk and resets ride progress")
        check(JourneyReminder.upcoming(journey: journey, progress: companion, now: during).isEmpty, "Remove vehicle reminders after getting off")
        companion.finish()
        check(companion.cue(journey: journey, destination: "Home", location: nil, now: during).phase == .arrived, "Arrival ends step-by-step guidance")
        var multiStop = leg
        multiStop.callingPoints.insert(.init(stop: a, time: during, sequence: 2), at: 1)
        var behindSchedule = JourneyGuidanceProgress()
        behindSchedule.board(); behindSchedule.observedStop = 0; behindSchedule.observedAt = leg.arrival
        check(!behindSchedule.getOffHint(for: multiStop, location: nil, now: leg.arrival), "Fresh GPS progress prevents premature schedule-based get-off prompt")
        var ridingProgress = JourneyGuidanceProgress()
        ridingProgress.board(); ridingProgress.observedStop = 1; ridingProgress.observedAt = during
        let archiveURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
        let archiveStore = JourneyArchiveStore(url: archiveURL)
        defer { archiveStore.clear() }
        let sessionID = UUID()
        let snapshot = JourneyArchive(journey: journey, title: "Home", destination: end, progress: ridingProgress, sessionID: sessionID, suppressed: true, now: during)
        try archiveStore.save(snapshot)
        let archived = archiveStore.load()!
        check(archived.restored(at: during)?.legs[0].tripID == "t1" && archived.sessionID == sessionID, "Restore saved route and session identity")
        check(archived.progress.onBoard && archived.progress.observedStop == 1 && archived.automaticBoardingSuppressed, "Restore boarding, stop progress and manual correction")
        check(archived.destinationTitle == "Home" && archived.destination.coordinate.longitude == end.longitude, "Restore destination coordinates and title")
        check(archived.restored(at: journey.arrival.addingTimeInterval(7201)) == nil, "Discard expired journey")
        var invalidProgress = ridingProgress; invalidProgress.legIndex = -1
        let invalid = JourneyArchive(journey: journey, title: "Home", destination: end, progress: invalidProgress, sessionID: sessionID, suppressed: false, now: during)
        check(invalid.restored(at: during) == nil, "Reject corrupt saved step")
        invalidProgress = ridingProgress; invalidProgress.observedStop = 999
        check(JourneyArchive(journey: journey, title: "Home", destination: end, progress: invalidProgress, sessionID: sessionID, suppressed: false, now: during).restored(at: during) == nil, "Reject corrupt saved stop progress")
        invalidProgress = ridingProgress; invalidProgress.finish()
        check(JourneyArchive(journey: journey, title: "Home", destination: end, progress: invalidProgress, sessionID: sessionID, suppressed: false, now: during).restored(at: during) == nil, "Do not restore completed journeys")
        try Data("broken".utf8).write(to: archiveURL)
        check(archiveStore.load() == nil, "Ignore malformed archive without crashing")
        archiveStore.clear(); check(archiveStore.load() == nil, "Ending a journey removes persisted state")

        var movingLeg = leg; movingLeg.coordinates = [start, end]; movingLeg.followsShape = true
        func observation(_ index: Int, speed: Double = 8, age: Double = 0, tripID: String = "t1", serviceDate: String = "20260930", latitude: Double = 45.42) -> (CLLocation, Vehicle, Date) {
            let time = now.addingTimeInterval(300 + Double(index * 6))
            let point = CLLocationCoordinate2D(latitude: latitude, longitude: start.longitude + Double(index) * 0.0008)
            let fix = CLLocation(coordinate: point, altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10, course: 90, speed: speed, timestamp: time)
            let vehicle = Vehicle(id: "v", tripID: tripID, routeID: "88", latitude: point.latitude, longitude: point.longitude, timestamp: time.addingTimeInterval(-age), serviceDate: serviceDate)
            return (fix, vehicle, time)
        }
        var detector = BoardingDetector()
        var detected = false
        for index in 0..<4 {
            let (fix, vehicle, time) = observation(index)
            detected = detector.observe(fix, vehicle: vehicle, leg: movingLeg, now: time)
            if index < 3 { check(!detected, "Do not board from fewer than four movement samples \(index)") }
        }
        check(detected, "Board after sustained route movement matching the vehicle")
        for scenario in ["walking", "stale", "wrong-trip", "wrong-day", "off-route", "missing-shape", "stationary-vehicle"] {
            detector.reset(); var anyDetection = false
            for index in 0..<5 {
                var (fix, vehicle, time) = observation(index, speed: scenario == "walking" ? 1 : 8, age: scenario == "stale" ? 120 : 0, tripID: scenario == "wrong-trip" ? "other" : "t1", serviceDate: scenario == "wrong-day" ? "20261001" : "20260930", latitude: scenario == "off-route" ? 45.43 : 45.42)
                if scenario == "stationary-vehicle" { vehicle = Vehicle(id: "v", tripID: "t1", routeID: "88", latitude: start.latitude, longitude: start.longitude, timestamp: time, serviceDate: "20260930") }
                var candidate = movingLeg
                if scenario == "missing-shape" { candidate.followsShape = false }
                anyDetection = anyDetection || detector.observe(fix, vehicle: vehicle, leg: candidate, now: time)
            }
            check(!anyDetection, "Keep manual boarding for \(scenario)")
        }
        func floatField(_ field: Int, _ value: Float) -> [UInt8] {
            let bits = value.bitPattern
            return varint(UInt64(field << 3 | 5)) + (0..<4).map { UInt8(truncatingIfNeeded: bits >> ($0 * 8)) }
        }
        let position = message(1, text(1, "t1") + text(3, "20260930")) + message(2, floatField(1, 45.42) + floatField(2, -75.7)) + number(5, UInt64(now.timeIntervalSince1970)) + number(9, 1)
        let decodedVehicle = Vehicle.decode(message(2, message(4, position))).first
        check(decodedVehicle?.timestamp == now && decodedVehicle?.serviceDate == "20260930", "Decode vehicle freshness and service date for boarding evidence")
        check(decodedVehicle?.occupancy?.label == "Seats available", "Show crowding only when a vehicle publishes occupancy")
        let quickSchedule = Schedule(["stops.txt": Data("stop_id,stop_code,stop_name,stop_lat,stop_lon\nA,A,Start,45.42,-75.70\nB,B,End,45.42,-75.64\n".utf8),
                                      "routes.txt": Data("route_id,route_short_name,route_color,route_text_color\n88,88,FF0000,FFFFFF\n".utf8),
                                      "trips.txt": Data("route_id,service_id,trip_id,trip_headsign\n88,weekday,t1,East\n".utf8)])
        let quickTrip = LiveTrips.Trip(id: "t1", routeID: "88", vehicleID: "v",
                                       stops: [StopTime(stopID: "A", time: now.addingTimeInterval(300), sequence: 1),
                                               StopTime(stopID: "B", time: now.addingTimeInterval(1500), sequence: 2)],
                                       serviceDate: "20260930")
        let quick = JourneyQuickStart.make(trip: quickTrip, schedule: quickSchedule, alightCode: "B", boardingCode: "A", alreadyAboard: false, now: now)
        check(quick?.legs.first?.board.code == "A" && quick?.legs.first?.alight.code == "B", "Start guidance from a nearby line toward a chosen stop")
        check(JourneyQuickStart.make(trip: quickTrip, schedule: quickSchedule, alightCode: "B", boardingCode: nil, alreadyAboard: true, now: now)?.legs.first?.departure == now, "Already-on-board guidance starts from the current ride")
        check(JourneyQuickStart.make(trip: quickTrip, schedule: quickSchedule, alightCode: "B", boardingCode: "MISSED", alreadyAboard: false, now: now) == nil, "Do not silently board at another stop when the selected stop has passed")
        let context = JourneyRecoveryContext.make(journey: journey, progress: ridingProgress, location: nil, now: during)!
        check(context.origin.longitude == b.longitude && context.departure > leg.arrival, "Replan onboard journeys from their upcoming alighting stop")
        var alternative = journey
        alternative.legs[0].departure = leg.arrival.addingTimeInterval(600)
        alternative.legs[0].arrival = leg.arrival.addingTimeInterval(1800)
        let joined = context.joining(alternative)
        check(joined.legs.count == 2 && joined.legs[0].arrival == leg.arrival && context.accepts(joined, live: nil, now: during), "Replacement preserves current ride and allows transfer buffer")
        check(!context.accepts(joined, live: nil, now: alternative.legs[0].departure), "Reject replacement after its transfer window closes")
        check(!context.accepts(joined, live: feed(canceled: true), now: during), "Reject canceled replacement")
        check(!context.accepts(joined, live: feed(skipped: true), now: during), "Reject replacement when boarding stop becomes skipped")
        var missedLater = joined
        missedLater.legs.append(alternative.legs[0])
        check(!context.accepts(missedLater, live: nil, now: during), "Reject replacement with an impossible later transfer")
        let fromGPS = JourneyRecoveryContext.make(journey: journey, progress: .init(), location: fresh, now: during)!
        check(fromGPS.origin.longitude == end.longitude && fromGPS.retainedLeg == nil, "Use fresh rider location before boarding")
        let withoutGPS = JourneyRecoveryContext.make(journey: journey, progress: .init(), location: stale, now: during)!
        check(withoutGPS.origin.longitude == start.longitude, "Use labeled planned origin when GPS is stale")
        var offlineWalk = walk
        offlineWalk.instructions = [.init(text: "Turn left onto Bank Street", distance: 42)]
        offlineWalk.coordinates = [start, end]
        var offlineTrip = journey
        offlineTrip.legs[0].walk = offlineWalk
        offlineTrip.finalWalk = offlineWalk
        let actionID = UUID()
        let offlineSnapshot = JourneyArchive(journey: offlineTrip, title: "Home", destination: end, progress: .init(), sessionID: sessionID,
                                            suppressed: false, now: now, predictionsUpdatedAt: now, actionToken: actionID)
        try archiveStore.save(offlineSnapshot)
        let offlineRestored = archiveStore.load()!
        check(offlineRestored.restored(at: now)?.legs[0].walk.instructions == offlineWalk.instructions, "Boarding walk instructions survive disk round trip")
        check(offlineRestored.restored(at: now)?.finalWalk.instructions == offlineWalk.instructions, "Final walking instructions survive disk round trip")
        check(offlineRestored.restored(at: now)?.finalWalk.coordinates.count == 2, "Walking path survives disk round trip")
        check(offlineRestored.predictionsUpdatedAt == now && offlineRestored.actionToken == actionID, "Persist prediction age and action identity")
        var oldArchive = try JSONSerialization.jsonObject(with: JSONEncoder().encode(offlineSnapshot)) as! [String: Any]
        oldArchive.removeValue(forKey: "predictionsUpdatedAt"); oldArchive.removeValue(forKey: "actionToken")
        var oldLegs = oldArchive["legs"] as! [[String: Any]]
        var oldWalk = oldLegs[0]["walk"] as! [String: Any]; oldWalk.removeValue(forKey: "instructions")
        oldLegs[0]["walk"] = oldWalk; oldArchive["legs"] = oldLegs
        var oldFinal = oldArchive["finalWalk"] as! [String: Any]; oldFinal.removeValue(forKey: "instructions"); oldArchive["finalWalk"] = oldFinal
        let compatible = try JSONDecoder().decode(JourneyArchive.self, from: JSONSerialization.data(withJSONObject: oldArchive))
        check(compatible.restored(at: now)?.legs[0].walk.instructions.isEmpty == true && compatible.predictionsUpdatedAt == nil, "Older saved journeys remain readable")
        let xml = """
        <rss><channel><item><title>Detour on route 88</title><link>https://www.octranspo.com/en/alerts/example</link><category>AffectedRoutes-88 Bus</category><description><![CDATA[Stop (#1234) is closed]]></description></item></channel></rss>
        """
        let parsed = AlertFeedParser.parse(Data(xml.utf8))!
        check(parsed.count == 1 && parsed[0].routes == ["88"] && parsed[0].stops == ["1234"], "Read route category and stop from RSS")
        let multi = xml.replacingOccurrences(of: "AffectedRoutes-88 Bus", with: "affectedRoutes-61, 62, 63")
        check(AlertFeedParser.parse(Data(multi.utf8))?.first?.routes == ["61", "62", "63"], "Match every route in the published multi-route category format")
        check(!parsed[0].affects(journey), "A route alert naming another affected stop does not warn this trip")
        check(!parsed[0].affects(journey, startingAt: 1), "Exclude completed journey legs from alerts")
        var stopAlert = ServiceAlert(); stopAlert.stops = [b.code]
        check(stopAlert.affects(journey), "Match alighting stop to service alert")
        stopAlert.stops = ["other-stop"]
        check(!stopAlert.affects(journey), "Ignore unrelated alerts")
        var intermediate = journey
        let middle = Stop(code: "1234", name: "Intermediate", latitude: 45.42, longitude: -75.67, ids: ["middle-id"])
        intermediate.legs[0].callingPoints.insert(.init(stop: middle, time: now, sequence: 2), at: 1)
        stopAlert.stops = [middle.code]
        check(stopAlert.affects(intermediate), "Match closures at intermediate calling points")
        check(parsed[0].affects(intermediate), "Route and affected stop must both match")
        let published = ISO8601DateFormatter().date(from: "2026-10-01T12:00:00Z")!
        let interval = AlertScope.window(in: "From 10:00 am Monday, October 5 until 6:00 pm Friday, December 4, route 88 is detoured.", published: published)!
        check(PreparedTransitFeed.dayKey(interval.lowerBound) == "20261005" && PreparedTransitFeed.dayKey(interval.upperBound) == "20261204", "Extract published detour date window")
        check(PreparedTransitFeed.calendar.component(.hour, from: interval.lowerBound) == 10 && PreparedTransitFeed.calendar.component(.hour, from: interval.upperBound) == 18, "Apply published start and end hours")
        let nightText = "Nightly, from October 5 until the morning of October 9, between 11:00 pm and 5:00 am, route 88 is detoured."
        let nightWindow = AlertScope.window(in: nightText, published: published)!
        let nightHours = AlertScope.dailyHours(in: nightText)!
        check(PreparedTransitFeed.calendar.component(.hour, from: nightWindow.upperBound) == 5, "End a nightly alert on its stated final morning")
        check(!nightHours.contains(nightWindow.lowerBound.addingTimeInterval(2 * 3600), startingAt: nightWindow.lowerBound), "Do not show a nightly alert before its first evening")
        check(!nightHours.contains(nightWindow.lowerBound.addingTimeInterval(12 * 3600), startingAt: nightWindow.lowerBound), "Do not show a nightly alert at noon")
        check(nightHours.contains(nightWindow.lowerBound.addingTimeInterval(23 * 3600), startingAt: nightWindow.lowerBound), "Show a nightly alert during its stated hours")
        var timed = ServiceAlert(); timed.routes = ["88"]; timed.stops = [b.code]; timed.activeFrom = interval.lowerBound; timed.activeThrough = interval.upperBound
        check(!timed.affects(journey), "Exclude detour before its start date")
        let future = Journey(legs: journey.legs.map { leg in
            var value = leg; value.departure = interval.lowerBound.addingTimeInterval(3600); return value
        }, finalWalk: journey.finalWalk, requestedDeparture: interval.lowerBound)
        check(timed.match(future) == .confirmed, "Show detour while its date window applies")
        timed.activeThrough = interval.lowerBound.addingTimeInterval(-3600)
        check(!timed.affects(future), "Exclude ended detour")
        timed.activeThrough = interval.upperBound; timed.directions = ["W"]
        check(!timed.affects(future), "Suppress opposite-direction detour")
        timed.directions = ["E"]
        check(timed.match(future) == .confirmed, "Match travel direction from boarding to alighting")
        timed.closedStops = [b.code]
        check(timed.closesJourneyStop(future), "Confirmed closed alighting stop invalidates this journey")
        timed.closedStops = ["unrelated"]
        check(!timed.closesJourneyStop(future), "Unrelated stop closure does not invalidate this journey")
        timed.directions = []; timed.activeFrom = nil; timed.activeThrough = nil
        check(timed.match(future) == .possible, "Unverified dates are shown as possible alerts")
        timed.activeFrom = interval.lowerBound; timed.activeThrough = interval.upperBound; timed.stops = []
        check(timed.match(future) == .possible, "Route-wide alerts without affected stop data are labelled possible")
        check(AlertScope.directions(in: "WB route 88 detour") == ["W"], "Read direction from published alert title")
        let detourHTML = "<table><tr><td>#1234 -- Closed stop</td><td>88</td><td>#5678 -- Alternative stop</td></tr></table><a href='/images/files/maps/detours/2026/route88.png'>Map</a>"
        let affectedStops = AlertScope.affectedStops(in: detourHTML)
        check(affectedStops.closed == ["1234"] && affectedStops.alternative == ["5678"], "Read closed and alternate stops from a published detour table")
        check(AlertScope.publishedMap(in: detourHTML)?.lastPathComponent == "route88.png", "Link the agency's published detour map")
        let openEnded = AlertScope.openEndedStart(in: "From 5:00 am on Wednesday, September 9, until further notice, stop #1234 is relocated.", published: published)
        check(openEnded.map { PreparedTransitFeed.dayKey($0) == "20260909" && PreparedTransitFeed.calendar.component(.hour, from: $0) == 5 } == true, "Read effective time for a stop closure until further notice")
        let transferRisk = JourneyConnection.all(in: Journey(legs: [leg, JourneyLeg(tripID: "t2", route: leg.route, headsign: leg.headsign, board: b, alight: b,
            departure: leg.arrival.addingTimeInterval(300), arrival: leg.arrival.addingTimeInterval(500), walk: walk,
            live: true, coordinates: [])], finalWalk: finalWalk, requestedDeparture: now))[0]
        check(transferRisk.isTight && transferRisk.spare == 60 && transferRisk.usesPrediction, "Transfer cushion accounts for walking and boarding buffer")
        check(!transferRisk.isMissed, "Tight connection remains catchable")
        let missedTrip = Journey(legs: [leg, JourneyLeg(tripID: "t2", route: leg.route, headsign: leg.headsign, board: b, alight: b,
            departure: leg.arrival.addingTimeInterval(100), arrival: leg.arrival.addingTimeInterval(500), walk: walk,
            live: true, coordinates: [])], finalWalk: finalWalk, requestedDeparture: now)
        check(JourneyConnection.all(in: missedTrip)[0].isMissed, "Live delay can make a transfer impossible")
        var accessLeg = leg; accessLeg.wheelchairAccessible = .accessible
        var accessTrip = Journey(legs: [accessLeg], finalWalk: finalWalk, requestedDeparture: now)
        check(accessTrip.accessibilitySummary.contains("Stop access unknown"), "Unknown stop access is not presented as step-free")
        var inaccessibleBoard = a; inaccessibleBoard.wheelchairBoarding = .inaccessible
        accessTrip.legs = [JourneyLeg(tripID: accessLeg.tripID, route: accessLeg.route, headsign: accessLeg.headsign,
            board: inaccessibleBoard, alight: b, departure: accessLeg.departure, arrival: accessLeg.arrival,
            walk: walk, live: false, coordinates: [], wheelchairAccessible: .accessible)]
        check(accessTrip.accessibilitySummary.contains("marked inaccessible"), "Known inaccessible stop is called out")
        check(AlertFeedParser.parse(Data("<html>error</html>".utf8)) == nil, "Reject HTTP error pages instead of clearing alerts")
        check(AlertFeedParser.parse(Data("<rss><channel><item>".utf8)) == nil, "Reject truncated alert feeds")
        check(AlertFeedParser.parse(Data("<rss><channel/></rss>".utf8))?.isEmpty == true, "Accept a valid empty alert feed")
        check(PredictionStatus(hasPredictions: true, feedAvailable: false, updatedAt: now).title.contains("Last known"), "Offline predictions are visibly stale")
        check(PredictionStatus(hasPredictions: false, feedAvailable: true, updatedAt: now).title.contains("Scheduled"), "Available feed does not label unmatched trips live")
        check(PredictionStatus(hasPredictions: true, feedAvailable: true, updatedAt: now, predictionsAreCurrent: false).title.contains("Last known"), "A fresh feed does not make missing trip predictions fresh")
        check(PredictionStatus(hasPredictions: true, feedAvailable: true, updatedAt: now).title == "Live predictions", "Fresh matched predictions are labeled live")
        func action(session: UUID = sessionID, index: Int = 0, token: UUID = actionID, alighting: Bool = false,
                    onBoard: Bool = false, finished: Bool = false, expiry: Date = now.addingTimeInterval(600)) -> Bool {
            JourneyActionValidation.accepts(sessionID: session.uuidString, expectedSessionID: sessionID, legIndex: index,
                currentLegIndex: 0, actionToken: token.uuidString, expectedToken: actionID, alighting: alighting,
                onBoard: onBoard, legCount: 1, finished: finished, expiresAt: expiry, now: now)
        }
        check(action(), "Accept current boarding action")
        check(action(alighting: true, onBoard: true), "Accept current alighting action")
        check(!action(session: UUID()), "Reject action for a previous journey")
        check(!action(index: 1) && !action(index: -1), "Reject action for wrong journey step")
        check(!action(token: UUID()), "Reject repeated or superseded action token")
        check(!action(onBoard: true) && !action(alighting: true), "Reject repeated boarding and premature alighting")
        check(!action(finished: true) && !action(expiry: now), "Reject finished and expired journey actions")
        print("Passed \(count) journey feature scenarios")
    }
}
