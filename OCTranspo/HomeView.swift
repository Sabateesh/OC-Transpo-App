import CoreLocation
import MapKit
import SwiftUI

struct HomeTab: View {
    @Binding var path: NavigationPath
    @Environment(Transit.self) private var transit
    @Environment(Location.self) private var location
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var saved = SavedDestinations.shared
    @State private var savingSlot: SavedDestinations.Slot?
    @State private var query = ""
    @State private var destinationSearch = DestinationSearch()
    @State private var selectedDestination: Destination?
    @FocusState private var searching: Bool
    @State private var renaming: Favourite?
    @State private var newName = ""
    @State private var choosingOrigin = false
    @State private var startingPoint: Destination?
    @State private var showingAbout = false

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    if !searching && query.isEmpty {
                        HStack {
                            Text("Plan a trip")
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
                            Button {
                                showingAbout = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("About and privacy")
                        }
                    }
                    searchField
                    if !searching && query.isEmpty {
                        destinationShortcuts
                        if let startingPoint {
                            Button("Starting from \(startingPoint.title)") { choosingOrigin = true }
                                .font(.caption.weight(.medium))
                        }
                        if location.status != .ready {
                            LocationRecoveryView { choosingOrigin = true }
                        }
                        if let through = transit.scheduleValidThrough,
                           through < PreparedTransitFeed.dayKey(Date.now.addingTimeInterval(14 * 86400)) {
                            TimetableCoverageView(through: through) { Task { await transit.loadSchedule(force: true) } }
                        }
                        if location.status == .ready && !dynamicTypeSize.isAccessibilitySize {
                            HomeMap()
                                .frame(height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .accessibilityLabel("Map of your nearby area")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)

                List {
                    if searching || !query.isEmpty {
                        searchResults
                    } else {
                        nearYouSection
                        favouritesSection
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.top, 0, for: .scrollContent)
                .scrollDismissesKeyboard(.immediately)
                .overlay { if query.isEmpty && !searching { loadingOverlay } }
            }
            .background(Color(.systemGroupedBackground))
            .animation(.easeInOut(duration: 0.25), value: searching || !query.isEmpty)
            .toolbar(.hidden, for: .navigationBar)
            .transitDestinations()
            .alert("Name this stop", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Home, Work…", text: $newName)
                Button("Save") {
                    if let renaming { transit.rename(renaming, to: newName) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .task { await location.update() }
            .onChange(of: query) { _, value in destinationSearch.update(value, near: location.current) }
            .sheet(item: $savingSlot) { slot in
                PlacePicker(title: "Set \(slot.rawValue)") { place in
                    if let place { saved.save(place, as: slot) }
                }
            }
            .sheet(isPresented: $choosingOrigin) {
                PlacePicker(title: "Starting address", allowCurrentLocation: true) { place in
                    startingPoint = place
                    if place == nil { location.retry() }
                }
            }
            .sheet(item: $selectedDestination) { destination in
                DestinationView(destination: destination, startingPoint: startingPoint)
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
        }
    }

    private var destinationShortcuts: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            ForEach(SavedDestinations.Slot.allCases) { slot in
                Button {
                    if let place = saved.place(slot) { searching = false; selectedDestination = place.destination }
                    else { savingSlot = slot }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: slot.symbol)
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 32, height: 32)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(slot.rawValue).font(.subheadline.weight(.semibold))
                            Text(saved.place(slot)?.destination.title ?? "Add address")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Change \(slot.rawValue)") { savingSlot = slot }
                    if saved.place(slot) != nil { Button("Remove", role: .destructive) { saved.remove(slot) } }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search a place or address", text: $query)
                .focused($searching)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { Task { await destinationSearch.submit() } }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 52)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.06)))
    }

