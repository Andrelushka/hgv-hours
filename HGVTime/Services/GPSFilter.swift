import CoreLocation
import Foundation

/// Throws away GPS fixes that would make the marker jump: rough Wi-Fi / mobile-mast positions (poor accuracy)
/// and impossible jumps (faster than any lorry could go). The first fix is always kept so the map isn't empty.
struct GPSFilter {
    /// Worst accuracy accepted once we've had a good fix (metres).
    var maxAccuracy: CLLocationAccuracy = 65
    /// Faster than this between two fixes is a glitch (m/s ≈ 200 km/h).
    var maxSpeed: CLLocationSpeed = 55
    private(set) var last: CLLocation?

    /// true = use this fix.
    mutating func accept(_ loc: CLLocation) -> Bool {
        guard loc.horizontalAccuracy >= 0 else { return false }
        guard let prev = last else {
            last = loc
            return true
        }
        let age = loc.timestamp.timeIntervalSince(prev.timestamp)
        // Older than what we have: ignore.
        if age < 0 { return false }
        let goodRecently = prev.horizontalAccuracy <= maxAccuracy && age < 60
        if loc.horizontalAccuracy > maxAccuracy && goodRecently { return false }
        if age > 0 && age < 60 {
            let jump = loc.distance(from: prev)
            let allowance = loc.horizontalAccuracy + prev.horizontalAccuracy
            if jump > allowance && (jump - allowance) / age > maxSpeed { return false }
        }
        last = loc
        return true
    }

    mutating func reset() { last = nil }
}
