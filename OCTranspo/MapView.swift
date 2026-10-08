import MapKit
import SwiftUI

struct MapTab: View {
    @State private var selected: MapTap?

    var body: some View {
        StopsMap(selection: $selected)
            .sheet(item: $selected) { tap in
                NavigationStack {
                    Group {
                        switch tap {
                        case .stop(let stop): StopView(stop: stop)
                        case .vehicle(let vehicle): TripView(tripID: vehicle.tripID)
                        }
                    }
                    .transitDestinations()
                }
                .presentationDetents([.medium, .large])
            }
    }
}

enum MapTap: Hashable, Identifiable {
    case stop(Stop)
    case vehicle(Vehicle)

    var id: String {
        switch self {
        case .stop(let stop): "stop-" + stop.code
        case .vehicle(let vehicle): "vehicle-" + vehicle.id
        }
    }
}

struct StopsMap: View {
    @Binding var selection: MapTap?
    @Environment(Transit.self) private var transit
    @Environment(Location.self) private var location
    @State private var journeySession = JourneySession.shared
    @State private var position = MapCameraPosition.region(.downtown)
    @State private var region: MKCoordinateRegion? = .downtown
    @State private var centred = false
    @State private var layer = Layer.all

    private let stopSpan = 0.008
    private let busSpan = 0.08
    private enum Layer: String, CaseIterable, Identifiable {
        case all = "All", stops = "Stops", vehicles = "Vehicles"
        var id: String { rawValue }
    }

    var body: some View {
        Map(position: $position, selection: $selection) {
            UserAnnotation { _ in
                Circle()
                    .fill(.blue)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(.white, lineWidth: 3))
                    .shadow(radius: 2)
            }
            ForEach(visibleStops) { stop in
                Annotation(stop.name, coordinate: stop.coordinate) {
                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(.red, lineWidth: 3))
                        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .annotationTitles(.hidden)
                .tag(MapTap.stop(stop))
            }
            ForEach(visibleVehicles) { vehicle in
                Annotation(transit.route(of: vehicle).name, coordinate: vehicle.coordinate) {
                    RouteBadge(route: transit.route(of: vehicle), small: true)
                        .shadow(radius: 2)
                }
                .annotationTitles(.hidden)
                .tag(MapTap.vehicle(vehicle))
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .onEnd) { region = $0.region }
        .onChange(of: location.inOttawa, initial: true) { _, inOttawa in
            guard inOttawa, !centred, let here = location.current else { return }
            position = .region(MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 1200, longitudinalMeters: 1200))
            centred = true
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Explore")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                HStack(spacing: 6) {
                    ForEach(Layer.allCases) { option in
                        Button(option.rawValue) { layer = option }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .foregroundStyle(layer == option ? Color.white : Color.primary)
                            .background(layer == option ? Color.accentColor : Color(.tertiarySystemGroupedBackground), in: Capsule())
                            .accessibilityAddTraits(layer == option ? .isSelected : [])
                    }
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .padding(.leading, 12)
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) {
            if !journeySession.isRunning {
                Label(mapHint, systemImage: mapHintSymbol)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
            }
        }
    }

    private var mapHint: String {
        if layer != .vehicles, let region, region.span.latitudeDelta >= stopSpan { return "Zoom in to show stops" }
        if layer == .vehicles { return visibleVehicles.isEmpty ? "No vehicles in this area" : "Tap a vehicle for trip details" }
        if layer == .stops { return visibleStops.isEmpty ? "No stops in this area" : "Tap a stop for departures" }
        return "Tap a stop or vehicle for details"
    }

    private var mapHintSymbol: String {
        if layer != .vehicles, let region, region.span.latitudeDelta >= stopSpan { return "plus.magnifyingglass" }
        if layer == .vehicles { return "bus" }
        if layer == .stops { return "mappin" }
        return "hand.tap"
    }

    private var visibleStops: [Stop] {
        guard layer != .vehicles, let region, region.span.latitudeDelta < stopSpan else { return [] }
        return Array(transit.schedule.stops.lazy.filter { region.contains($0.coordinate) }.prefix(200))
    }

    private var visibleVehicles: [Vehicle] {
        guard layer != .stops, let region, region.span.latitudeDelta < busSpan else { return [] }
        return Array(transit.vehicles.lazy
            .filter { region.contains($0.coordinate) && !transit.route(of: $0).name.isEmpty }
            .prefix(150))
    }
}

extension Stop {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension Vehicle {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension MKCoordinateRegion {
    static let downtown = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 45.4215, longitude: -75.6972),
                                             span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012))

    func contains(_ point: CLLocationCoordinate2D) -> Bool {
        abs(point.latitude - center.latitude) < span.latitudeDelta / 2
            && abs(point.longitude - center.longitude) < span.longitudeDelta / 2
    }
}