    @ViewBuilder private var nearYouSection: some View {
        let lines = nearbyLines()
        let pinned = lines.filter { transit.pinnedRoutes.contains($0.upcoming.route.name) }
        let others = lines.filter { !transit.pinnedRoutes.contains($0.upcoming.route.name) }

        if !pinned.isEmpty {
            Section("Pinned lines") {
                ForEach(pinned) { line in
                    NearbyLineRow(line: line) { tripID in
                        path.append(TripRef(id: tripID, boardingStopCode: line.stop.code))
                    }
                    .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        Section("Near you") {
            if lines.isEmpty {
                Text(nearYouMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(others) { line in
                NearbyLineRow(line: line) { tripID in
                    path.append(TripRef(id: tripID, boardingStopCode: line.stop.code))
                }
                .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }

    private var nearYouMessage: String {
        if location.current == nil { return location.status.message }
        if !location.inOttawa { return "You're not in Ottawa right now. Search for a destination to plan a trip." }
        if transit.liveUpdated == nil { return transit.liveError ?? "Getting live times…" }
        return "Nothing's coming near you right now."
    }

    @ViewBuilder private var favouritesSection: some View {
        if !transit.favourites.isEmpty {
            Section {
                ForEach(transit.favourites, id: \.code) { favourite in
                    if let stop = transit.schedule.stop(code: favourite.code) {
                        NavigationLink(value: stop) {
                            StopRow(title: transit.title(for: favourite),
                                    subtitle: favourite.nickname == nil ? stop.code : "\(stop.name) · \(stop.code)",
                                    upcoming: transit.upcoming(at: stop))
                        }
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions {
                            Button("Remove", role: .destructive) { transit.toggleFavourite(stop) }
                            Button("Rename") {
                                newName = favourite.nickname ?? ""
                                renaming = favourite
                            }
                            .tint(.indigo)
                        }
                    } else {
                        Text("Stop \(favourite.code)").foregroundStyle(.secondary)
                    }
                }
                .onMove { transit.favourites.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { transit.favourites.remove(atOffsets: $0) }
            } header: {
                HStack {
                    Text("Favourites")
                    Spacer()
                    EditButton()
                        .font(.subheadline)
                        .textCase(nil)
                }
            }
        }
    }

    private var searchResults: some View {
        PlaceSearchResults(search: destinationSearch, query: query) { destination in
            searching = false
            selectedDestination = destination
        }
    }

    @ViewBuilder private var loadingOverlay: some View {
        if transit.schedule.stops.isEmpty {
            if let error = transit.loadError {
                ContentUnavailableView {
                    Label("Couldn't get the stop list", systemImage: "wifi.slash")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await transit.loadSchedule() } }
                }
            } else {
                ProgressView("Downloading stops…")
            }
        }
    }

    private func nearbyStops() -> [NearbyStop] {
        guard let here = location.current else { return [] }
        let close = transit.schedule.stops
            .map { NearbyStop(stop: $0, distance: here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))) }
            .filter { $0.distance < 800 }
            .sorted { $0.distance < $1.distance }
        return Array(close.prefix(20))
    }

    private func nearbyLines() -> [NearbyLine] {
        var closest: [String: NearbyLine] = [:]
        for item in nearbyStops() {
            for upcoming in transit.upcoming(at: item.stop) where closest[upcoming.id] == nil {
                closest[upcoming.id] = NearbyLine(upcoming: upcoming, stop: item.stop, distance: item.distance)
            }
        }
        return closest.values.sorted { ($0.distance, $0.upcoming.times[0]) < ($1.distance, $1.upcoming.times[0]) }
    }
}

private struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Plan trips and follow OC Transpo service using public transit data. This independent app is not affiliated with OC Transpo or the City of Ottawa.")
                }
                Section("Information") {
                    Link("Privacy Policy", destination: URL(string: "https://github.com/Sabateesh/OC-Transpo-App/blob/main/docs/PRIVACY.md")!)
                    Link("Support", destination: URL(string: "https://github.com/Sabateesh/OC-Transpo-App/issues")!)
                }
                Section {
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct HomeMap: View {
    @Environment(Location.self) private var location
    @State private var position = MapCameraPosition.region(.downtown)

    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            UserAnnotation { _ in
                Circle()
                    .fill(.blue)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(.white, lineWidth: 3))
                    .shadow(radius: 2)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .onChange(of: location.inOttawa, initial: true) { _, inOttawa in
            if inOttawa { position = .userLocation(fallback: .region(.downtown)) }
        }
    }
}

private struct NearbyStop {
    let stop: Stop
    let distance: CLLocationDistance
}

struct NearbyLine: Identifiable {
    let upcoming: Upcoming
    let stop: Stop
    let distance: CLLocationDistance

    var id: String { upcoming.id }
}

struct NearbyLineRow: View {
    let line: NearbyLine
    let choose: (String) -> Void
    @Environment(Transit.self) private var transit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RouteBadge(route: line.upcoming.route)
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.upcoming.headsign.isEmpty ? "Route \(line.upcoming.route.name)" : line.upcoming.headsign)
                        .fontWeight(.semibold).lineLimit(1)
                    Text("\(line.stop.name) · \(Measurement(value: line.distance, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    transit.togglePinnedRoute(line.upcoming.route.name)
                } label: {
                    Image(systemName: transit.pinnedRoutes.contains(line.upcoming.route.name) ? "pin.fill" : "pin")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(transit.pinnedRoutes.contains(line.upcoming.route.name) ? Color.accentColor : Color.secondary)
                .accessibilityLabel(transit.pinnedRoutes.contains(line.upcoming.route.name) ? "Unpin route \(line.upcoming.route.name)" : "Pin route \(line.upcoming.route.name)")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(line.upcoming.tripIDs.prefix(4).enumerated()), id: \.offset) { index, tripID in
                        Button { choose(tripID) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(arrivalLabel(line.upcoming.times[index])).font(.headline).monospacedDigit()
                                Text(transit.live.trips[tripID]?.vehicleID != nil ? "Live" : "Predicted")
                                    .font(.caption2).foregroundStyle(.secondary)
                                if let crowding = transit.crowding(for: tripID) {
                                    Text(crowding).font(.caption2).foregroundStyle(.secondary)
                                }
                            }.frame(minWidth: 92, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 10)
                                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct StopRow: View {
    let title: String
    let subtitle: String
    var distance: CLLocationDistance?
    var upcoming: [Upcoming] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let distance {
                    Text(Measurement(value: distance, unit: UnitLength.meters),
                         format: .measurement(width: .abbreviated, usage: .road))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if !upcoming.isEmpty {
                HStack(spacing: 12) {
                    ForEach(upcoming.prefix(3)) { line in
                        HStack(spacing: 4) {
                            RouteBadge(route: line.route, small: true)
                            Text(arrivalLabel(line.times[0]))
                                .font(.subheadline.monospacedDigit())
                        }
                    }
                }
            }
        }
    }
}
