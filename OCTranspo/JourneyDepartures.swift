import CoreLocation
import Foundation

struct JourneyDepartureOption: Identifiable {
    let journey: Journey
    let legIndex: Int
    let selected: Bool
    var leg: JourneyLeg { journey.legs[legIndex] }
    var id: String { leg.tripID + ":" + leg.serviceDate }
}

enum JourneyDepartures {
    static func options(for journey: Journey, legIndex: Int, network: RoutingNetwork,
                        live: LiveTrips?, now: Date = .now, accessibleVehiclesOnly: Bool = false) -> [JourneyDepartureOption] {
        guard journey.legs.indices.contains(legIndex) else { return [] }
        let original = journey.legs[legIndex]
        let earliest = legIndex == 0 ? max(now.addingTimeInterval(original.walk.duration + 30), original.departure.addingTimeInterval(-15 * 60))
            : journey.legs[legIndex - 1].arrival.addingTimeInterval(max(180, original.walk.duration + 120))
        let latest = max(original.departure.addingTimeInterval(90 * 60), earliest.addingTimeInterval(90 * 60))
        let replacements = candidates(for: original, from: earliest, through: latest, network: network,
                                      live: live, accessibleVehiclesOnly: accessibleVehiclesOnly)
        return replacements.compactMap { replacement in
            guard let result = replacing(journey, at: legIndex, with: replacement, network: network,
                                         live: live, accessibleVehiclesOnly: accessibleVehiclesOnly) else { return nil }
            return JourneyDepartureOption(journey: result, legIndex: legIndex,
                                          selected: replacement.tripID == original.tripID && replacement.serviceDate == original.serviceDate)
        }.prefix(8).map { $0 }
    }

    static func replacing(_ journey: Journey, at index: Int, with replacement: JourneyLeg,
                          network: RoutingNetwork, live: LiveTrips?, accessibleVehiclesOnly: Bool = false) -> Journey? {
        guard journey.legs.indices.contains(index), replacement.board.code == journey.legs[index].board.code,
              replacement.alight.code == journey.legs[index].alight.code else { return nil }
        var updated = journey
        updated.legs[index] = replacement
        if index > 0 {
            let previous = updated.legs[index - 1]
            guard previous.arrival.addingTimeInterval(max(180, replacement.walk.duration + 120)) <= replacement.departure else { return nil }
        }
        if index + 1 < updated.legs.count {
            for nextIndex in (index + 1)..<updated.legs.count {
                let old = updated.legs[nextIndex]
                let needed = updated.legs[nextIndex - 1].arrival.addingTimeInterval(max(180, old.walk.duration + 120))
                if old.departure >= needed, live?.isCanceled(tripID: old.tripID, serviceDate: old.serviceDate, now: needed) != true { continue }
                guard let next = candidates(for: old, from: needed, through: needed.addingTimeInterval(3 * 3600),
                                            network: network, live: live, accessibleVehiclesOnly: accessibleVehiclesOnly).first else { return nil }
                updated.legs[nextIndex] = next
            }
        }
        return updated
    }

    private static func candidates(for leg: JourneyLeg, from earliest: Date, through latest: Date,
                                   network: RoutingNetwork, live: LiveTrips?, accessibleVehiclesOnly: Bool) -> [JourneyLeg] {
        let table = network.timetable
        guard let boarding = table.stops.firstIndex(where: { $0.code == leg.board.code && $0.ids.contains(where: leg.board.ids.contains) }),
              let alighting = table.stops.firstIndex(where: { $0.code == leg.alight.code && $0.ids.contains(where: leg.alight.ids.contains) }) else { return [] }
        var values: [JourneyLeg] = []
        for departure in network.index.departures[boarding] where departure.time >= earliest.addingTimeInterval(-30 * 60) && departure.time <= latest.addingTimeInterval(30 * 60) {
            let scheduled = table.trips[departure.trip]
            guard Schedule.route(scheduled.routeID, in: table.routes).name == leg.route.name,
                  leg.headsign.isEmpty || scheduled.headsign == leg.headsign,
                  !accessibleVehiclesOnly || scheduled.wheelchairAccessible == WheelchairAccess.accessible else { continue }
            let single = RoutingTimetable(stops: table.stops, routes: table.routes, trips: [scheduled], day: table.day)
            guard let trip = JourneyPlanner.updatedTrips(single, live: live).first,
                  let boardIndex = trip.calls.firstIndex(where: { $0.stop == boarding && $0.pickup && $0.departure >= earliest && $0.departure <= latest }),
                  let alightIndex = trip.calls.indices.first(where: { $0 > boardIndex && trip.calls[$0].stop == alighting && trip.calls[$0].dropoff }),
                  !accessibleVehiclesOnly || table.stops[boarding].wheelchairBoarding != WheelchairAccess.inaccessible,
                  !accessibleVehiclesOnly || table.stops[alighting].wheelchairBoarding != WheelchairAccess.inaccessible else { continue }
            let board = trip.calls[boardIndex], alight = trip.calls[alightIndex]
            let calls = Array(trip.calls[boardIndex...alightIndex])
            let scheduledDeparture = (trip.scheduledCalls ?? trip.calls).first(where: { $0.sequence == board.sequence })?.departure
            let points: [JourneyCallingPoint] = calls.map { call in
                JourneyCallingPoint(stop: table.stops[call.stop], time: call.arrival, sequence: call.sequence)
            }
            let coordinates = calls.map { call in
                let stop = table.stops[call.stop]
                return CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)
            }
            let candidate = JourneyLeg(tripID: trip.id, route: Schedule.route(trip.routeID, in: table.routes),
                                       headsign: trip.headsign, board: table.stops[boarding], alight: table.stops[alighting],
                                       departure: board.departure, arrival: alight.arrival, walk: leg.walk, live: trip.live,
                                       coordinates: coordinates, serviceDate: trip.serviceDate,
                                       scheduledDeparture: scheduledDeparture, shapeID: trip.shapeID,
                                       shapeStart: board.shapeDistance, shapeEnd: alight.shapeDistance,
                                       callingPoints: points, wheelchairAccessible: trip.wheelchairAccessible)
            values.append(candidate)
        }
        var seen: Set<String> = []
        return values.sorted { $0.departure < $1.departure }.filter { seen.insert($0.tripID + ":" + $0.serviceDate).inserted }
    }
}
