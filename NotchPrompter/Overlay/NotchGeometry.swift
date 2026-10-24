import AppKit

/// Where the camera notch is on the screen the overlay lives on.
struct NotchGeometry: Equatable {
    let screenFrame: CGRect
    /// Height of the notch (equals the menu bar height on notched Macs). 0 without a notch.
    let notchHeight: CGFloat
    /// Width of the physical notch. 0 without a notch.
    let notchWidth: CGFloat

    var hasNotch: Bool { notchWidth > 0 && notchHeight > 0 }

    init(screen: NSScreen) {
        screenFrame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            notchHeight = screen.safeAreaInsets.top
            notchWidth = screen.frame.width - left.width - right.width
        } else {
            notchHeight = 0
            notchWidth = 0
        }
    }

    /// The notched built-in display if there is one, else any built-in display, else the main screen.
    static func preferredScreen() -> NSScreen? {
        let screens = NSScreen.screens
        return screens.first { $0.safeAreaInsets.top > 0 }
            ?? screens.first { $0.isBuiltIn }
            ?? NSScreen.main
            ?? screens.first
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var isBuiltIn: Bool {
        displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false
    }
}
