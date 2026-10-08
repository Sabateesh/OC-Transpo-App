import Foundation

struct JourneyConnection {
    let nextLeg: Int
    let available: TimeInterval
    let walk: TimeInterval
    let spare: TimeInterval
    let usesPrediction: Bool
    var isMissed: Bool { spare < 0 }
    var isTight: Bool { spare >= 0 && spare < 180 }
    var summary: String {
        let minutes = max(0, Int(floor(spare / 60)))
        if isMissed { return "Connection may be missed" }
        if isTight { return "Tight connection · \(minutes) min spare" }
        return "\(minutes) min transfer cushion"
    }
    static func all(in journey: Journey) -> [Self] {
        zip(journey.legs, journey.legs.dropFirst()).enumerated().map { index, pair in
            let (previous, next) = pair
            let available = next.departure.timeIntervalSince(previous.arrival)
            let required = max(180, next.walk.duration + 120)
            return .init(nextLeg: index + 1, available: available, walk: next.walk.duration,
                         spare: available - required, usesPrediction: previous.live || next.live)
        }
    }
}
