import Foundation

struct PredictionStatus {
    let hasPredictions: Bool
    let feedAvailable: Bool
    let updatedAt: Date?
    var predictionsAreCurrent = true
    var title: String {
        if hasPredictions { return feedAvailable && predictionsAreCurrent ? "Live predictions" : "Last known predictions · May have changed" }
        return "Scheduled times · Delays may change your trip"
    }
}
