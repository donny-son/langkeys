import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let tapController = EventTapController()
    private var permissionTimer: Timer?
    private var selectionObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeft

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        selectionObserver = InputSourceManager.observeSelectionChange { [weak self] in
            self?.updateStatusTitle()
        }
        Preferences.shared.onChange = { [weak self] in self?.updateStatusTitle() }

        updateStatusTitle()
        startTapOrWaitForPermission()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tapController.stop()
        permissionTimer?.invalidate()
        if let selectionObserver {
            DistributedNotificationCenter.default().removeObserver(selectionObserver)
        }
    }

    // MARK: - Event tap lifecycle

    private func startTapOrWaitForPermission() {
        if tapController.start() {
            permissionTimer?.invalidate()
            permissionTimer = nil
            updateStatusTitle()
            return
        }
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) {
            [weak self] _ in
            self?.startTapOrWaitForPermission()
        }
    }

    private func requestAccessibilityPermission() {
        let options =
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(
            URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )!)
        startTapOrWaitForPermission()
    }

    // MARK: - Status item

    private func updateStatusTitle() {
        guard let button = statusItem.button else { return }
        let current = InputSourceManager.current()

        if let flag = current?.flag {
            button.image = nil
            // Emoji ignore the menu bar's tint, so size them explicitly and nudge the
            // baseline to sit centered like a template image would.
            button.attributedTitle = NSAttributedString(
                string: flag,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 15),
                    .baselineOffset: -1,
                ])
        } else if let badge = current?.badge {
            button.image = nil
            button.attributedTitle = NSAttributedString(
                string: badge, attributes: [.font: NSFont.systemFont(ofSize: 13)])
        } else {
            button.title = ""
            button.image = NSImage(
                systemSymbolName: "keyboard", accessibilityDescription: "LangKeys")
        }

        button.toolTip = current.map { "LangKeys — \($0.name)" } ?? "LangKeys"
        button.appearsDisabled = !AXIsProcessTrusted() || !Preferences.shared.isEnabled
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let sources = InputSourceManager.available()

        if !AXIsProcessTrusted() {
            let item = NSMenuItem(
                title: "⚠︎ Grant Accessibility Permission…",
                action: #selector(openAccessibilitySettings), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }

        if let current = InputSourceManager.current() {
            menu.addItem(disabledItem("Current: \(current.displayName)"))
            menu.addItem(.separator())
        }

        menu.addItem(disabledItem("Tap a key on its own to switch"))
        for key in ModifierKey.allCases {
            menu.addItem(mappingItem(for: key, sources: sources))
        }

        menu.addItem(.separator())

        let enabled = NSMenuItem(
            title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        enabled.state = Preferences.shared.isEnabled ? .on : .off
        menu.addItem(enabled)

        let login = NSMenuItem(
            title: "Open at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit LangKeys", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func mappingItem(for key: ModifierKey, sources: [InputSource]) -> NSMenuItem {
        let assignedID = Preferences.shared.inputSourceID(for: key)
        let assigned = sources.first { $0.id == assignedID }
        let item = NSMenuItem(title: key.title, action: nil, keyEquivalent: "")

        let submenu = NSMenu()
        let none = NSMenuItem(title: "None", action: #selector(assignSource(_:)), keyEquivalent: "")
        none.target = self
        none.representedObject = Assignment(key: key, sourceID: nil)
        none.state = assignedID == nil ? .on : .off
        submenu.addItem(none)
        submenu.addItem(.separator())

        for source in sources {
            let sourceItem = NSMenuItem(
                title: source.displayName, action: #selector(assignSource(_:)), keyEquivalent: "")
            sourceItem.target = self
            sourceItem.representedObject = Assignment(key: key, sourceID: source.id)
            sourceItem.state = source.id == assignedID ? .on : .off
            submenu.addItem(sourceItem)
        }

        // Show a stale mapping (source no longer enabled) rather than pretending it is unset.
        if let assignedID, assigned == nil {
            submenu.addItem(.separator())
            submenu.addItem(disabledItem("Unavailable: \(assignedID)"))
        }

        item.submenu = submenu
        item.attributedTitle = attributedMapping(
            key: key, value: assigned?.displayName ?? (assignedID == nil ? "—" : "unavailable"))
        return item
    }

    private func attributedMapping(key: ModifierKey, value: String) -> NSAttributedString {
        let text = NSMutableAttributedString(string: key.title + "  ")
        text.append(
            NSAttributedString(
                string: value,
                attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
        return text
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    private struct Assignment {
        let key: ModifierKey
        let sourceID: String?
    }

    @objc private func assignSource(_ sender: NSMenuItem) {
        guard let assignment = sender.representedObject as? Assignment else { return }
        Preferences.shared.setInputSource(assignment.sourceID, for: assignment.key)
    }

    @objc private func toggleEnabled() {
        Preferences.shared.isEnabled.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Could not change the login item"
            alert.runModal()
        }
    }

    @objc private func openAccessibilitySettings() {
        requestAccessibilityPermission()
    }
}
