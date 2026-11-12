import CoreLocation
import Observation

/// Position and heading for the truck marker on the map (only while the map is open).
@MainActor
@Observable
final class LiveLocation: NSObject, CLLocationManagerDelegate {
    var location: CLLocation?
    /// Direction the lorry points: GPS course when moving, otherwise the compass.
    var heading: CLLocationDirection = 0

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var filter = GPSFilter()

    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.headingFilter = 3
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            // Skip rough Wi-Fi / mobile-mast positions and impossible jumps.
            guard self.filter.accept(loc) else { return }
            self.location = loc
            if loc.course >= 0 && loc.speed > 2 { self.heading = loc.course }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            // The compass only counts when stopped or slow; GPS course is steadier on the move.
            if (self.location?.speed ?? 0) <= 2 { self.heading = h }
        }
    }
}
