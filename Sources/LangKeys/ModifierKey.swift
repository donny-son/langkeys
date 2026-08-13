import Foundation
import CoreGraphics

/// A modifier key that can be tapped on its own to trigger an input-source switch.
///
/// The raw value is the hardware key code reported by `flagsChanged` events.
enum ModifierKey: Int64, CaseIterable, Codable {
    case rightCommand = 54
    case rightOption = 61
    case rightShift = 60
    case rightControl = 62
    case leftCommand = 55
    case leftOption = 58
    case leftShift = 56
    case leftControl = 59
    case function = 63

    var title: String {
        switch self {
        case .rightCommand: return "Right ⌘ Command"
        case .rightOption: return "Right ⌥ Option"
        case .rightShift: return "Right ⇧ Shift"
        case .rightControl: return "Right ⌃ Control"
        case .leftCommand: return "Left ⌘ Command"
        case .leftOption: return "Left ⌥ Option"
        case .leftShift: return "Left ⇧ Shift"
        case .leftControl: return "Left ⌃ Control"
        case .function: return "Fn"
        }
    }

    /// Device-dependent flag bit that is set while this specific physical key is held.
    /// Lets us tell a press apart from a release without keeping a toggle guess.
    var flagBit: UInt64 {
        switch self {
        case .leftControl: return 0x0000_0001
        case .leftShift: return 0x0000_0002
        case .rightShift: return 0x0000_0004
        case .leftCommand: return 0x0000_0008
        case .rightCommand: return 0x0000_0010
        case .leftOption: return 0x0000_0020
        case .rightOption: return 0x0000_0040
        case .rightControl: return 0x0000_2000
        case .function: return UInt64(CGEventFlags.maskSecondaryFn.rawValue)
        }
    }

    func isHeld(in flags: CGEventFlags) -> Bool {
        flags.rawValue & flagBit != 0
    }

    static func from(keyCode: Int64) -> ModifierKey? {
        ModifierKey(rawValue: keyCode)
    }
}
