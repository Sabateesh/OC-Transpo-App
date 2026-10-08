import CoreLocation
import Foundation

struct WalkKey: Hashable { let from: Int; let to: Int }

struct WalkingInstruction: Codable, Equatable {
    let text: String
    let distance: Double
}

struct JourneyWalk {
    let key: WalkKey
    let from: CLLocationCoordinate2D
    let to: CLLocationCoordinate2D
    var duration: TimeInterval
    var distance: Double
    var verified = false
    var coordinates: [CLLocationCoordinate2D] = []
    var instructions: [WalkingInstruction] = []
}

struct JourneyCallingPoint: Codable {
    let stop: Stop
    let time: Date
    let sequence: Int
}

struct JourneyLeg {
    let tripID: String
    let route: Route
    let headsign: String
    let board: Stop
    let alight: Stop
    var departure: Date
    var arrival: Date
    var walk: JourneyWalk
    var live: Bool
    var coordinates: [CLLocationCoordinate2D]
    var serviceDate = ""
    var scheduledDeparture: Date? = nil
    var shapeID: String? = nil
    var shapeStart: Double? = nil
    var shapeEnd: Double? = nil
    var callingPoints: [JourneyCallingPoint] = []
    var followsShape = false
    var wheelchairAccessible: WheelchairAccess? = nil
    var delay: TimeInterval { departure.timeIntervalSince(scheduledDeparture ?? departure) }
}

struct Journey: Identifiable {
    var legs: [JourneyLeg]
    var finalWalk: JourneyWalk
    let requestedDeparture: Date
    var arrival: Date { legs.last!.arrival.addingTimeInterval(finalWalk.duration) }
    var leave: Date { legs[0].departure.addingTimeInterval(-legs[0].walk.duration - 60) }
    var duration: TimeInterval { arrival.timeIntervalSince(leave) }
    var walking: TimeInterval { legs.reduce(finalWalk.duration) { $0 + $1.walk.duration } }
    var id: String { legs.map { "\($0.tripID):\($0.board.ids[0]):\($0.alight.ids[0]):\($0.serviceDate)" }.joined(separator: "|") }
    var walks: [JourneyWalk] { legs.map(\.walk) + [finalWalk] }
}

enum JourneyPlanner {
    static func walkingTime(_ distance: Double) -> TimeInterval { distance * 1.35 / 1.25 }

