import CoreLocation
import Foundation

struct JourneyCue: Equatable {
    enum Phase: String { case leave, walk, wait, ride, getOff, finalWalk, arrived }
    let phase: Phase
    let title: String
    let detail: String
    let symbol: String
    let count: Int?
    let estimated: Bool
}

extension JourneyGuidanceProgress {
    static func usable(_ location: CLLocation?, now: Date) -> CLLocation? {
        guard let location, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 65,
              abs(location.timestamp.timeIntervalSince(now)) < 30 else { return nil }
        return location
    }

    func cue(journey: Journey, destination: String, location: CLLocation?, now: Date) -> JourneyCue {
        if finished { return .init(phase: .arrived, title: "You've arrived", detail: destination, symbol: "flag.checkered", count: nil, estimated: false) }
        guard legIndex < journey.legs.count else {
            return .init(phase: .finalWalk, title: "Walk to your destination", detail: destination, symbol: "figure.walk", count: nil, estimated: false)
        }
        let leg = journey.legs[legIndex]
        let fix = Self.usable(location, now: now)
        if onBoard {
            let remaining = remainingStops(leg, now: now)
            let estimated = observedAt.map { now.timeIntervalSince($0) > 120 } ?? true
            if getOffHint(for: leg, location: fix, now: now) {
                return .init(phase: .getOff, title: "Get ready to get off", detail: leg.alight.name, symbol: "bell.fill", count: remaining, estimated: estimated)
            }
            return .init(phase: .ride, title: remaining == 1 ? "Your stop is next" : "\(remaining) stops to go", detail: leg.alight.name, symbol: "bus.fill", count: remaining, estimated: estimated)
        }
        let distance = fix.map { $0.distance(from: CLLocation(latitude: leg.board.latitude, longitude: leg.board.longitude)) }
        if let distance, distance < 90 {
            return .init(phase: .wait, title: "Wait for \(leg.route.name)", detail: "Toward \(leg.headsign)", symbol: "bus.fill", count: nil, estimated: false)
        }
        let leave = leg.departure.addingTimeInterval(-leg.walk.duration - 60)
        if legIndex == 0, leave.timeIntervalSince(now) > 60 {
            return .init(phase: .leave, title: "Leave in \(Int(ceil(leave.timeIntervalSince(now) / 60))) min", detail: "Walk to \(leg.board.name)", symbol: "clock.fill", count: nil, estimated: !leg.walk.verified)
        }
        return .init(phase: .walk, title: legIndex == 0 ? "Head to your stop" : "Make your transfer", detail: leg.board.name, symbol: "figure.walk", count: nil, estimated: !leg.walk.verified)
    }

    func remainingStops(_ leg: JourneyLeg, now: Date) -> Int {
        let timed = max(1, leg.callingPoints.dropFirst().filter { $0.time >= now }.count)
        if let observedStop {
            let knownRemaining = max(0, leg.callingPoints.count - 1 - observedStop)
            if let observedAt, now.timeIntervalSince(observedAt) <= 120 { return knownRemaining }
            return min(knownRemaining, timed)
        }
        return timed
    }

    mutating func observe(_ location: CLLocation, leg: JourneyLeg, now: Date) {
        guard onBoard, let fix = Self.usable(location, now: now), leg.callingPoints.count > 1 else { return }
        let lower = observedStop ?? 0
        let candidates = leg.callingPoints.enumerated().filter { index, point in
            index >= lower && (index <= lower + 1 || abs(point.time.timeIntervalSince(now)) < 180)
        }
        guard let nearest = candidates.min(by: {
            fix.distance(from: CLLocation(latitude: $0.element.stop.latitude, longitude: $0.element.stop.longitude)) <
            fix.distance(from: CLLocation(latitude: $1.element.stop.latitude, longitude: $1.element.stop.longitude))
        }), fix.distance(from: CLLocation(latitude: nearest.element.stop.latitude, longitude: nearest.element.stop.longitude)) < 90 else { return }
        observedStop = max(lower, nearest.offset); observedAt = now
    }
}

struct JourneyReminder: Equatable {
    let id: String
    let title: String
    let body: String
    let date: Date

    static func upcoming(journey: Journey, progress: JourneyGuidanceProgress, now: Date,
                         leaveLead: TimeInterval = 60, getOffLead: TimeInterval = 60,
                         transferLead: TimeInterval = 180) -> [JourneyReminder] {
        guard !progress.finished, progress.legIndex < journey.legs.count else { return [] }
        let leg = journey.legs[progress.legIndex]
        if progress.onBoard {
            let date = leg.arrival.addingTimeInterval(-getOffLead)
            let next = journey.legs.indices.contains(progress.legIndex + 1) ? journey.legs[progress.legIndex + 1] : nil
            let transferDate = leg.arrival.addingTimeInterval(-transferLead)
            var reminders: [JourneyReminder] = []
            if date > now {
                let transfer = next != nil && transferDate == date ? " Then head to \(next!.board.name) for route \(next!.route.name)." : " Check your journey for updates."
                reminders.append(.init(id: "get-off", title: "Your stop is coming up", body: "Route \(leg.route.name): expected at \(leg.alight.name).\(transfer)", date: date))
            }
            if let next {
                if transferDate > now, transferDate != date {
                    reminders.append(.init(id: "transfer", title: "Transfer coming up", body: "Get off at \(leg.alight.name), then head to \(next.board.name) for route \(next.route.name).", date: transferDate))
                }
            }
            return reminders.sorted { $0.date < $1.date }
        }
        let date = leg.departure.addingTimeInterval(-leg.walk.duration - leaveLead)
        guard date > now else { return [] }
        return [.init(id: "leave", title: "Time to head to your stop", body: "Walk to \(leg.board.name) for \(leg.route.name) toward \(leg.headsign). Based on the latest available departure.", date: date)]
    }
}
