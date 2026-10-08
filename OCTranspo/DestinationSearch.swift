import MapKit
import Observation

struct Destination: Identifiable {
    let id = UUID()
    let item: MKMapItem
    var title: String { item.name ?? "Destination" }
    var subtitle: String { item.placemark.title ?? "" }
}

struct PlaceSuggestion: Identifiable {
    let title: String
    let subtitle: String
    let completion: MKLocalSearchCompletion?
    let destination: Destination?
    var id: String { title + "|" + subtitle }
}

@MainActor @Observable
final class DestinationSearch: NSObject, @preconcurrency MKLocalSearchCompleterDelegate {
    private(set) var suggestions: [PlaceSuggestion] = []
    private(set) var recent: [PlaceSuggestion] = []
    private(set) var loading = false
    private(set) var resolving = false
    var error: String?
    @ObservationIgnored private var completer: MKLocalSearchCompleter?
    @ObservationIgnored private var activeSearch: MKLocalSearch?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var query = ""
    @ObservationIgnored private var acceptsCompletions = false
    @ObservationIgnored private var pendingQuery: Task<Void, Never>?
    @ObservationIgnored private var cache: [String: [PlaceSuggestion]] = [:]
    @ObservationIgnored private var cacheOrder: [String] = []
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let saved: SavedDestinations
    @ObservationIgnored private var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 45.35, longitude: -75.75),
                                                                 latitudinalMeters: 65_000, longitudinalMeters: 65_000)

    private struct SavedPlace: Codable {
        let title: String
        let subtitle: String
        let latitude: Double
        let longitude: Double
    }

    init(defaults: UserDefaults = .standard, saved: SavedDestinations? = nil) {
        self.defaults = defaults
        self.saved = saved ?? .shared
        super.init()
        let completer = MKLocalSearchCompleter()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        self.completer = completer
        reloadRecent()
    }

    private var cacheKey: String { "\(Int(region.center.latitude * 50)):\(Int(region.center.longitude * 50)):\(query.lowercased())" }
    private func localMatches(_ text: String) -> [PlaceSuggestion] {
        reloadRecent()
        let shortcuts = SavedDestinations.Slot.allCases.compactMap { slot -> PlaceSuggestion? in
            guard let place = saved.place(slot) else { return nil }
            return .init(title: place.title, subtitle: "\(slot.rawValue) · \(place.address)", completion: nil, destination: place.destination)
        }
        let terms = text.lowercased().split(whereSeparator: { $0.isWhitespace })
        return (shortcuts + recent).filter { suggestion in
            let label = (suggestion.title + " " + suggestion.subtitle).lowercased()
            return terms.allSatisfy { label.contains($0) }
        }
    }
    private func merged(_ lists: [PlaceSuggestion]...) -> [PlaceSuggestion] {
        var seen: Set<String> = []
        return lists.flatMap { $0 }.filter { seen.insert($0.title.lowercased() + "|" + ($0.destination?.item.placemark.coordinate.latitude.description ?? $0.subtitle.lowercased())).inserted }.prefix(12).map { $0 }
    }
    func update(_ text: String, near location: CLLocation?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        query = trimmed
        generation = UUID()
        acceptsCompletions = !trimmed.isEmpty
        activeSearch?.cancel()
        resolving = false
        pendingQuery?.cancel()
        error = nil
        if let location, (44.9...45.7).contains(location.coordinate.latitude), (-76.4 ... -75.2).contains(location.coordinate.longitude) { region.center = location.coordinate }
        guard !trimmed.isEmpty else {
            completer?.cancel()
            suggestions = []
            loading = false
            reloadRecent()
            return
        }
        let matching = suggestions.filter { ($0.title + " " + $0.subtitle).localizedCaseInsensitiveContains(trimmed) }
        suggestions = merged(localMatches(trimmed), cache[cacheKey] ?? [], matching)
        loading = true
        let token = generation
        pendingQuery = Task {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard generation == token, !Task.isCancelled else { return }
            completer?.region = region
            completer?.queryFragment = trimmed
        }
    }
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard acceptsCompletions, self.completer === completer, !query.isEmpty, completer.queryFragment == query, !completer.isSearching else { return }
        let results = completer.results.prefix(12).map { PlaceSuggestion(title: $0.title, subtitle: $0.subtitle, completion: $0, destination: nil) }
        cache[cacheKey] = results
        cacheOrder.removeAll { $0 == cacheKey }
        cacheOrder.append(cacheKey)
        if cacheOrder.count > 40 { cache.removeValue(forKey: cacheOrder.removeFirst()) }
        suggestions = merged(localMatches(query), results)
        loading = false
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        guard acceptsCompletions, self.completer === completer, !query.isEmpty, completer.queryFragment == query else { return }
        loading = false
        self.error = "Suggestions are unavailable. Tap Search to look up the full address."
    }

    func resolve(_ suggestion: PlaceSuggestion) async -> Destination? {
        acceptsCompletions = false
        pendingQuery?.cancel()
        completer?.cancel()
        if let destination = suggestion.destination {
            remember(destination)
            return destination
        }
        guard let completion = suggestion.completion else { return nil }
        return await find(MKLocalSearch.Request(completion: completion))
    }

    func submit() async {
        guard !query.isEmpty else { return }
        acceptsCompletions = false
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        request.resultTypes = [.address, .pointOfInterest]
        let token = UUID()
        generation = token
        completer?.cancel()
        pendingQuery?.cancel()
        activeSearch?.cancel()
        let search = MKLocalSearch(request: request)
        activeSearch = search
        loading = true
        error = nil
        do {
            let response = try await search.start()
            guard generation == token else { return }
            suggestions = response.mapItems.map {
                let destination = Destination(item: $0)
                return PlaceSuggestion(title: destination.title, subtitle: destination.subtitle, completion: nil, destination: destination)
            }
        } catch {
            if generation == token { self.error = "Couldn't search places. Check your connection and try again." }
        }
        if generation == token { loading = false }
    }

    private func find(_ request: MKLocalSearch.Request) async -> Destination? {
        let token = UUID()
        generation = token
        activeSearch?.cancel()
        request.region = region
        let search = MKLocalSearch(request: request)
        activeSearch = search
        resolving = true
        error = nil
        defer { if generation == token { resolving = false } }
        do {
            let response = try await search.start()
            guard generation == token, !Task.isCancelled else { return nil }
            guard let item = response.mapItems.first else {
                error = "Couldn't locate that address. Try including its street number or city."
                return nil
            }
            let result = Destination(item: item)
            remember(result)
            return result
        } catch {
            if generation == token { self.error = "Couldn't open that place. Check your connection and try again." }
            return nil
        }
    }

    func remember(_ destination: Destination) {
        var saved = savedPlaces()
        let c = destination.item.placemark.coordinate
        saved.removeAll { $0.title == destination.title && abs($0.latitude - c.latitude) < 0.0001 && abs($0.longitude - c.longitude) < 0.0001 }
        saved.insert(SavedPlace(title: destination.title, subtitle: destination.subtitle, latitude: c.latitude, longitude: c.longitude), at: 0)
        defaults.set(try? JSONEncoder().encode(Array(saved.prefix(8))), forKey: "recentDestinations")
        reloadRecent()
    }

    private func savedPlaces() -> [SavedPlace] {
        guard let data = defaults.data(forKey: "recentDestinations") else { return [] }
        return (try? JSONDecoder().decode([SavedPlace].self, from: data)) ?? []
    }

    private func reloadRecent() {
        recent = savedPlaces().map {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)))
            item.name = $0.title
            return PlaceSuggestion(title: $0.title, subtitle: $0.subtitle, completion: nil, destination: Destination(item: item))
        }
    }
}
