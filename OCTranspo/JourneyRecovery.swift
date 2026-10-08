import CoreLocation
import Foundation

struct JourneyRecoveryContext {
    let origin: CLLocationCoordinate2D
    let departure: Date
    let retainedLeg: JourneyLeg?
    let label: String
    static func make(journey: Journey, progress: JourneyGuidanceProgress, location: CLLocation?, now: Date) -> Self? {
        guard progress.legIndex < journey.legs.count else { return nil }
        let leg = journey.legs[progress.legIndex]
        if progress.onBoard {
            return .init(origin: .init(latitude: leg.alight.latitude, longitude: leg.alight.longitude), departure: max(now, leg.arrival).addingTimeInterval(120), retainedLeg: leg, label: "After getting off at \(leg.alight.name)")
        }
        if let fix = JourneyGuidanceProgress.usable(location, now: now) {
            return .init(origin: fix.coordinate, departure: now, retainedLeg: nil, label: "From your current location")
        }
        return .init(origin: leg.walk.from, departure: now, retainedLeg: nil, label: "From your planned starting point")
    }
    func joining(_ candidate: Journey) -> Journey {
        guard let retainedLeg else { return candidate }
        return .init(legs: [retainedLeg] + candidate.legs, finalWalk: candidate.finalWalk, requestedDeparture: candidate.requestedDeparture)
    }
    func accepts(_ candidate: Journey, live: LiveTrips?, now: Date) -> Bool {
        var updated = candidate
        updated.legs = candidate.legs.map { $0.withPredictions(live) }
        guard !updated.legs.isEmpty, updated.cancellationNotices(in: live ?? LiveTrips(), now: now).isEmpty,
              updated.legs.allSatisfy({ !$0.skips($0.callingPoints.first, live: live) && !$0.skips($0.callingPoints.last, live: live) }) else { return false }
        for (previous, next) in zip(updated.legs, updated.legs.dropFirst()) {
            guard previous.arrival.addingTimeInterval(max(180, next.walk.duration + 120)) <= next.departure else { return false }
        }
        if let retainedLeg {
            guard updated.legs.count > 1, updated.legs[0].tripID == retainedLeg.tripID,
                  updated.legs[0].serviceDate == retainedLeg.serviceDate else { return false }
            let next = updated.legs[1]
            return next.departure >= max(now, retainedLeg.arrival).addingTimeInterval(max(180, next.walk.duration + 120))
        }
        return updated.canStart(at: now, live: live)
    }
}
