import SwiftData
import SwiftUI
import XCTest
@testable import HGVTime

/// Renders screens to PNG for a visual check (only when HGV_RENDER_DIR is set).
@MainActor
final class RenderSnapshotTests: XCTestCase {
    func testRenderAssistantAndReset() throws {
        let dir = "/private/tmp/claude-501/-Users-andreikotlyarenko-Documents-Claude/a2d682c6-7bd3-43da-8611-9075333fc8d8/scratchpad/render"
        guard FileManager.default.fileExists(atPath: dir) else {
            throw XCTSkip("Set HGV_RENDER_DIR to render")
        }
        let container = try ModelContainer(for: StoreSetup.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = SettingsStore(defaults: UserDefaults(suiteName: "render")!)
        store.settings.driverName = "Andrei K"
        let screens: [(String, AnyView)] = [
            ("assistant", AnyView(NavigationStack { AssistantView() })),
            ("reset", AnyView(NavigationStack { ResetView() })),
            ("calculator", AnyView(NavigationStack { CalculatorView() })),
        ]
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        for (name, view) in screens {
            let host = UIHostingController(rootView: view.environment(store).modelContainer(container))
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            window.rootViewController = host
            window.makeKeyAndVisible()
            // Let SwiftUI lay out and animate in.
            RunLoop.main.run(until: Date().addingTimeInterval(1.5))
            let img = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try XCTUnwrap(img.pngData()).write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
            window.isHidden = true
        }
    }
}
