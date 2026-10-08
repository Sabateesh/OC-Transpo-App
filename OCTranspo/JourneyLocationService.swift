import CoreLocation
import Foundation

@MainActor
final class JourneyLocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    var onLocation: ((CLLocation) -> Void)?
    var onUnavailable: ((String?) -> Void)?
    private let manager = CLLocationManager()
    private var wanted = false
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 15
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
    }
    func start() {
        wanted = true
        manager.requestWhenInUseAuthorization()
        configure()
    }
    func stop() {
        wanted = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }
    private func configure() {
        guard wanted else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            manager.startUpdatingLocation()
            onUnavailable?(nil)
        case .denied, .restricted:
            manager.stopUpdatingLocation()
            onUnavailable?("Location is off. Background stop tracking needs location access in Settings.")
        default: break
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { configure() }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard wanted, let location = locations.last else { return }
        onLocation?(location)
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .denied { onUnavailable?("Location access is unavailable. Open Settings to resume background guidance.") }
    }
}
