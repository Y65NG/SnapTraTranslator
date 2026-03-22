import AppKit
import XCTest
@testable import SnapTra_Translator

final class SmokeTests: XCTestCase {
    func testSmoke() {
        XCTAssertTrue(true)
    }

    @MainActor
    func testOverlayShowBringsVisibleWindowToFrontAgain() {
        let suiteName = "SmokeTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let model = AppModel(settings: SettingsStore(defaults: defaults, loginItemStatus: false))
        let panel = RecordingOverlayPanel(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let controller = OverlayWindowController(model: model, panel: panel)

        controller.show(at: CGPoint(x: 200, y: 200))
        controller.show(at: CGPoint(x: 240, y: 240))

        XCTAssertEqual(panel.orderFrontRegardlessCallCount, 2)
    }
}

private final class RecordingOverlayPanel: NSPanel {
    private(set) var orderFrontRegardlessCallCount = 0

    override func orderFrontRegardless() {
        orderFrontRegardlessCallCount += 1
        super.orderFrontRegardless()
    }
}
