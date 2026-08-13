import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let tapController = EventTapController()
    private let notchHUD = NotchHUD()
    private let settingsController = SettingsWindowController()
    private var permissionTimer: Timer?
    private var selectionObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeft

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        settingsController.onOpenAccessibilitySettings = { [weak self] in
            self?.requestAccessibilityPermission()
        }

        tapController.onSwitch = { [weak self] key, sourceID in
            self?.presentNotchHUD(for: key, sourceID: sourceID)
        }

        // A pinned flag has to survive a display change, which forces the panel to be rebuilt.
        notchHUD.pinnedFlagProvider = { [weak self] in
            guard Preferences.shared.showsNotchHUD, Preferences.shared.flagStaysVisible else {
                return nil
            }
            return self?.currentFlagAndSide()
        }

        selectionObserver = InputSourceManager.observeSelectionChange { [weak self] in
            self?.updateStatusTitle()
            self?.pinCurrentFlagIfNeeded()
        }
        Preferences.shared.onChange = { [weak self] in self?.applyPreferences() }

        applyPreferences()
        startTapOrWaitForPermission()
        pinCurrentFlagIfNeeded()
        Updater.shared.start()

        // With no menu bar icon there is nothing to click, so open settings on launch.
        if !Preferences.shared.showsMenuBarIcon {
            settingsController.show()
        }

        // Developer aid: `LangKeys --preview-notch` plays the animation without needing a
        // real keystroke (or Accessibility permission).
        if CommandLine.arguments.contains("--preview-notch") {
            let sources = InputSourceManager.available()
            let flags = sources.compactMap(\.flag)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.notchHUD.show(flag: flags.first ?? "🇺🇸", on: .left)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
                self?.notchHUD.show(flag: flags.dropFirst().first ?? "🇰🇷", on: .right)
            }
        }
    }

    /// Clicking the app in Spotlight, Finder, or the Dock while it is already running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        settingsController.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        tapController.stop()
        Updater.shared.stop()
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

    // MARK: - Notch HUD

    private func presentNotchHUD(for key: ModifierKey, sourceID: String) {
        guard Preferences.shared.showsNotchHUD else { return }
        // The switch has just landed, so the current source is the one we want a flag for.
        let source =
            InputSourceManager.current().flatMap { $0.id == sourceID ? $0 : nil }
            ?? InputSourceManager.available().first { $0.id == sourceID }
        guard let flag = source?.flag ?? source?.badge else { return }
        notchHUD.show(flag: flag, on: Preferences.shared.notchSide(for: key))
    }

    /// The flag for whatever input source is active now, and the side it belongs on.
    private func currentFlagAndSide() -> (flag: String, side: NotchSide)? {
        guard let source = InputSourceManager.current() else { return nil }
        guard let flag = source.flag ?? source.badge as String? else { return nil }
        return (flag, Preferences.shared.notchSide(forSourceID: source.id))
    }

    /// In pinned mode the notch mirrors the input source however it was changed — a key tap,
    /// the input menu, or another app.
    private func pinCurrentFlagIfNeeded() {
        guard Preferences.shared.showsNotchHUD, Preferences.shared.flagStaysVisible,
            let pinned = currentFlagAndSide()
        else { return }
        notchHUD.show(flag: pinned.flag, on: pinned.side)
    }

    /// Pushes preference changes into the pieces that cannot observe them directly.
    private func applyPreferences() {
        updateStatusTitle()
        statusItem.isVisible = Preferences.shared.showsMenuBarIcon

        if Preferences.shared.showsNotchHUD {
            notchHUD.applyDwellSettings()
            pinCurrentFlagIfNeeded()
        } else {
            notchHUD.hideImmediately()
        }
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

        let hud = NSMenuItem(
            title: "Show Flag in Notch", action: #selector(toggleNotchHUD), keyEquivalent: "")
        hud.target = self
        hud.state = Preferences.shared.showsNotchHUD ? .on : .off
        menu.addItem(hud)

        let login = NSMenuItem(
            title: "Open at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let updates = NSMenuItem(
            title: Updater.shared.isBusy ? "Checking for Updates…" : "Check for Updates…",
            action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        updates.isEnabled = !Updater.shared.isBusy
        menu.addItem(updates)

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

        submenu.addItem(.separator())
        submenu.addItem(disabledItem("Flag appears at"))
        let currentSide = Preferences.shared.notchSide(for: key)
        for side in [NotchSide.left, .right] {
            let sideItem = NSMenuItem(
                title: side == .left ? "Left of Notch" : "Right of Notch",
                action: #selector(assignSide(_:)), keyEquivalent: "")
            sideItem.target = self
            sideItem.representedObject = SideChoice(key: key, side: side)
            sideItem.state = side == currentSide ? .on : .off
            submenu.addItem(sideItem)
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

    private struct SideChoice {
        let key: ModifierKey
        let side: NotchSide
    }

    @objc private func assignSource(_ sender: NSMenuItem) {
        guard let assignment = sender.representedObject as? Assignment else { return }
        Preferences.shared.setInputSource(assignment.sourceID, for: assignment.key)
    }

    @objc private func assignSide(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? SideChoice else { return }
        Preferences.shared.setNotchSide(choice.side, for: choice.key)
        // Show the result straight away so the choice is obvious.
        if let sourceID = Preferences.shared.inputSourceID(for: choice.key),
            let source = InputSourceManager.available().first(where: { $0.id == sourceID }),
            let flag = source.flag ?? source.badge as String?
        {
            notchHUD.show(flag: flag, on: choice.side)
        }
    }

    @objc private func toggleEnabled() {
        Preferences.shared.isEnabled.toggle()
    }

    @objc private func toggleNotchHUD() {
        Preferences.shared.showsNotchHUD.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    @objc private func openSettings() {
        settingsController.show()
    }

    @MainActor @objc private func checkForUpdates() {
        Updater.shared.checkNow()
    }

    @objc private func openAccessibilitySettings() {
        requestAccessibilityPermission()
    }
}
