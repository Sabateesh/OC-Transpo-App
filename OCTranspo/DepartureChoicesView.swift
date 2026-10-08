import SwiftUI

struct DepartureChoicesView: View {
    let journey: Journey
    let legIndex: Int
    let onChoose: (Journey) -> Void
    @Environment(Transit.self) private var transit
    @Environment(\.dismiss) private var dismiss
    @State private var options: [JourneyDepartureOption] = []
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let leg = journey.legs[legIndex]
                    HStack(spacing: 10) {
                        RouteBadge(route: leg.route)
                        VStack(alignment: .leading) {
                            Text("Toward \(leg.headsign)").font(.headline)
                            Text("\(leg.board.name) → \(leg.alight.name)").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Text("Choose a departure").font(.title3.bold())
                    if options.isEmpty, message == nil { ProgressView("Checking departures…") }
                    if let message { ContentUnavailableView("No other departures", systemImage: "bus", description: Text(message)) }
                    VStack(spacing: 10) {
                        ForEach(options) { option in
                            Button {
                                onChoose(option.journey)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .center, spacing: 14) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(option.leg.departure, style: .time)
                                                .font(.system(.title3, design: .rounded, weight: .bold))
                                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                                Text(JourneyRanking.countdown(option.leg.departure, now: context.date))
                                                    .font(.caption.weight(.semibold)).monospacedDigit()
                                                    .foregroundStyle(option.selected ? Color.secondary : Color.accentColor)
                                            }
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 4) {
                                            Text("Arrive \(option.journey.arrival.formatted(date: .omitted, time: .shortened))")
                                                .font(.subheadline)
                                            Label(option.selected ? "Selected" : "Choose", systemImage: option.selected ? "checkmark.circle.fill" : "arrow.right.circle")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(option.selected ? Color.green : Color.accentColor)
                                        }
                                    }
                                    if let tight = JourneyConnection.all(in: option.journey).first(where: { $0.isTight || $0.isMissed }) {
                                        Label(tight.summary, systemImage: "clock.badge.exclamationmark")
                                            .font(.caption).foregroundStyle(.orange)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(option.selected ? Color.accentColor : Color.clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(option.leg.departure.formatted(date: .omitted, time: .shortened)), arrive \(option.journey.arrival.formatted(date: .omitted, time: .shortened)), \(option.selected ? "selected" : "choose departure")")
                        }
                    }
                    Text("Transfer and arrival times update when you choose a bus.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Departures").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: journey.id + ":" + String(legIndex)) {
                while !Task.isCancelled {
                    await loadOptions()
                    try? await Task.sleep(for: .seconds(20))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    @MainActor private func loadOptions() async {
        do {
            let network = try await RoutingStore.shared.network(for: journey.legs[legIndex].departure)
            let live = transit.liveError == nil && transit.liveUpdated.map { Date.now.timeIntervalSince($0) < 120 } == true ? transit.live : nil
            let choices = await Task.detached(priority: .userInitiated) {
                JourneyDepartures.options(for: journey, legIndex: legIndex, network: network, live: live,
                                          accessibleVehiclesOnly: UserDefaults.standard.bool(forKey: "accessibleVehiclesOnly"))
            }.value
            guard !Task.isCancelled else { return }
            options = choices
            message = choices.isEmpty ? "No catchable departure on this line keeps your planned connections." : nil
        } catch { message = error.localizedDescription }
    }
}