    static func plan(timetable: RoutingTimetable, origin: CLLocationCoordinate2D,
                     destination: CLLocationCoordinate2D, departure: Date,
                     walks: [WalkKey: JourneyWalk] = [:], blocked: Set<WalkKey> = [],
                     live: LiveTrips? = nil, arriveBy: Date? = nil, boardingBuffer: TimeInterval = 60, index suppliedIndex: RoutingIndex? = nil, accessibleVehiclesOnly: Bool = false) -> [Journey] {
        if let arriveBy {
            return planArriving(timetable: timetable, origin: origin, destination: destination, earliestDeparture: departure, deadline: arriveBy, walks: walks, blocked: blocked, live: live, index: suppliedIndex, accessibleVehiclesOnly: accessibleVehiclesOnly)
        }
        let stops = timetable.stops
        let index = suppliedIndex ?? RoutingIndex(timetable)
        let points = index.geometry.points
        let start = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let end = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        func coordinate(_ i: Int) -> CLLocationCoordinate2D {
            if i == -1 { return origin }
            if i == -2 { return destination }
            return points[i].coordinate
        }
        func walk(_ from: Int, _ to: Int, distance: Double) -> JourneyWalk? {
            let key = WalkKey(from: from, to: to)
            if blocked.contains(key) { return nil }
            if let value = walks[key] { return value }
            return JourneyWalk(key: key, from: coordinate(from), to: coordinate(to),
                               duration: walkingTime(distance), distance: distance * 1.35)
        }
        struct Label {
            let time: Date
            let legs: [JourneyLeg]
            var walk: JourneyWalk
        }
        var previous: [Int: Label] = [:]
        var exits: [Int: JourneyWalk] = [:]
        for (i, distance) in index.geometry.near(start, radius: 1600) {
            if let walk = walk(-1, i, distance: distance), walk.duration <= 25 * 60 {
                previous[i] = Label(time: departure.addingTimeInterval(walk.duration + boardingBuffer), legs: [], walk: walk)
            }
        }
        for (i, distance) in index.geometry.near(end, radius: 1600) {
            if let walk = walk(i, -2, distance: distance), walk.duration <= 25 * 60 { exits[i] = walk }
        }
        guard !previous.isEmpty, !exits.isEmpty else { return [] }
        func neighbours(_ i: Int) -> [(Int, JourneyWalk)] {
            index.geometry.transfers[i].compactMap { j, distance in walk(i, j, distance: distance).map { (j, $0) } }
        }
        let latestBoarding = departure.addingTimeInterval(24 * 3600)
        let horizon = latestBoarding.addingTimeInterval(4 * 3600)
        let trips = updatedTrips(timetable, live: live).filter {
            if accessibleVehiclesOnly && $0.wheelchairAccessible != .accessible { return false }
            guard let first = $0.calls.first, let last = $0.calls.last else { return false }
            return first.departure <= horizon && last.arrival >= departure
        }
        let byKey = Dictionary(trips.map { (RoutingIndex.key($0), $0) }, uniquingKeysWith: { _, last in last })
        var results: [Journey] = []
        for _ in 0..<4 {
            if Task.isCancelled { return [] }
            var reached: [Int: Label] = [:]
            let candidates = index.candidates(from: previous.map { ($0.key, $0.value.time) }, live: live != nil)
            for candidate in candidates {
                guard let trip = byKey[index.tripKeys[candidate]] else { continue }
                if Task.isCancelled { return [] }
                let route = Schedule.route(trip.routeID, in: timetable.routes)
                let scheduled = Dictionary((trip.scheduledCalls ?? []).map { ($0.sequence, $0.departure) }, uniquingKeysWith: { first, _ in first })
                var boarding: (label: Label, index: Int)?
                for (index, call) in trip.calls.enumerated() {
                    if let boarding, index > boarding.index, call.dropoff,
                       call.arrival >= trip.calls[boarding.index].departure, call.arrival <= horizon,
                       (exits[call.stop] != nil || reached[call.stop] == nil || call.arrival < reached[call.stop]!.time),
                       (!accessibleVehiclesOnly || stops[call.stop].wheelchairBoarding != .inaccessible) {
                        let board = trip.calls[boarding.index]
                        let leg = JourneyLeg(tripID: trip.id, route: route,
                                             headsign: trip.headsign, board: stops[board.stop], alight: stops[call.stop],
                                             departure: board.departure, arrival: call.arrival, walk: boarding.label.walk,
                                             live: trip.live, coordinates: trip.calls[boarding.index...index].map { points[$0.stop].coordinate },
                                             serviceDate: trip.serviceDate, scheduledDeparture: scheduled[board.sequence] ?? board.departure,
                                             shapeID: trip.shapeID, shapeStart: board.shapeDistance, shapeEnd: call.shapeDistance,
                                             callingPoints: trip.calls[boarding.index...index].map { JourneyCallingPoint(stop: stops[$0.stop], time: $0.arrival, sequence: $0.sequence) }, wheelchairAccessible: trip.wheelchairAccessible)
                        let legs = boarding.label.legs + [leg]
                        let label = Label(time: call.arrival, legs: legs, walk: boarding.label.walk)
                        if reached[call.stop] == nil || call.arrival < reached[call.stop]!.time { reached[call.stop] = label }
                        if let exit = exits[call.stop] {
                            results.append(Journey(legs: legs, finalWalk: exit, requestedDeparture: departure))
                        }
                    }
                    if call.pickup, let label = previous[call.stop], call.departure >= label.time,
                       (!accessibleVehiclesOnly || stops[call.stop].wheelchairBoarding != .inaccessible),
                       (!label.legs.isEmpty || call.departure <= latestBoarding),
                       !label.legs.contains(where: { $0.tripID == trip.id }),
                       (label.legs.last?.route.name != route.name || label.legs.last?.headsign != trip.headsign) {
                        if boarding == nil || label.walk.duration < boarding!.label.walk.duration {
                            boarding = (label, index)
                        }
                    }
                }
            }
            previous = [:]
            for (stop, label) in reached {
                for (next, walk) in neighbours(stop) {
                    let time = label.time.addingTimeInterval(max(180, walk.duration + 120))
                    if previous[next] == nil || time < previous[next]!.time {
                        previous[next] = Label(time: time, legs: label.legs, walk: walk)
                    }
                }
            }
        }
        var seen: Set<String> = []
        var routeCounts: [String: Int] = [:]
        func score(_ journey: Journey) -> Double {
            journey.arrival.timeIntervalSince(departure) + journey.walking * 0.3 + Double(journey.legs.count - 1) * 180
        }
        struct Ranked { let journey: Journey; let score: Double; let id: String }
        var ranked: [Ranked] = results.map { Ranked(journey: $0, score: score($0), id: $0.id) }
        ranked.sort { left, right in
            if left.score == right.score { return left.id < right.id }
            return left.score < right.score
        }
        var selected: [Journey] = []
        for candidate in ranked {
            let journey = candidate.journey
            let signature = journey.legs.map { "\($0.route.name):\($0.board.ids[0]):\($0.alight.ids[0])" }.joined(separator: ">")
            let routeSignature = journey.legs.map { $0.route.name + ":" + $0.headsign }.joined(separator: ">")
            guard seen.insert(signature).inserted, routeCounts[routeSignature, default: 0] < 3 else { continue }
            routeCounts[routeSignature, default: 0] += 1
            selected.append(journey)
            if selected.count == 18 { break }
        }
        return selected
    }

