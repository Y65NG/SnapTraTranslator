import XCTest
@testable import SnapTra_Translator

final class HotkeyManagerTests: XCTestCase {
    func testCommandHotkeyMatchesBothPhysicalCommandKeys() {
        XCTAssertTrue(SingleKeyMapping.matches(keyCode: 54, for: .command))
        XCTAssertTrue(SingleKeyMapping.matches(keyCode: 55, for: .command))
    }

    func testOptionHotkeyMatchesBothPhysicalOptionKeys() {
        XCTAssertTrue(SingleKeyMapping.matches(keyCode: 58, for: .option))
        XCTAssertTrue(SingleKeyMapping.matches(keyCode: 61, for: .option))
    }

    func testGenericModifierHotkeyRejectsDifferentModifierKeyCode() {
        XCTAssertFalse(SingleKeyMapping.matches(keyCode: 58, for: .command))
        XCTAssertFalse(SingleKeyMapping.matches(keyCode: 55, for: .option))
    }

    func testFirstPressTriggersImmediately() {
        var stateMachine = HotkeyGestureStateMachine()

        let events = stateMachine.handlePress(now: Date())

        XCTAssertEqual(events, [.trigger])
    }

    func testShortTapDelaysReleaseForDoubleTapWindow() {
        var stateMachine = HotkeyGestureStateMachine()
        let start = Date()

        _ = stateMachine.handlePress(now: start)
        let resolution = stateMachine.handleRelease(now: start.addingTimeInterval(0.08))

        XCTAssertEqual(resolution, .delayed(0.25))
    }

    func testSecondPressWithinWindowEmitsDoubleTapWithoutNewTrigger() {
        var stateMachine = HotkeyGestureStateMachine()
        let start = Date()

        _ = stateMachine.handlePress(now: start)
        _ = stateMachine.handleRelease(now: start.addingTimeInterval(0.08))
        let events = stateMachine.handlePress(now: start.addingTimeInterval(0.16))

        XCTAssertEqual(events, [.doubleTap])
    }

    func testExpiredTapWindowReleasesBeforeNextTrigger() {
        var stateMachine = HotkeyGestureStateMachine()
        let start = Date()

        _ = stateMachine.handlePress(now: start)
        _ = stateMachine.handleRelease(now: start.addingTimeInterval(0.08))
        let events = stateMachine.handlePress(now: start.addingTimeInterval(0.40))

        XCTAssertEqual(events, [.release, .trigger])
    }

    func testDoubleTapSecondReleaseIsImmediate() {
        var stateMachine = HotkeyGestureStateMachine()
        let start = Date()

        _ = stateMachine.handlePress(now: start)
        _ = stateMachine.handleRelease(now: start.addingTimeInterval(0.08))
        _ = stateMachine.handlePress(now: start.addingTimeInterval(0.16))
        let resolution = stateMachine.handleRelease(now: start.addingTimeInterval(0.24))

        XCTAssertEqual(resolution, .none)
    }
}
