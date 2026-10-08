import SwiftUI

struct PredictionStatusView: View {
    let status: PredictionStatus
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(status.title, systemImage: status.feedAvailable ? "clock" : "wifi.slash")
            if let date = status.updatedAt {
                Text("Live feed last received \(date, style: .relative) ago · \(date, style: .time)")
            } else { Text("No live predictions received yet") }
            if !status.feedAvailable { Text("Live updates unavailable. Saved trip details remain available.") }
        }.font(.caption).foregroundStyle(.secondary).accessibilityElement(children: .combine)
    }
}

struct WalkingInstructionsView: View {
    let walk: JourneyWalk
    var saved = true
    var body: some View {
        if !walk.instructions.isEmpty {
            DisclosureGroup(saved ? "Walking directions · Saved for offline use" : "Walking directions") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(walk.instructions.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top) {
                            Text("\(index + 1).").monospacedDigit()
                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.text)
                                if step.distance > 0 { Text("\(Int(step.distance.rounded())) m").foregroundStyle(.secondary) }
                            }
                        }
                    }
                }.font(.subheadline).padding(.top, 8)
            }.font(.subheadline)
        } else {
            Text(walk.distance < 25 ? "A short walk connects these points." : "Written walking directions aren't saved yet. The map shows the available path.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
