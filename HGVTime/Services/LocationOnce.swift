import CoreLocation
import Foundation

/// Gets a single location fix (for Arrived / Departed) and a readable place name.
@MainActor
final class LocationOnce: NSObject, CLLocationManagerDelegate {
    static let shared = LocationOnce()
    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func current() async -> CLLocation? {
        switch manager.authorizationStatus {
        case .denied, .restricted: return nil
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: break
        }
        // A recent fix is reused only if it's a proper GPS one (not a rough Wi-Fi / mast position).
        if let recent = manager.location, abs(recent.timestamp.timeIntervalSinceNow) < 60,
           recent.horizontalAccuracy >= 0, recent.horizontalAccuracy <= 100 { return recent }
        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
            manager.requestLocation()
            // Don't wait forever.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(12))
                self.finish(nil)
            }
        }
    }

    /// "Tesco DC, Daventry NN11 8XX" style name for a location.
    func placeName(for location: CLLocation) async -> String {
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        guard let p = placemark else { return String(format: "%.5f, %.5f", location.coordinate.latitude, location.coordinate.longitude) }
        return [p.name, p.locality, p.postalCode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private func finish(_ location: CLLocation?) {
        let list = waiting
        waiting = []
        list.forEach { $0.resume(returning: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.finish(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .authorizedWhenInUse || status == .authorizedAlways, !self.waiting.isEmpty {
                self.manager.requestLocation()
            } else if status == .denied || status == .restricted {
                self.finish(nil)
            }
        }
    }
}
