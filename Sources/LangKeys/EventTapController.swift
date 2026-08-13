import AppKit
import CoreGraphics

/// Watches for a modifier key that is pressed and released on its own — no other key in
/// between — and switches the input source that the user mapped to it.
final class EventTapController {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var pendingKey: ModifierKey?
    private var pendingWasUsedInCombo = false

    /// Called on the main queue after a lone tap has selected an input source.
    var onSwitch: ((ModifierKey, String) -> Void)?

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard AXIsProcessTrusted() else { return false }

        let mask =
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<EventTapController>.fromOpaque(refcon)
                .takeUnretainedValue()
            controller.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: CGEventMask(mask),
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        resetPending()
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // The system disables a slow tap; re-arm it instead of silently dying.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        switch type {
        case .flagsChanged:
            handleFlagsChanged(event)
        default:
            // Any real keystroke or click means the held modifier was part of a combo.
            pendingWasUsedInCombo = true
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard let key = ModifierKey.from(keyCode: keyCode) else {
            pendingWasUsedInCombo = true
            return
        }

        if key.isHeld(in: event.flags) {
            // Press: a second modifier going down invalidates the first.
            if pendingKey != nil && pendingKey != key {
                pendingWasUsedInCombo = true
                pendingKey = nil
                return
            }
            pendingKey = key
            pendingWasUsedInCombo = false
        } else {
            let wasLoneTap = pendingKey == key && !pendingWasUsedInCombo
            resetPending()
            guard wasLoneTap, Preferences.shared.isEnabled,
                let sourceID = Preferences.shared.inputSourceID(for: key)
            else { return }
            DispatchQueue.main.async { [weak self] in
                InputSourceManager.select(id: sourceID)
                self?.onSwitch?(key, sourceID)
            }
        }
    }

    private func resetPending() {
        pendingKey = nil
        pendingWasUsedInCombo = false
    }
}
