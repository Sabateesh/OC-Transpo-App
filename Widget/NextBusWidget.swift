import SwiftUI
import WidgetKit

@main
struct OCTranspoWidgets: WidgetBundle {
    var body: some Widget { NextBusWidget(); JourneyLiveActivity() }
}

struct NextBusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextBus", provider: NextBusProvider()) { entry in
            NextBusView(entry: entry)
        }
        .configurationDisplayName("Next Bus")
        .description("Live times for your favourite stops. Reorder favourites in the app to pick which show first.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct NextBusEntry: TimelineEntry {
    let date: Date
    var stops: [WidgetStop] = []
    var message: String?
}

struct WidgetStop: Identifiable {
    let title: String
    let stop: Stop
    let lines: [Upcoming]
    var id: String { stop.code }
}

struct NextBusProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextBusEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (NextBusEntry) -> Void) {
        if context.isPreview {
            completion(.sample)
        } else {
            Task { completion(await Self.load()) }
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextBusEntry>) -> Void) {
        Task {
            let entry = await Self.load()
            let entries = (0..<15).map { minute in
                NextBusEntry(date: entry.date.addingTimeInterval(Double(minute) * 60), stops: entry.stops, message: entry.message)
            }
            completion(Timeline(entries: entries, policy: .after(entry.date.addingTimeInterval(15 * 60))))
        }
    }

    static func load() async -> NextBusEntry {
        let pinned = Array(AppGroup.pinnedStops.prefix(4))
        guard !pinned.isEmpty else {
            return NextBusEntry(date: .now, message: "Star a stop in the app and it'll show up here.")
        }
        do {
            let ids = Set(pinned.flatMap(\.stop.ids))
            let live = LiveTrips(try await Feed.download(Feed.tripUpdates), only: ids)
            let summary = TransitFeedStore.cachedSummary()
            let routes = summary?.routes ?? [:]
            let headsigns = summary?.headsigns ?? [:]

            let stops = pinned.map { pin in
                WidgetStop(title: pin.title, stop: pin.stop,
                           lines: live.upcoming(at: pin.stop.ids,
                                                route: { Schedule.route($0, in: routes) },
                                                headsign: { headsigns[$0] }))
            }
            return NextBusEntry(date: .now, stops: stops)
        } catch {
            return NextBusEntry(date: .now, message: error.localizedDescription)
        }
    }
}

struct NextBusView: View {
    let entry: NextBusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let message = entry.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(entry.stops.prefix(stopLimit)) { stop in
                        Link(destination: URL(string: "octranspo://stop/\(stop.stop.code)")!) {
                            StopBlock(stop: stop, now: entry.date, lineLimit: lineLimit, showHeadsign: family != .systemSmall)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .widgetURL(entry.stops.first.flatMap { URL(string: "octranspo://stop/\($0.stop.code)") })
        .containerBackground(.background, for: .widget)
    }

    private var stopLimit: Int {
        switch family {
        case .systemSmall: 1
        case .systemMedium: 2
        default: 4
        }
    }

    private var lineLimit: Int {
        family == .systemMedium ? 2 : 3
    }
}

private struct StopBlock: View {
    struct Line: Identifiable {
        let upcoming: Upcoming
        let next: Date
        var id: String { upcoming.id }
    }

    let stop: WidgetStop
    let now: Date
    let lineLimit: Int
    let showHeadsign: Bool

    var body: some View {
        let lines = stop.lines.compactMap { line in
            line.times.first { $0 > now.addingTimeInterval(-10) }.map { Line(upcoming: line, next: $0) }
        }

        VStack(alignment: .leading, spacing: 4) {
            Text(stop.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if lines.isEmpty {
                Text("Nothing coming up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(lines.prefix(lineLimit)) { line in
                HStack(spacing: 6) {
                    RouteBadge(route: line.upcoming.route, small: true)
                    if showHeadsign {
                        Text(line.upcoming.headsign)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(arrivalLabel(line.next, now: now))
                        .font(.caption.weight(.semibold).monospacedDigit())
                }
            }
        }
    }
}

extension NextBusEntry {
    static var sample: NextBusEntry {
        let route = Route(name: "95", color: "0057B8", textColor: "FFFFFF")
        let stop = Stop(code: "3017", name: "Baseline", latitude: 45.3474, longitude: -75.7617)
        let line = Upcoming(route: route, headsign: "Barrhaven Centre", times: [.now + 240, .now + 1_140])
        return NextBusEntry(date: .now, stops: [WidgetStop(title: "Baseline", stop: stop, lines: [line])])
    }
}
