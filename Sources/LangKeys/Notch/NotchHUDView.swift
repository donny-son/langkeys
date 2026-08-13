import SwiftUI

/// The black body that grows out of one side of the notch, with the flag riding out of it.
struct NotchHUDView: View {
    @ObservedObject var hud: NotchHUD
    let geometry: NotchGeometry

    /// Overshooting spring — the low damping is what gives the stretch its gooey feel.
    private var bodySpring: Animation { .spring(response: 0.42, dampingFraction: 0.62) }
    /// The flag settles a touch later than the body, so it reads as being pulled along by it.
    private var flagSpring: Animation { .spring(response: 0.46, dampingFraction: 0.66) }

    private var wing: CGFloat { hud.isExpanded ? geometry.wingWidth : 0 }

    /// Grow on one side only: the body widens while the opposite edge stays pinned to the
    /// real notch, so the cutout never appears to drift.
    private var bodyOffset: CGFloat {
        hud.side == .left ? -wing / 2 : wing / 2
    }

    private var flagOffset: CGFloat {
        guard hud.isExpanded else { return 0 }
        let distance = geometry.notchWidth / 2 + geometry.wingWidth / 2
        return hud.side == .left ? -distance : distance
    }

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape()
                .fill(.black)
                .frame(width: geometry.notchWidth + wing, height: geometry.notchHeight)
                .offset(x: bodyOffset)
                .animation(bodySpring, value: hud.isExpanded)
                .animation(bodySpring, value: hud.side)

            // Kept in the hierarchy even while hidden: a view that is inserted on show would
            // appear at its final offset instead of sliding out of the notch.
            Text(hud.flag ?? "")
                .font(.system(size: geometry.flagSize))
                .scaleEffect(hud.isExpanded ? 1 : 0.35)
                .opacity(hud.isExpanded ? 1 : 0)
                .blur(radius: hud.isExpanded ? 0 : 3)
                .offset(x: flagOffset)
                .frame(height: geometry.notchHeight)
                .animation(flagSpring, value: hud.isExpanded)
                .animation(flagSpring, value: hud.side)
        }
        .frame(
            width: geometry.panelSize.width, height: geometry.panelSize.height, alignment: .top)
    }
}
