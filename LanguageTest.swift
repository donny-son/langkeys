import Foundation
import Carbon
import CoreGraphics

// MARK: - 1. Language Switcher
func switchLanguage(to targetID: String) {
    let filter = [kTISPropertyInputSourceID! as String: targetID] as CFDictionary
    guard let cfSources = TISCreateInputSourceList(filter, false),
          let sources = cfSources.takeRetainedValue() as? [TISInputSource],
          let targetSource = sources.first else { return }
    
    TISSelectInputSource(targetSource)
    print("Switched language to: \(targetID)")
}

// MARK: - 2. State Machine Variables
var activeModifierKeyCode: Int64? = nil
var modifierUsedWithOtherKey = false

// MARK: - 3. Keystroke Listener (Event Tap)
let eventCallback: CGEventTapCallBack = { (proxy, type, event, refcon) in
    
    if type == .keyDown {
        if activeModifierKeyCode != nil {
            modifierUsedWithOtherKey = true
        }
    }
    else if type == .flagsChanged {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        // 54 = Right Command, 61 = Right Option
        if keyCode == 54 || keyCode == 61 {
            if activeModifierKeyCode == keyCode {
                // --- RELEASE EVENT ---
                if !modifierUsedWithOtherKey {
                    if keyCode == 54 { switchLanguage(to: "com.apple.keylayout.ABC") }
                    else if keyCode == 61 { switchLanguage(to: "com.apple.inputmethod.Korean.2SetKorean") }
                }
                activeModifierKeyCode = nil
            } else {
                // --- PRESS DOWN EVENT ---
                activeModifierKeyCode = keyCode
                modifierUsedWithOtherKey = false
            }
        } else {
            if activeModifierKeyCode != nil {
                modifierUsedWithOtherKey = true
            }
        }
    }
    
    return Unmanaged.passUnretained(event)
}

// MARK: - 4. Setup and Run Loop
print("Starting up...")

let eventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)

guard let eventTap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: CGEventMask(eventMask),
    callback: eventCallback,
    userInfo: nil
) else {
    print("❌ FAILED: Cannot intercept keystrokes.")
    print("Ensure Terminal has Accessibility permissions in System Settings > Privacy & Security > Accessibility.")
    exit(1)
}

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: eventTap, enable: true)

print("✅ Listening in the background (Lone Modifiers Only).")
print("👉 Tap and release Right Command for English.")
print("👉 Tap and release Right Option for Korean.")
print("Press Ctrl+C in this terminal to quit.\n")

CFRunLoopRun()