    static func updatedTrips(_ timetable: RoutingTimetable, live: LiveTrips?) -> [RoutingTrip] {
        let stops = timetable.stops
        return timetable.trips.compactMap { scheduled -> RoutingTrip? in
            var trip = scheduled
            if let live {
                if let dates = live.canceledTripDates[trip.id],
                   dates.contains(trip.serviceDate) || (dates.contains("") && trip.serviceDate == RoutingTimetable.dayKey(.now)) { return nil }
                if let update = live.trips[trip.id],
                   update.serviceDate == trip.serviceDate || (update.serviceDate == nil && trip.serviceDate == RoutingTimetable.dayKey(.now)) {
                    trip.scheduledCalls = trip.calls
                    let updates = Dictionary(update.stops.map { ($0.stopID, $0) }, uniquingKeysWith: { _, last in last })
                    let bySequence = Dictionary(update.stops.compactMap { stop in stop.sequence.map { ($0, stop) } }, uniquingKeysWith: { _, last in last })
                    var delay: TimeInterval = 0
                    for i in trip.calls.indices {
                        let stopID = stops[trip.calls[i].stop].ids[0]
                        if let prediction = bySequence[trip.calls[i].sequence] ?? updates[stopID] {
                            delay = prediction.time.timeIntervalSince(trip.calls[i].departure)
                            trip.calls[i].departure = prediction.time
                            trip.calls[i].arrival = prediction.arrival ?? prediction.time
                            trip.live = true
                        } else {
                            trip.calls[i].departure.addTimeInterval(delay)
                            trip.calls[i].arrival.addTimeInterval(delay)
                        }
                    }
                    trip.calls.removeAll { update.skippedSequences.contains($0.sequence) || update.skippedStopIDs.contains(stops[$0.stop].ids[0]) }
                }
            }
            return trip
        }
    }

