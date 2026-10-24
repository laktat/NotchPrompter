import CoreGraphics

/// Sizes shared by the panel (window frame) and the SwiftUI content, so they never disagree.
struct OverlayLayout {
    static let flare: CGFloat = 10
    static let bottomRadius: CGFloat = 20
    static let horizontalPadding: CGFloat = 18
    static let bottomPadding: CGFloat = 8
    /// Top inset without a notch, so the text doesn't touch the screen edge.
    static let noNotchTopInset: CGFloat = 6

    let bodyWidth: CGFloat
    let topInset: CGFloat
    let textHeight: CGFloat

    init(settings: PrompterSettings, geometry: NotchGeometry) {
        // Always at least as wide as the hardware notch plus room for the bottom corners.
        bodyWidth = max(CGFloat(settings.width), geometry.notchWidth + 2 * Self.bottomRadius)
        topInset = geometry.hasNotch ? geometry.notchHeight : Self.noNotchTopInset
        textHeight = CGFloat(settings.height)
    }

    var windowWidth: CGFloat { bodyWidth + 2 * Self.flare }
    var windowHeight: CGFloat { topInset + textHeight + Self.bottomPadding }
    var textWidth: CGFloat { bodyWidth - 2 * Self.horizontalPadding }

    /// Window frame in screen coordinates: centred, top edge flush with the top of the screen.
    func frame(in geometry: NotchGeometry) -> CGRect {
        CGRect(x: geometry.screenFrame.midX - windowWidth / 2,
               y: geometry.screenFrame.maxY - windowHeight,
               width: windowWidth,
               height: windowHeight)
    }
}
