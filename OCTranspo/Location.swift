import CoreLocation
import Observation

@MainActor @Observable
final class Location: NSObject, @preconcurrency CLLocationManagerDelegate {
    enum Status: Equatable {
        case locating, ready, denied, restricted, unavailable
        var message: String {
            switch self {
            case .locating: return "Finding your location…"
            case .ready: return "Location found"
            case .denied: return "Location access is off. Enable it in Settings or choose a starting address."
            case .restricted: return "Location access is restricted on this device. Choose a starting address."
            case .unavailable: return "Your location is unavailable. Try again or choose a starting address."
            }
        }
    }
    private(set) var current: CLLocation?
    private(set) var status: Status = .locating
    @ObservationIgnored private let manager: CLLocationManager
    @ObservationIgnored private let timeoutSeconds: Double
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private var requesting = false

    init(manager: CLLocationManager = CLLocationManager(), timeoutSeconds: Double = 15) {
        self.manager = manager; self.timeoutSeconds = timeoutSeconds
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    var inOttawa: Bool {
        guard let c = current?.coordinate else { return false }
        return (44.9...45.7).contains(c.latitude) && (-76.4 ... -75.2).contains(c.longitude)
    }
    func update() async { request(force: false) }
    func retry() { request(force: true) }
    private func request(force: Bool) {
        if !force, requesting { return }
        if !force, status == .ready, let current, abs(current.timestamp.timeIntervalSinceNow) < 300 { return }
        current = nil
        switch manager.authorizationStatus {
        case .denied: stop(.denied)
        case .restricted: stop(.restricted)
        case .notDetermined:
            status = .locating
            manager.requestWhenInUseAuthorization()
        default:
            status = .locating; requesting = true
            manager.startUpdatingLocation()
            timeout?.cancel()
            timeout = Task { [weak self, timeoutSeconds] in
                do { try await Task.sleep(for: .seconds(timeoutSeconds)) } catch { return }
                self?.stop(.unavailable)
            }
        }
    }
    private func stop(_ value: Status) {
        status = value; requesting = false
        timeout?.cancel(); timeout = nil
        manager.stopUpdatingLocation()
        if value != .ready { current = nil }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        request(force: true)
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard requesting, let fix = locations.last,
              fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 150,
              abs(fix.timestamp.timeIntervalSinceNow) < 30 else { return }
        current = fix; stop(.ready)
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard requesting else { return }
        if (error as? CLError)?.code == .locationUnknown { return }
        stop((error as? CLError)?.code == .denied ? .denied : .unavailable)
    }
}
