import MapKit

enum WalkingResult {
    case route(JourneyWalk)
    case blocked
}

@MainActor
final class WalkingRoutes {
    static let shared = WalkingRoutes()
    private struct Key: Hashable {
        let fromLat: Double
        let fromLon: Double
        let toLat: Double
        let toLon: Double
        init(_ walk: JourneyWalk) {
            fromLat = walk.from.latitude; fromLon = walk.from.longitude
            toLat = walk.to.latitude; toLon = walk.to.longitude
        }
    }
    private var cache: [Key: (result: WalkingResult, saved: Date)] = [:]

    func check(_ walk: JourneyWalk) async throws -> WalkingResult {
        try Task.checkCancellation()
        let key = Key(walk)
        if let cached = cache[key], Date.now.timeIntervalSince(cached.saved) < 6 * 3600 {
            switch cached.result {
            case .blocked: return .blocked
            case .route(let route):
                var result = walk
                result.duration = route.duration; result.distance = route.distance
                result.verified = true; result.coordinates = route.coordinates; result.instructions = route.instructions
                return .route(result)
            }
        }
        if walk.distance < 25 {
            var result = walk
            result.verified = true
            return .route(result)
        }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: walk.from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: walk.to))
        request.transportType = .walking
        let directions = MKDirections(request: request)
        let timeout = Task { @MainActor in
            try await Task.sleep(for: .seconds(5))
            directions.cancel()
        }
        defer { timeout.cancel() }
        let result: WalkingResult
        do {
            let response = try await withTaskCancellationHandler {
                try await directions.calculate()
            } onCancel: { directions.cancel() }
            try Task.checkCancellation()
            if let route = response.routes.first {
                var verified = walk
                verified.duration = route.expectedTravelTime; verified.distance = route.distance
                verified.verified = true; verified.coordinates = route.polyline.routeCoordinates
                verified.instructions = route.steps.compactMap { step in
                    let text = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                    return text.isEmpty ? nil : WalkingInstruction(text: text, distance: step.distance)
                }
                result = .route(verified)
            } else { result = .blocked }
        } catch {
            try Task.checkCancellation()
            if (error as NSError).domain == MKErrorDomain,
               (error as NSError).code == MKError.directionsNotFound.rawValue { result = .blocked }
            else { return .route(walk) }
        }
        if cache.count >= 256, let oldest = cache.min(by: { $0.value.saved < $1.value.saved })?.key {
            cache.removeValue(forKey: oldest)
        }
        cache[key] = (result, .now)
        return result
    }
}

extension MKPolyline {
    var routeCoordinates: [CLLocationCoordinate2D] {
        var result = Array(repeating: CLLocationCoordinate2D(), count: pointCount)
        getCoordinates(&result, range: NSRange(location: 0, length: pointCount))
        return result
    }
}
