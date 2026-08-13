import AppKit
import SwiftUI

/// Borderless, non-activating panel that floats over the menu bar and the notch.
/// Settings mirror boring.notch's `BoringNotchWindow`.
private final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = .mainMenu + 3
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shows a flag sliding out of one side of the notch, then tucks it back in.
final class NotchHUD: ObservableObject {
    @Published private(set) var flag: String?
    @Published private(set) var side: NotchSide = .left
    @Published private(set) var isExpanded = false

    /// Asks for the flag that should be pinned right now, after the panel had to be rebuilt.
    var pinnedFlagProvider: (() -> (flag: String, side: NotchSide)?)?

    private var panel: NotchPanel?
    private var geometry: NotchGeometry?
    private var collapseWork: DispatchWorkItem?
    private var orderOutWork: DispatchWorkItem?

    init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func show(flag: String, on side: NotchSide) {
        let isFirstShow = panel == nil
        guard let panel = ensurePanel() else { return }

        collapseWork?.cancel()
        orderOutWork?.cancel()
        panel.orderFrontRegardless()

        let expand = { [weak self] in
            guard let self else { return }
            self.flag = flag
            self.side = side
            self.isExpanded = true
            self.scheduleCollapse()
        }

        // Swapping sides mid-flight would slide the body across the notch; tuck in first so
        // only one flag is ever out.
        if isExpanded && side != self.side {
            isExpanded = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: expand)
        } else if isFirstShow {
            // Let the hosting view lay out collapsed once, so the first flag animates too.
            self.flag = flag
            self.side = side
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: expand)
        } else {
            expand()
        }
    }

    private func scheduleCollapse() {
        collapseWork?.cancel()
        // Pinned mode: the flag is the user's indicator of the current input mode, so it
        // stays out until something replaces it.
        guard !Preferences.shared.flagStaysVisible else { return }

        let collapse = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isExpanded = false

            // Keep the panel around until the body has finished springing back, otherwise
            // the flag vanishes mid-animation.
            // The flag stays set: clearing it would tear the view out of the hierarchy and
            // break the slide-out on the next show.
            let orderOut = DispatchWorkItem { [weak self] in
                self?.panel?.orderOut(nil)
            }
            self.orderOutWork = orderOut
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: orderOut)
        }
        collapseWork = collapse
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Preferences.shared.flagDwellSeconds, execute: collapse)
    }

    /// Re-evaluates the timer after the dwell settings change: start tucking in a pinned flag
    /// that should no longer be pinned, or cancel a countdown that should now hold.
    func applyDwellSettings() {
        guard isExpanded else { return }
        scheduleCollapse()
    }

    func hideImmediately() {
        collapseWork?.cancel()
        orderOutWork?.cancel()
        isExpanded = false
        panel?.orderOut(nil)
    }

    // MARK: - Panel lifecycle

    private func ensurePanel() -> NotchPanel? {
        if let panel, geometry != nil { return panel }
        guard let geometry = NotchGeometry.current() else { return nil }

        let frame = NSRect(origin: geometry.panelOrigin, size: geometry.panelSize)
        let panel = NotchPanel(contentRect: frame)
        let host = NSHostingView(rootView: NotchHUDView(hud: self, geometry: geometry))
        host.frame = NSRect(origin: .zero, size: geometry.panelSize)
        panel.contentView = host
        panel.setFrame(frame, display: false)

        self.panel = panel
        self.geometry = geometry
        return panel
    }

    @objc private func screenParametersChanged() {
        // Notch metrics are per-display; rebuild rather than stretch the old panel.
        hideImmediately()
        panel?.close()
        panel = nil
        geometry = nil

        guard let pinned = pinnedFlagProvider?() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.show(flag: pinned.flag, on: pinned.side)
        }
    }
}
