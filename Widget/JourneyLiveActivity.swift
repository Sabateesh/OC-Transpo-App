import ActivityKit
import SwiftUI
import WidgetKit

struct JourneyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JourneyActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(context.state.route.isEmpty ? "Your journey" : "Route \(context.state.route)", systemImage: context.state.symbol).font(.headline)
                    Spacer()
                    Text(context.state.arrival, style: .time).monospacedDigit()
                }
                Text(context.state.title).font(.title3.bold())
                Text(context.state.detail).font(.subheadline).lineLimit(2)
                journeyAction(context)
                HStack {
                    Text(context.attributes.destination).lineLimit(1)
                    Spacer()
                    if context.isStale { Text("Open for updates").fontWeight(.semibold) }
                    else if let departure = context.state.departure, departure > .now {
                        Text(timerInterval: Date.now...departure, countsDown: true).monospacedDigit().frame(maxWidth: 80)
                    }
                }.font(.caption).foregroundStyle(Color.secondary)
            }.padding().activityBackgroundTint(context.state.urgent ? Color.orange.opacity(0.18) : Color(.systemBackground))
                .activitySystemActionForegroundColor(.primary)
                .widgetURL(URL(string: "octranspo://journey"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label(context.state.route, systemImage: context.state.symbol).font(.headline) }
                DynamicIslandExpandedRegion(.trailing) { Text(context.state.arrival, style: .time).font(.headline).monospacedDigit() }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(context.state.title).font(.headline)
                        Text(context.state.detail).font(.caption).lineLimit(2)
                        journeyAction(context)
                        if context.isStale { Text("Open for updates").font(.caption).foregroundStyle(Color.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Label(context.state.route, systemImage: context.state.symbol).font(.caption.bold())
            } compactTrailing: {
                if context.isStale { Image(systemName: "arrow.clockwise") }
                else if let stops = context.state.stopsRemaining { Text("\(stops)").monospacedDigit() }
                else { Text(context.state.arrival, style: .time).font(.caption2) }
            } minimal: {
                Image(systemName: context.state.symbol)
            }.widgetURL(URL(string: "octranspo://journey")).keylineTint(context.state.urgent ? .orange : .red)
        }
    }
    @ViewBuilder private func journeyAction(_ context: ActivityViewContext<JourneyActivityAttributes>) -> some View {
        if let index = context.state.legIndex, let token = context.state.actionToken, let onBoard = context.state.onBoard {
            Button(intent: JourneyActionIntent(sessionID: context.attributes.sessionID, legIndex: index, actionToken: token, alighting: onBoard)) {
                Label(onBoard ? "I got off" : "I'm on board", systemImage: onBoard ? "figure.walk" : "checkmark")
                    .font(.subheadline.bold())
            }.buttonStyle(.borderedProminent).tint(.red)
                .disabled(context.isStale || (!onBoard && context.state.canBoard != true))
        }
    }
}
