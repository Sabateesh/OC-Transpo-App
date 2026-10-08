import SwiftUI

struct StopView: View {
    let stop: Stop
    @Environment(Transit.self) private var transit
    @State private var routeFilter: String?

    var body: some View {
        let upcoming = transit.upcoming(at: stop)
        let routes = Set(upcoming.map(\.route)).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let filter = routes.count > 3 ? routeFilter : nil
        let shown = upcoming.filter { filter == nil || $0.route.name == filter }
        let alerts = transit.alerts(for: stop, routes: Set(routes.map(\.name)))

        List {
            if !alerts.isEmpty {
                Section {
                    ForEach(alerts) { alert in
                        AlertRow(alert: alert, compact: true)
                            .padding(12)
                            .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
                            .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            if routes.count > 3 {
                RouteFilter(routes: routes, selection: $routeFilter)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section {
                ForEach(shown) { line in
                    NavigationLink(value: TripRef(id: line.tripIDs[0], boardingStopCode: stop.code)) {
                        UpcomingRow(item: line)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .overlay {
            if upcoming.isEmpty {
                if transit.liveUpdated == nil && transit.liveError == nil {
                    ProgressView()
                } else if let error = transit.liveError {
                    ContentUnavailableView("No times", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    ContentUnavailableView("Nothing coming up",
                                           systemImage: "bus",
                                           description: Text("No buses or trains are reporting for this stop right now."))
                }
            }
        }
        .navigationTitle(stop.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(stop.name).font(.headline)
                    Text("Stop \(stop.code)").font(.caption).foregroundStyle(.secondary)
                }
            }
            ToolbarItem {
                Button {
                    transit.toggleFavourite(stop)
                } label: {
                    Label("Favourite", systemImage: transit.isFavourite(stop) ? "star.fill" : "star")
                }
            }
        }
        .refreshable { await transit.refreshLive() }
    }
}

struct RouteFilter: View {
    let routes: [Route]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button("All") { selection = nil }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.bordered)
                    .tint(selection == nil ? .accentColor : .secondary)
                ForEach(routes, id: \.self) { route in
                    Button {
                        selection = selection == route.name ? nil : route.name
                    } label: {
                        RouteBadge(route: route, small: true)
                    }
                    .buttonStyle(.plain)
                    .opacity(selection == nil || selection == route.name ? 1 : 0.35)
                }
            }
        }
    }
}

struct UpcomingRow: View {
    let item: Upcoming

    var body: some View {
        HStack(spacing: 12) {
            RouteBadge(route: item.route)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.headsign.isEmpty ? "Route \(item.route.name)" : item.headsign)
                    .fontWeight(.medium)
                if item.times.count > 1 {
                    Text("then " + item.times.dropFirst().prefix(2).map { arrivalLabel($0) }.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                if item.live {
                    Image(systemName: "dot.radiowaves.up.forward")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .accessibilityLabel("Live")
                }
                Text(arrivalLabel(item.times[0]))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }
}
