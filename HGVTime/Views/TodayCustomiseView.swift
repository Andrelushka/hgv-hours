import SwiftUI
import UIKit

/// Kept for older links: the Today layout screen.
struct TodayCustomiseView: View {
    var body: some View { TileCustomiseView(page: .today) }
}

enum ScreenAwake {
    /// Applies the keep-screen-on setting.
    @MainActor
    static func apply(_ settings: AppSettings, onShift: Bool) {
        let on: Bool
        switch settings.keepScreenOn {
        case "always": on = true
        case "shift": on = onShift
        default: on = false
        }
        UIApplication.shared.isIdleTimerDisabled = on
    }
}
