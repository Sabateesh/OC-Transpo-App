import Foundation

enum JourneyTimeMode: String, CaseIterable, Identifiable {
    case now = "Leave now", depart = "Depart at", arrive = "Arrive by"
    var id: String { rawValue }
}

enum JourneyRanking {
    static func labels(for journey: Journey, among choices: [Journey]) -> [String] {
        guard !choices.isEmpty else { return [] }
        var labels: [String] = []
        if journey.duration <= (choices.map(\.duration).min() ?? 0) + 1 { labels.append("Fastest") }
        if journey.walking <= (choices.map(\.walking).min() ?? 0) + 1 { labels.append("Less walking") }
        if journey.legs.count == choices.map({ $0.legs.count }).min() { labels.append("Fewer transfers") }
        return labels
    }

    static func countdown(_ departure: Date, now: Date) -> String {
        let remaining = departure.timeIntervalSince(now)
        if remaining < 0 { return "Departed" }
        if remaining < 60 { return "Due now" }
        return "Departs in \(Int(ceil(remaining / 60))) min"
    }

    static func distinctOptions(_ options: [Journey]) -> [Journey] {
        let winners = [options.first,
                       options.min { $0.duration < $1.duration },
                       options.min { $0.walking < $1.walking },
                       options.min { $0.legs.count == $1.legs.count ? $0.arrival < $1.arrival : $0.legs.count < $1.legs.count }].compactMap { $0 }
        var seen: Set<String> = [], selected: [Journey] = []
        for journey in winners + options {
            let signature = journey.legs.map { $0.route.name + ":" + $0.headsign }.joined(separator: ">")
            guard seen.insert(signature).inserted else { continue }
            selected.append(journey)
            if selected.count == 5 { break }
        }
        return selected
    }
}

extension Journey {
    func cancellationNotices(in live: LiveTrips, now: Date) -> [String] {
        legs.filter { live.isCanceled(tripID: $0.tripID, serviceDate: $0.serviceDate, now: now) }
            .map { "Route \($0.route.name) toward \($0.headsign) was cancelled. Other departures are shown below." }
    }
    func canStart(at now: Date, live: LiveTrips? = nil) -> Bool {
        leave >= now && (live.map { cancellationNotices(in: $0, now: now).isEmpty } ?? true)
    }
}

extension LiveTrips {
    func isCanceled(tripID: String, serviceDate: String, now: Date) -> Bool {
        guard let dates = canceledTripDates[tripID] else { return false }
        return dates.contains(serviceDate) || (dates.contains("") && serviceDate == RoutingTimetable.dayKey(now))
    }
}
