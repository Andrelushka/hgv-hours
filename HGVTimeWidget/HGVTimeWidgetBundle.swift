import SwiftUI
import WidgetKit

@main
struct HGVTimeWidgetBundle: WidgetBundle {
    var body: some Widget {
        HGVStatusWidget()
        HGVCountdownWidget()
        HGVDashboardWidget()
        HGVLiveActivityWidget()
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { AlarmLiveActivity() }
        #endif
    }
}
