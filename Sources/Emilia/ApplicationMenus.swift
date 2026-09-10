import AppKit

/// Standard nil-target actions follow the responder chain to SwiftUI's native field editor.
@MainActor
enum ApplicationMenus {
    static func make() -> NSMenu {
        let main = NSMenu()
        let application = NSMenuItem()
        application.title = "Emilia"
        let appMenu = NSMenu(title: "Emilia")
        appMenu.addItem(withTitle: "About Emilia", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Emilia", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Emilia", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        application.submenu = appMenu; main.addItem(application)
        let editItem = NSMenuItem()
        editItem.title = "Edit"
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; main.addItem(editItem)
        let windowItem = NSMenuItem()
        windowItem.title = "Window"
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu; main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        return main
    }
}
