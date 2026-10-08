import SwiftUI

struct PlaceSearchResults: View {
    let search: DestinationSearch
    let query: String
    let select: (Destination) -> Void

    var body: some View {
        let places = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? search.recent : search.suggestions
        if search.resolving { ProgressView("Opening place…") }
        if let error = search.error { Text(error).font(.subheadline).foregroundStyle(.secondary) }
        if search.loading && places.isEmpty { ProgressView("Finding places…") }
        if !places.isEmpty {
            Section(query.isEmpty ? "Recent destinations" : "Places & addresses") {
                ForEach(places) { place in
                    Button {
                        Task { if let destination = await search.resolve(place) { select(destination) } }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: query.isEmpty ? "clock.arrow.circlepath" : "mappin.circle.fill")
                                .font(.title2).foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(place.title).foregroundStyle(.primary).fontWeight(.medium)
                                Text(place.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(search.resolving)
                    .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        } else if !search.loading && !search.resolving && search.error == nil {
            ContentUnavailableView(query.isEmpty ? "Where to?" : "No suggestions yet",
                                   systemImage: "magnifyingglass",
                                   description: Text(query.isEmpty ? "Search a place, street address, or neighbourhood." : "Try a street name or place, or tap Search for more results."))
        }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Button("Search for “\(query)”", systemImage: "magnifyingglass") { Task { await search.submit() } }
                .disabled(search.resolving)
        }
    }
}

struct PlacePicker: View {
    let title: String
    var allowCurrentLocation = false
    let select: (Destination?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(Location.self) private var location
    @State private var query = ""
    @State private var search = DestinationSearch()

    var body: some View {
        NavigationStack {
            List {
                if allowCurrentLocation {
                    Button("Current location", systemImage: "location.fill") { select(nil); dismiss() }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                PlaceSearchResults(search: search, query: query) { destination in select(destination); dismiss() }
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .searchable(text: $query, prompt: "Place or street address")
            .onChange(of: query) { _, value in search.update(value, near: location.current) }
            .onSubmit(of: .search) { Task { await search.submit() } }
            .navigationTitle(title)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
