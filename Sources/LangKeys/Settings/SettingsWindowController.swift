import AppKit
import SwiftUI

/// Owns the single settings window. It is the only UI the app has when the menu bar icon is
/// hidden, so it is also reachable by launching the app again from Spotlight or Finder.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    var onOpenAccessibilitySettings: () -> Void = {}

    func show() {
        if window == nil { window = makeWindow() }
        guard let window else { return }

        // An accessory app is not active by default; without this the window opens behind
        // whatever the user was using.
        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let view = SettingsView(
            onOpenAccessibilitySettings: { [weak self] in self?.onOpenAccessibilitySettings() },
            onQuit: { NSApp.terminate(nil) })

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "LangKeys"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        // Drop back to accessory behavior so closing settings does not leave the app focused.
        NSApp.hide(nil)
    }
}
