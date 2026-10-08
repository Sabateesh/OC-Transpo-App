import CoreLocation
import Foundation

@main
struct JourneyPlannerTests {
    static func main() async throws {
        let date = ISO8601DateFormatter().date(from: "2026-09-30T12:00:00Z")!
        let origin = CLLocationCoordinate2D(latitude: 45.42, longitude: -75.70)
        let destination = CLLocationCoordinate2D(latitude: 45.42, longitude: -75.64)
        var count = 0
        func check(_ value: Bool, _ name: String) { if !value { FileHandle.standardError.write(Data("FAILED: \(name)\n".utf8)); exit(1) }; count += 1; print("PASS", name) }
        func files(_ times: String, calendar: String? = nil, exceptions: String = "service_id,date,exception_type\n") -> [String: Data] {
            let values = [
                "stops.txt": "stop_id,stop_code,stop_name,stop_lat,stop_lon,location_type\nA,A,Start,45.42,-75.70,0\nB,B,Transfer,45.42,-75.67,0\nX,,Across the street,45.42,-75.669,0\nC,C,End,45.42,-75.64,0\nD,D,Further,45.42,-75.61,0\n",
                "routes.txt": "route_id,route_short_name,route_color,route_text_color\n88,88,FF0000,FFFFFF\n6,6,008800,FFFFFF\n7,7,008800,FFFFFF\n",
                "trips.txt": "route_id,service_id,trip_id,trip_headsign\n88,weekday,t1,East\n6,weekday,t2,North\n7,weekday,t3,South\n",
                "calendar.txt": calendar ?? "service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date\nweekday,1,1,1,1,1,0,0,20260901,20261031\n",
                "calendar_dates.txt": exceptions,
                "stop_times.txt": "trip_id,arrival_time,departure_time,stop_id,stop_sequence,pickup_type,drop_off_type\n" + times
            ]
            return values.mapValues { Data($0.utf8) }
        }
        func plan(_ table: RoutingTimetable, at: Date? = nil, end: CLLocationCoordinate2D? = nil,
                  walks: [WalkKey: JourneyWalk] = [:], blocked: Set<WalkKey> = []) -> [Journey] {
            JourneyPlanner.plan(timetable: table, origin: origin, destination: end ?? destination,
                                departure: at ?? date, walks: walks, blocked: blocked)
        }
        let directTimes = "t1,08:05:00,08:05:00,A,1,0,0\nt1,08:15:00,08:15:00,B,2,0,0\nt1,08:25:00,08:25:00,C,3,0,0\n"
        let direct = try RoutingTimetable(files: files(directTimes), date: date)
        let first = plan(direct).first!
        check(first.legs.count == 1, "Direct route without any live feed")
        check(first.legs[0].board.code == "A" && first.legs[0].alight.code == "C", "Correct boarding and alighting stops")
        check(!first.legs[0].live, "Scheduled times labelled accurately")
        check(direct.stops.contains { $0.ids == ["X"] }, "Keep stops without public codes")
        var accessFiles = files(directTimes)
        accessFiles["stops.txt"] = Data("stop_id,stop_code,stop_name,stop_lat,stop_lon,location_type,wheelchair_boarding\nA,A,Start,45.42,-75.70,0,1\nB,B,Transfer,45.42,-75.67,0,0\nX,,Across the street,45.42,-75.669,0,0\nC,C,End,45.42,-75.64,0,1\nD,D,Further,45.42,-75.61,0,0\n".utf8)
        accessFiles["trips.txt"] = Data("route_id,service_id,trip_id,trip_headsign,wheelchair_accessible\n88,weekday,t1,East,1\n6,weekday,t2,North,2\n7,weekday,t3,South,0\n".utf8)
        let accessibleTable = try RoutingTimetable(files: accessFiles, date: date)
        let accessiblePlans = JourneyPlanner.plan(timetable: accessibleTable, origin: origin, destination: destination,
                                                 departure: date, accessibleVehiclesOnly: true)
        check(accessiblePlans.first?.legs[0].wheelchairAccessible == .accessible, "Filter to confirmed accessible vehicles")
        check(accessiblePlans.first?.legs[0].board.wheelchairBoarding == .accessible, "Carry stop accessibility into journey")
        let accessibleArrivals = JourneyPlanner.plan(timetable: accessibleTable, origin: origin, destination: destination,
            departure: date, arriveBy: date.addingTimeInterval(3600), accessibleVehiclesOnly: true)
        check(!accessibleArrivals.isEmpty && accessibleArrivals.allSatisfy { $0.legs.allSatisfy { $0.wheelchairAccessible == .accessible } }, "Arrive-by respects accessibility filter")
        accessFiles["stops.txt"] = Data(String(decoding: accessFiles["stops.txt"]!, as: UTF8.self).replacingOccurrences(of: "C,End,45.42,-75.64,0,1", with: "C,End,45.42,-75.64,0,2").utf8)
        let blockedAccess = try RoutingTimetable(files: accessFiles, date: date)
        check(JourneyPlanner.plan(timetable: blockedAccess, origin: origin, destination: destination, departure: date,
                                  accessibleVehiclesOnly: true).isEmpty, "Exclude stop explicitly marked inaccessible")
        check(JourneyPlanner.plan(timetable: direct, origin: origin, destination: destination, departure: date,
                                  accessibleVehiclesOnly: true).isEmpty, "Unknown vehicle access is not shown as confirmed accessible")
        var inheritedFiles = files(directTimes)
        inheritedFiles["stops.txt"] = Data("stop_id,stop_code,stop_name,stop_lat,stop_lon,location_type,parent_station,wheelchair_boarding\nS,S,Station,45.42,-75.70,1,,1\nA,A,Start,45.42,-75.70,0,S,0\nB,B,Transfer,45.42,-75.67,0,,0\nC,C,End,45.42,-75.64,0,,0\n".utf8)
        check(try PreparedTransitFeed(files: inheritedFiles).stops.first { $0.code == "A" }?.wheelchairBoarding == .accessible,
              "Child stop inherits known station wheelchair access")
        let transferTimes = "t1,08:05:00,08:05:00,A,1,0,0\nt1,08:15:00,08:15:00,B,2,0,0\nt2,08:22:00,08:22:00,X,1,0,0\nt2,08:40:00,08:40:00,C,2,0,0\n"
        let transfers = try RoutingTimetable(files: files(transferTimes), date: date)
        check(plan(transfers).first?.legs.count == 2, "Walk across street between different transfer stops")
        var choiceFiles = files(transferTimes + "t1b,08:30:00,08:30:00,A,1,0,0\nt1b,08:40:00,08:40:00,B,2,0,0\nt2b,08:48:00,08:48:00,X,1,0,0\nt2b,09:05:00,09:05:00,C,2,0,0\n")
        choiceFiles["trips.txt"] = Data("route_id,service_id,trip_id,trip_headsign\n88,weekday,t1,East\n88,weekday,t1b,East\n6,weekday,t2,North\n6,weekday,t2b,North\n".utf8)
        let choiceTable = try RoutingTimetable(files: choiceFiles, date: date)
        let choiceNetwork = RoutingNetwork(timetable: choiceTable, index: RoutingIndex(choiceTable), version: "choices")
        let choiceJourney = plan(choiceTable).first { $0.legs.map(\.tripID) == ["t1", "t2"] }!
        let choices = JourneyDepartures.options(for: choiceJourney, legIndex: 0, network: choiceNetwork, live: nil, now: date)
        let laterChoice = choices.first { $0.leg.tripID == "t1b" }
        check(laterChoice?.journey.legs.map(\.tripID) == ["t1b", "t2b"], "Switching the first departure finds a catchable later transfer")
        check(laterChoice?.journey.arrival == date.addingTimeInterval(65 * 60), "Departure card updates the final arrival time")
        check(JourneyDepartures.options(for: choiceJourney, legIndex: 1, network: choiceNetwork, live: nil, now: date).contains { $0.leg.tripID == "t2b" }, "Change a connecting departure independently")
        var noLaterFiles = files(transferTimes + "t1b,08:30:00,08:30:00,A,1,0,0\nt1b,08:40:00,08:40:00,B,2,0,0\n")
        noLaterFiles["trips.txt"] = Data("route_id,service_id,trip_id,trip_headsign\n88,weekday,t1,East\n88,weekday,t1b,East\n6,weekday,t2,North\n".utf8)
        let noLater = try RoutingTimetable(files: noLaterFiles, date: date)
        let noLaterNetwork = RoutingNetwork(timetable: noLater, index: RoutingIndex(noLater), version: "no-transfer")
        check(JourneyDepartures.options(for: choiceJourney, legIndex: 0, network: noLaterNetwork, live: nil, now: date).allSatisfy { $0.leg.tripID != "t1b" }, "Hide departures that lose their onward connection")
        let tight = try RoutingTimetable(files: files(transferTimes.replacingOccurrences(of: "08:22:00", with: "08:16:00")), date: date)
        check(plan(tight).allSatisfy { $0.legs.last!.departure.timeIntervalSince($0.legs.first!.arrival) >= 180 }, "Reject missed transfer, including next-day combinations")
        let twoTransfers = try RoutingTimetable(files: files(transferTimes + "t3,08:45:00,08:45:00,C,1,0,0\nt3,09:00:00,09:00:00,D,2,0,0\n"), date: date)
        check(plan(twoTransfers, end: .init(latitude:45.42, longitude:-75.61)).first?.legs.count == 3, "Two transfers")
        let reverse = try RoutingTimetable(files: files("t1,08:05:00,08:05:00,C,1,0,0\nt1,08:25:00,08:25:00,A,2,0,0\n"), date: date)
        check(plan(reverse).isEmpty, "No backward riding")
        let noPickup = try RoutingTimetable(files: files(directTimes.replacingOccurrences(of: "A,1,0,0", with: "A,1,1,0")), date: date)
        check(plan(noPickup).isEmpty, "Honor pickup restriction")
        let noDropoff = try RoutingTimetable(files: files(directTimes.replacingOccurrences(of: "C,3,0,0", with: "C,3,0,1")), date: date)
        check(plan(noDropoff).isEmpty, "Honor dropoff restriction")
        let removed = try RoutingTimetable(files: files(directTimes, exceptions: "service_id,date,exception_type\nweekday,20260930,2\n"), date: date)
        check(!removed.trips.contains { $0.serviceDate == "20260930" }, "Calendar exception removes service")
        let sunday = ISO8601DateFormatter().date(from: "2026-10-04T12:00:00Z")!
        let added = try RoutingTimetable(files: files(directTimes, exceptions: "service_id,date,exception_type\nweekday,20261004,1\n"), date: sunday)
        check(added.trips.contains { $0.serviceDate == "20261004" }, "Calendar exception adds Sunday service")
        let overnight = try RoutingTimetable(files: files("t1,24:10:00,24:10:00,A,1,0,0\nt1,24:30:00,24:30:00,C,2,0,0\n"), date: date)
        let midnight = ISO8601DateFormatter().date(from: "2026-09-30T04:00:00Z")!
        check(plan(overnight, at: midnight).first?.legs[0].departure == midnight.addingTimeInterval(600), "Previous service day's times beyond 24:00")
        check(plan(direct, at: date.addingTimeInterval(600)).first!.legs[0].departure > date.addingTimeInterval(20*3600), "Look ahead to next day's service")
        check(plan(direct, end: .init(latitude:45.50,longitude:-75.90)).isEmpty, "Do not invent long walks")
        let aKey = first.legs[0].walk.key
        check(plan(direct, blocked: [aKey]).isEmpty, "Exclude inaccessible walking path")
        var slower = first.legs[0].walk
        slower.duration = 20 * 60
        slower.verified = true
        let later = try RoutingTimetable(files: files(directTimes + "t2,08:35:00,08:35:00,A,1,0,0\nt2,09:00:00,09:00:00,C,2,0,0\n"), date: date)
        check(plan(later, walks: [aKey:slower]).first?.legs[0].tripID == "t2", "Replan after walking duration misses bus")
        let addressBeyondOldRadius = CLLocationCoordinate2D(latitude:45.429,longitude:-75.64)
        check(!plan(direct, end:addressBeyondOldRadius).isEmpty, "Address over 700 metres from stop")
        let unsorted = try RoutingTimetable(files: files(directTimes.split(separator:"\n").reversed().joined(separator:"\n") + "\n"), date:date)
        check(plan(unsorted).first?.legs[0].departure == first.legs[0].departure, "Use stop_sequence rather than file order")
        check(RoutingTimetable.seconds("25:10:00") == 90600 && RoutingTimetable.seconds("08:99:00") == nil, "Parse extended GTFS times and reject malformed values")
        func varint(_ value: UInt64) -> [UInt8] {
            var value = value, bytes: [UInt8] = []
            while value >= 128 { bytes.append(UInt8(value & 127) | 128); value >>= 7 }
            bytes.append(UInt8(value)); return bytes
        }
        func number(_ field: Int, _ value: UInt64) -> [UInt8] { varint(UInt64(field << 3)) + varint(value) }
        func message(_ field: Int, _ value: [UInt8]) -> [UInt8] { varint(UInt64(field << 3 | 2)) + varint(UInt64(value.count)) + value }
        func text(_ field: Int, _ value: String) -> [UInt8] { message(field, Array(value.utf8)) }
        func feed(canceled: Bool = false, skipped: Bool = false, delay: Int = 0) -> LiveTrips {
            let descriptor = text(1, "t1") + text(3, "20260930") + text(5, "88") + (canceled ? number(4, 3) : [])
            let start = UInt64(date.timeIntervalSince1970) + 300 + UInt64(delay)
            let event = number(2, start)
            let update = text(4, "A") + number(1, 1) + message(3, event) + (skipped ? number(5, 1) : [])
            return LiveTrips(message(2, message(3, message(1, descriptor) + message(2, update))))
        }
        let canceled = feed(canceled: true)
        check(canceled.canceledTripIDs.contains("t1") && canceled.trips.isEmpty, "Decode canceled trip without showing arrivals")
        let canceledPlans = JourneyPlanner.plan(timetable: direct, origin: origin, destination: destination, departure: date, live: canceled)
        check(canceledPlans.isEmpty, "Canceled service date cannot be boarded")
        let delayed = JourneyPlanner.plan(timetable: direct, origin: origin, destination: destination, departure: date, live: feed(delay: 600))
        check(delayed.first?.legs[0].departure == first.legs[0].departure.addingTimeInterval(600), "Overlay live departure delay")
        check(delayed.first?.legs[0].arrival == first.legs[0].arrival.addingTimeInterval(600), "Propagate delay to later scheduled stops")
        let skipped = JourneyPlanner.plan(timetable: direct, origin: origin, destination: destination, departure: date, live: feed(skipped: true))
        check(skipped.isEmpty, "Skipped boarding stop cannot be boarded")
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cachedFiles = files(directTimes)
        for (name, data) in cachedFiles { try data.write(to: tmp.appending(path: name)) }
        try cachedFiles.keys.map { $0 + ":test" }.joined(separator: "|").write(to: tmp.appending(path: "version"), atomically: true, encoding: .utf8)
        try String(Date.now.timeIntervalSince1970).write(to: tmp.appending(path: "checked"), atomically: true, encoding: .utf8)
        let store = RoutingStore(folder: tmp)
        async let today = store.load(for: date)
        async let tomorrow = store.load(for: date.addingTimeInterval(86400))
        let (cachedToday, cachedTomorrow) = try await (today, tomorrow)
        check(cachedToday.day == "20260930" && cachedTomorrow.day == "20261001", "Concurrent different-date searches use correct cached calendar")
        try Data("corrupt cache".utf8).write(to: tmp.appending(path: "timetable-compact.json"))
        let recovered = try await RoutingStore(folder: tmp).load(for: date)
        check(!plan(recovered).isEmpty, "Rebuild corrupt compiled cache from downloaded files without network")
        let plainTimes = "trip_id,stop_id,arrival_time\r\nt1,A,08:00:00\r\nignore,B,09:00:00\r\nt1,C,10:00:00"
        var parsed: [String] = []
        readRoutingStopTimes(Data(plainTimes.utf8), tripIDs:["t1"]) { parsed.append($0("stop_id")) }
        check(parsed == ["A", "C"], "Fast stop-time reader handles CRLF, inactive trips, and final unterminated line")
        parsed = []
        readRoutingStopTimes(Data("stop_id,trip_id\nA,t1\n".utf8), tripIDs:["t1"]) { parsed.append($0("stop_id")) }
        check(parsed == ["A"], "Fallback supports reordered CSV columns")
        parsed = []
        readRoutingStopTimes(Data("trip_id,stop_id\nt1,\"A,B\"\n".utf8), tripIDs:["t1"]) { parsed.append($0("stop_id")) }
        check(parsed == ["A,B"], "Fallback preserves quoted CSV fields")
        let deadline = date.addingTimeInterval(3600)
        let arrivalOptions = JourneyPlanner.plan(timetable: later, origin: origin, destination: destination, departure: date, arriveBy: deadline)
        check(arrivalOptions.first?.legs[0].tripID == "t2", "Arrive by chooses the latest feasible departure")
        check(arrivalOptions.allSatisfy { $0.arrival <= deadline && $0.leave >= date }, "Arrive by respects deadline and earliest departure")
        let exact = JourneyPlanner.plan(timetable: direct, origin: origin, destination: destination, departure: date, arriveBy: date.addingTimeInterval(25 * 60))
        check(exact.first?.arrival == date.addingTimeInterval(25 * 60), "A trip arriving exactly at the deadline is allowed")
        let arrivalTransfers = JourneyPlanner.plan(timetable: transfers, origin: origin, destination: destination, departure: date, arriveBy: date.addingTimeInterval(45 * 60))
        check(arrivalTransfers.first?.legs.count == 2, "Arrive by supports walking transfers")
        check(arrivalTransfers.first?.legs.first?.board.code == "A" && arrivalTransfers.first?.legs.last?.alight.code == "C", "Reverse search returns forward journey instructions")
        let lateArrival = JourneyPlanner.plan(timetable: direct, origin: origin, destination: destination, departure: date, live: feed(delay: 600), arriveBy: date.addingTimeInterval(30 * 60))
        check(lateArrival.isEmpty, "Live delay excludes trips that miss arrival deadline")
        let canceledArrival = JourneyPlanner.plan(timetable: direct, origin: origin, destination: destination, departure: date, live: canceled, arriveBy: deadline)
        check(canceledArrival.isEmpty, "Arrive by excludes cancelled trips")
        check(JourneyPlanner.plan(timetable: direct, origin: origin, destination: destination, departure: date, arriveBy: date.addingTimeInterval(-1)).isEmpty, "Reject arrival deadlines in the past")
        check(delayed.first?.legs[0].delay == 600, "Expose delay relative to scheduled departure")
        check(delayed.first?.id == first.id, "Live time changes preserve journey identity")
        print("Passed \(count) scheduled routing scenarios")
    }
}
