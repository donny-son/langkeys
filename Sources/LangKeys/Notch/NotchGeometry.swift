import AppKit

/// Which side of the notch a flag slides out from.
enum NotchSide: String, Codable {
    case left
    case right
}

/// Measurements of the physical notch (or a stand-in pill on displays without one).
///
/// Width/height derivation follows boring.notch's `getClosedNotchSize()`.
struct NotchGeometry {
    let screen: NSScreen
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let hasPhysicalNotch: Bool

    /// How far the black body stretches past the notch to make room for a flag.
    var wingWidth: CGFloat { flagSize + 26 }
    var flagSize: CGFloat { (notchHeight * 0.58).rounded() }

    /// The panel is sized for the widest state so it never has to resize mid-animation.
    var panelSize: CGSize {
        CGSize(width: notchWidth + wingWidth * 2 + 24, height: notchHeight + 4)
    }

    var panelOrigin: CGPoint {
        CGPoint(
            x: screen.frame.midX - panelSize.width / 2,
            y: screen.frame.maxY - panelSize.height)
    }

    static func current() -> NotchGeometry? {
        let notched = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        guard let screen = (NSScreen.main?.safeAreaInsets.top ?? 0) > 0
                ? NSScreen.main : (notched ?? NSScreen.main)
        else { return nil }

        let hasNotch = screen.safeAreaInsets.top > 0
        var width: CGFloat = 185
        if let left = screen.auxiliaryTopLeftArea?.width,
            let right = screen.auxiliaryTopRightArea?.width
        {
            // +4 hides the seam between our black body and the real notch cutout.
            width = screen.frame.width - left - right + 4
        }

        return NotchGeometry(
            screen: screen,
            notchWidth: width,
            notchHeight: hasNotch ? screen.safeAreaInsets.top : 32,
            hasPhysicalNotch: hasNotch)
    }
}