    private static func planArriving(timetable: RoutingTimetable, origin: CLLocationCoordinate2D,
                                     destination: CLLocationCoordinate2D, earliestDeparture: Date, deadline: Date,
                                     walks: [WalkKey: JourneyWalk], blocked: Set<WalkKey>, live: LiveTrips?, index preparedIndex: RoutingIndex?, accessibleVehiclesOnly: Bool) -> [Journey] {
        guard deadline > earliestDeparture else { return [] }
        func flip(_ time: Date) -> Date { Date(timeIntervalSinceReferenceDate: -time.timeIntervalSinceReferenceDate) }
        func index(_ value: Int) -> Int { value == -1 ? -2 : value == -2 ? -1 : value }
        func key(_ value: WalkKey) -> WalkKey { WalkKey(from: index(value.to), to: index(value.from)) }
        func reverseWalk(_ value: JourneyWalk) -> JourneyWalk {
            JourneyWalk(key: key(value.key), from: value.to, to: value.from, duration: value.duration,
                        distance: value.distance, verified: value.verified, coordinates: value.coordinates.reversed())
        }
        let adjusted = updatedTrips(timetable, live: live)
        let reversed = adjusted.map { trip -> RoutingTrip in
            var result = trip
            result.calls = trip.calls.reversed().map {
                RoutingCall(stop: $0.stop, sequence: $0.sequence, arrival: flip($0.departure), departure: flip($0.arrival),
                            pickup: $0.dropoff, dropoff: $0.pickup, shapeDistance: $0.shapeDistance)
            }
            result.scheduledCalls = nil
            return result
        }
        let reverseTable = RoutingTimetable(stops: timetable.stops, routes: timetable.routes, trips: reversed, day: timetable.day)
        let reverseWalks = Dictionary(walks.map { (key($0.key), reverseWalk($0.value)) }, uniquingKeysWith: { first, _ in first })
        let backward = plan(timetable: reverseTable, origin: destination, destination: origin, departure: flip(deadline),
                            walks: reverseWalks, blocked: Set(blocked.map(key)), boardingBuffer: 0, index: RoutingIndex(reverseTable, geometry: preparedIndex?.geometry), accessibleVehiclesOnly: accessibleVehiclesOnly)
        let originals = Dictionary(adjusted.map { ($0.id + ":" + $0.serviceDate, $0) }, uniquingKeysWith: { first, _ in first })
        return backward.compactMap { journey -> Journey? in
            let reverseLegs = Array(journey.legs.reversed())
            var legs: [JourneyLeg] = []
            for (i, leg) in reverseLegs.enumerated() {
                let trip = originals[leg.tripID + ":" + leg.serviceDate]
                let startSequence = leg.callingPoints.last?.sequence
                let endSequence = leg.callingPoints.first?.sequence
                let points = trip?.calls.filter { call in
                    guard let startSequence, let endSequence else { return false }
                    return call.sequence >= startSequence && call.sequence <= endSequence
                }.map { JourneyCallingPoint(stop: timetable.stops[$0.stop], time: $0.arrival, sequence: $0.sequence) } ?? []
                let scheduled = (trip?.scheduledCalls ?? trip?.calls)?.first { $0.sequence == startSequence }?.departure
                legs.append(JourneyLeg(tripID: leg.tripID, route: leg.route, headsign: leg.headsign,
                                       board: leg.alight, alight: leg.board, departure: flip(leg.arrival), arrival: flip(leg.departure),
                                       walk: reverseWalk(i == 0 ? journey.finalWalk : reverseLegs[i - 1].walk), live: leg.live,
                                       coordinates: leg.coordinates.reversed(), serviceDate: leg.serviceDate, scheduledDeparture: scheduled,
                                       shapeID: leg.shapeID, shapeStart: leg.shapeEnd, shapeEnd: leg.shapeStart, callingPoints: points, wheelchairAccessible: leg.wheelchairAccessible))
            }
            let result = Journey(legs: legs, finalWalk: reverseWalk(reverseLegs.last!.walk), requestedDeparture: earliestDeparture)
            guard result.arrival <= deadline, result.leave >= earliestDeparture else { return nil }
            return result
        }.sorted { $0.leave == $1.leave ? $0.walking < $1.walking : $0.leave > $1.leave }
    }

}
