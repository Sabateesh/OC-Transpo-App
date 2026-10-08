import SwiftUI

struct AlertsTab: View {
    @Environment(Transit.self) private var transit
    @State private var query = ""
    @State private var pinnedOnly = false

    private var shownAlerts: [ServiceAlert] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return transit.alerts.filter { alert in
            if pinnedOnly && alert.routes.isDisjoint(with: transit.pinnedRoutes) { return false }
            guard !term.isEmpty else { return true }
            return ([alert.title, alert.category] + Array(alert.routes) + Array(alert.stops))
                .contains { $0.localizedCaseInsensitiveContains(term) }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("\(shownAlerts.count) \(shownAlerts.count == 1 ? "alert" : "alerts")")
                            .font(.headline)
                        Spacer()
                        if let updated = transit.alertsUpdated {
                            Text("Checked \(updated.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 8) {
                        filterButton("All alerts", selected: !pinnedOnly) { pinnedOnly = false }
                        filterButton("Pinned routes", selected: pinnedOnly) { pinnedOnly = true }
                    }
                    if transit.alertsFailed && !transit.alerts.isEmpty {
                        Label("Showing saved alerts. Pull down to retry.", systemImage: "wifi.slash")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)

                List(shownAlerts) { alert in
                    AlertRow(alert: alert)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .searchable(text: $query, prompt: "Route, stop, or alert")
                .refreshable { await transit.loadAlerts(force: true) }
                .overlay { if shownAlerts.isEmpty { emptyState } }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Service alerts")
        }
    }

    private func filterButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Color.accentColor : Color(.secondarySystemGroupedBackground), in: Capsule())
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var emptyState: some View {
        if transit.alertsFailed && transit.alerts.isEmpty {
            ContentUnavailableView("Couldn't load alerts", systemImage: "wifi.slash",
                                   description: Text("Pull down to try again."))
        } else if transit.alertsUpdated == nil && transit.alerts.isEmpty {
            ProgressView("Checking alerts…")
        } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView.search(text: query)
        } else if pinnedOnly {
            ContentUnavailableView("No alerts for pinned routes", systemImage: "pin",
                                   description: Text(transit.pinnedRoutes.isEmpty ? "Pin a route from Home to follow its alerts here." : "There are no published alerts for your pinned routes."))
        } else {
            ContentUnavailableView("No service alerts", systemImage: "checkmark.circle",
                                   description: Text("There are no published alerts to show right now."))
        }
    }
}

struct AlertRow: View {
    let alert: ServiceAlert
    var compact = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { openURL(alert.link) } label: {
            if compact {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(alert.title).font(.subheadline).foregroundStyle(.primary)
                        HStack(spacing: 6) {
                            if let date = alert.date { Text(date, format: .relative(presentation: .named)) }
                            if !alert.category.isEmpty { Text(alert.category) }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .frame(width: 36, height: 36)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 7) {
                    Text(alert.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                    HStack(spacing: 6) {
                        if !alert.category.isEmpty { Text(alert.category) }
                        if let date = alert.date {
                            if !alert.category.isEmpty { Text("·") }
                            Text("Published \(date.formatted(.dateTime.month(.abbreviated).day()))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if !alert.routes.isEmpty {
                        Text("Routes " + alert.routes.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: ", "))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else if !alert.stops.isEmpty {
                        Text("Stops " + alert.stops.sorted().joined(separator: ", "))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct JourneyAlertsView: View {
    let journey: Journey
    var startingAt = 0
    @State private var transit = Transit.shared
    var body: some View {
        let alerts = transit.alerts(for: journey, startingAt: startingAt)
        if !alerts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Alerts relevant to this trip", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold()).foregroundStyle(.orange)
                ForEach(alerts) { alert in
                    VStack(alignment: .leading, spacing: 8) {
                        if alert.match(journey, startingAt: startingAt) == .possible {
                            Text("Possible · Confirm dates, stops or direction").font(.caption.bold()).foregroundStyle(.secondary)
                        }
                        AlertRow(alert: alert, compact: true)
                        if let closed = alert.closedStops, !closed.isEmpty {
                            Text("Published stop closures: " + closed.sorted().joined(separator: ", "))
                                .font(.caption).foregroundStyle(.orange)
                        }
                        if let alternatives = alert.alternativeStops, !alternatives.isEmpty {
                            Text("Alternative stops: " + alternatives.sorted().joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let map = alert.publishedMap {
                            DisclosureGroup("Published detour map") {
                                if ["png", "jpg", "jpeg"].contains(map.pathExtension.lowercased()) {
                                    AsyncImage(url: map) { image in
                                        image.resizable().scaledToFit().accessibilityLabel("Official OC Transpo detour map")
                                    } placeholder: { ProgressView("Loading the published map…") }
                                }
                                Link("Open full map", destination: map)
                            }.font(.caption.weight(.semibold))
                        }
                    }
                }
                if transit.alertsFailed || transit.alertsUpdated.map({ Date.now.timeIntervalSince($0) > 600 }) == true {
                    Text("Saved alerts · Check details for current conditions").font(.caption).foregroundStyle(.secondary)
                }
                if let date = transit.alertsUpdated {
                    Text("Alerts checked \(date, style: .relative) ago").font(.caption).foregroundStyle(.secondary)
                }
            }.padding().background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        } else if transit.alertsFailed {
            Label("Service alerts unavailable", systemImage: "wifi.slash").font(.caption).foregroundStyle(.secondary)
        }
    }
}
