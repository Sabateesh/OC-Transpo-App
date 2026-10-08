import MapKit

enum JourneyQuickStart {
    static func make(trip: LiveTrips.Trip, schedule: Schedule, alightCode: String,
                     boardingCode: String?, alreadyAboard: Bool, timetable: RoutingTimetable? = nil,
                     now: Date = .now) -> Journey? {
        let remaining = trip.stops.compactMap { visit -> (Stop, StopTime)? in
            guard visit.time > now.addingTimeInterval(-30), let stop = schedule.stop(id: visit.stopID) else { return nil }
            return (stop, visit)
        }
        let boardIndex: Int
        if alreadyAboard || boardingCode == nil {
            boardIndex = 0
        } else {
            guard let selected = remaining.firstIndex(where: { $0.0.code == boardingCode }) else { return nil }
            boardIndex = selected
        }
        guard remaining.indices.contains(boardIndex),
              let alightIndex = remaining.indices.first(where: { $0 > boardIndex && remaining[$0].0.code == alightCode }) else { return nil }
        let board = remaining[boardIndex].0, alight = remaining[alightIndex].0
        func coordinate(_ stop: Stop) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)
        }
        let points = Array(remaining[boardIndex...alightIndex])
        let scheduled = timetable?.trips.first { $0.id == trip.id && ($0.serviceDate == trip.serviceDate || trip.serviceDate == nil) }
        let startSequence = points.first?.1.sequence
        let endSequence = points.last?.1.sequence
        let shapeStart = scheduled?.calls.first(where: { $0.sequence == startSequence })?.shapeDistance
        let shapeEnd = scheduled?.calls.first(where: { $0.sequence == endSequence })?.shapeDistance
        let firstDeparture = alreadyAboard ? now : points[0].1.time
        let lastArrival = points.last?.1.arrival ?? points.last!.1.time
        guard lastArrival > now else { return nil }
        let walk = JourneyWalk(key: .init(from: -1, to: 0), from: coordinate(board), to: coordinate(board),
                               duration: 0, distance: 0, verified: true)
        let finalWalk = JourneyWalk(key: .init(from: alightIndex, to: -2), from: coordinate(alight),
                                    to: coordinate(alight), duration: 0, distance: 0, verified: true)
        let calls = points.enumerated().map { index, point in
            JourneyCallingPoint(stop: point.0, time: point.1.arrival ?? point.1.time, sequence: point.1.sequence ?? index)
        }
        let leg = JourneyLeg(tripID: trip.id, route: schedule.route(trip.routeID),
                             headsign: schedule.headsigns[trip.id] ?? alight.name, board: board, alight: alight,
                             departure: firstDeparture, arrival: lastArrival, walk: walk, live: true,
                             coordinates: points.map { coordinate($0.0) },
                             serviceDate: trip.serviceDate ?? RoutingTimetable.dayKey(now),
                             scheduledDeparture: scheduled?.calls.first(where: { $0.sequence == startSequence })?.departure,
                             shapeID: scheduled?.shapeID, shapeStart: shapeStart, shapeEnd: shapeEnd,
                             callingPoints: calls, wheelchairAccessible: scheduled?.wheelchairAccessible)
        return Journey(legs: [leg], finalWalk: finalWalk, requestedDeparture: now)
    }
}
