import XCTest
import AppKit
@testable import Emilia

final class VoiceGlowTests: XCTestCase {
    @MainActor func testRedTakesPrecedenceAndPauseRemovesGlow() {
        XCTAssertTrue(VoiceGlow.shouldShow(listening: true, synthetic: true, scamWarning: false))
        XCTAssertFalse(VoiceGlow.shouldShow(listening: true, synthetic: true, scamWarning: true))
        XCTAssertFalse(VoiceGlow.shouldShow(listening: false, synthetic: true, scamWarning: false))
        XCTAssertFalse(VoiceGlow.shouldShow(listening: true, synthetic: false, scamWarning: false))
    }
    @MainActor func testGlowCannotInterceptClicksOrKeyboardFocus() {
        _ = NSApplication.shared
        let window = VoiceGlow.makeWindow(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.isOpaque)
    }
}
