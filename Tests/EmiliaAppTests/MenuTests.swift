import XCTest
import AppKit
@testable import Emilia

final class MenuTests: XCTestCase {
    @MainActor func testStatusItemHasVisibleTemplateIcon() throws {
        _ = NSApplication.shared
        let item = AppDelegate.makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        XCTAssertTrue(item.isVisible)
        XCTAssertEqual(item.length, NSStatusItem.squareLength)
        let image = try XCTUnwrap(item.button?.image)
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
    }
    @MainActor func testEditingShortcutsTargetTheResponderChain() throws {
        _ = NSApplication.shared
        let menu = ApplicationMenus.make()
        let edit = try XCTUnwrap(menu.items.first { $0.title == "Edit" }?.submenu)
        for (title, key, selector) in [("Paste", "v", "paste:"), ("Select All", "a", "selectAll:"), ("Copy", "c", "copy:"), ("Cut", "x", "cut:")] {
            let item = try XCTUnwrap(edit.items.first { $0.title == title })
            XCTAssertEqual(item.keyEquivalent, key)
            XCTAssertEqual(item.keyEquivalentModifierMask, .command)
            XCTAssertEqual(item.action, NSSelectorFromString(selector))
            XCTAssertNil(item.target)
        }
    }
}
