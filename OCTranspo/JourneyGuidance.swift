import CoreLocation
import Foundation

struct JourneyGuidanceProgress: Codable {
    var legIndex = 0
    var onBoard = false
    var finished = false
    var observedStop: Int? = nil
    var observedAt: Date? = nil
    mutating func board() { onBoard = true; observedStop = nil; observedAt = nil }
    mutating func alight() { legIndex += 1; onBoard = false; observedStop = nil; observedAt = nil }
    mutating func finish() { finished = true }

    func getOffHint(for leg: JourneyLeg, location: CLLocation?, now: Date) -> Bool {
        guard onBoard else { return false }
        if let location, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100,
           abs(location.timestamp.timeIntervalSince(now)) < 30, now > leg.departure.addingTimeInterval(60) {
            let target = CLLocation(latitude: leg.alight.latitude, longitude: leg.alight.longitude)
            if location.distance(from: target) < 180 { return true }
        }
        if let observedStop, let observedAt, now.timeIntervalSince(observedAt) < 120,
           leg.callingPoints.count - 1 - observedStop > 1 { return false }
        return leg.arrival.timeIntervalSince(now) <= 60 && leg.arrival.timeIntervalSince(now) > -120
    }
}

extension JourneyLeg {
    func withPredictions(_ live: LiveTrips?) -> JourneyLeg {
        guard let update = matchingUpdate(live) else { return self }
        var result = self
        let bySequence = Dictionary(update.stops.compactMap { point in point.sequence.map { ($0, point) } }, uniquingKeysWith: { _, last in last })
        func prediction(_ point: JourneyCallingPoint) -> StopTime? {
            bySequence[point.sequence] ?? update.stops.first { point.stop.ids.contains($0.stopID) }
        }
        var delay: TimeInterval = 0
        if let first = callingPoints.first, let value = prediction(first) { result.departure = value.time }
        result.callingPoints = callingPoints.map { point in
            if let value = prediction(point) {
                delay = (value.arrival ?? value.time).timeIntervalSince(point.time)
                result.live = true
            }
            return JourneyCallingPoint(stop: point.stop, time: point.time.addingTimeInterval(delay), sequence: point.sequence)
        }
        result.arrival = result.callingPoints.last?.time ?? arrival
        return result
    }

    func matchingUpdate(_ live: LiveTrips?) -> LiveTrips.Trip? {
        guard let update = live?.trips[tripID],
              update.serviceDate == serviceDate || (update.serviceDate == nil && serviceDate == RoutingTimetable.dayKey(.now)) else { return nil }
        return update
    }

    func skips(_ point: JourneyCallingPoint?, live: LiveTrips?) -> Bool {
        guard let point, let update = matchingUpdate(live) else { return false }
        return update.skippedSequences.contains(point.sequence) || point.stop.ids.contains { update.skippedStopIDs.contains($0) }
    }
}
