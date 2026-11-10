import SwiftUI
import WidgetKit

@main
struct HGVTimeWidgetBundle: WidgetBundle {
    var body: some Widget {
        HGVStatusWidget()
        HGVCountdownWidget()
        HGVDashboardWidget()
        HGVLiveActivityWidget()
    }
}
