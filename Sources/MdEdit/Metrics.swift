import AppKit
import QuartzCore

/// Layout constants shared by every piece of chrome.
///
/// Keeping them in one place is what makes concentric corners possible: an inner
/// glass element inset from the window edge must curve by the window's radius
/// minus that inset, or its curve fights the window's.
enum Metrics {
    /// Approximate corner radius of a macOS window on Tahoe.
    static let windowCornerRadius: CGFloat = 16

    /// Standard inset of floating chrome from the window edge.
    static let chromeInset: CGFloat = 10

    /// Radius for chrome inset by `chromeInset`, concentric with the window.
    static var concentricRadius: CGFloat { windowCornerRadius - chromeInset }

    /// Height of the segmented tab track.
    static let trackHeight: CGFloat = 30

    /// Inset of the raised thumb inside the track.
    static let thumbInset: CGFloat = 2

    /// Diameter of the round "new tab" button beside the track.
    static let plusDiameter: CGFloat = 30

    /// Gap between the track and the button beside it.
    static let tabGap: CGFloat = 8

    /// Height of the bottom status bar.
    static let statusBarHeight: CGFloat = 28

    /// Width of the text column in the editor canvas.
    static let defaultLineWidth: CGFloat = 720

    /// Width of the sidebar holding files, outline and search.
    static let sidebarWidth: CGFloat = 240

    /// Space above and below an inline image preview.
    static let imageSpacing: CGFloat = 6

    /// How far a tab must be dragged off the strip to tear off into a window.
    static let tearOffDistance: CGFloat = 40

    /// Height of a table's hidden delimiter row, drawn as a rule.
    static let tableRuleHeight: CGFloat = 9

    /// Tall images are scaled down to this height.
    static let maxImageHeight: CGFloat = 420

    /// Typeset diagrams and formulas are scaled down to this height.
    static let maxDiagramHeight: CGFloat = 900

    /// Space a code card leaves above its first line and below its last.
    static let codeCardPadding: CGFloat = 8

    /// Corner radius of a code card.
    static let codeCardRadius: CGFloat = 8

    /// Corner radius of a row's hover and selection wash in lists and menus.
    static let rowRadius: CGFloat = 6

    /// Inset of that wash from the list's edges.
    static let rowInset: CGFloat = 6
}

/// How chrome moves: one curve and a few durations, so everything that
/// slides or fades settles the same way.
@MainActor
enum Motion {
    /// A fast start that eases long into place, close to the system's springs.
    static var curve: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1) }

    /// Hover washes and small state changes.
    static let quick: TimeInterval = 0.12
    /// The text settling as a line reveals or hides its markdown.
    static let fade: TimeInterval = 0.18
    /// Tabs, menus and page fades.
    static let standard: TimeInterval = 0.24
    /// Panels that move a lot of the window, such as the sidebar.
    static let slow: TimeInterval = 0.32

    /// Animations play only for those who have not asked for less motion.
    static var isEnabled: Bool { !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Runs changes on the shared curve, or at once when motion is reduced.
    static func animate(
        _ duration: TimeInterval = standard,
        _ changes: () -> Void,
        completion: (@MainActor () -> Void)? = nil
    ) {
        guard isEnabled else {
            changes()
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = curve
            context.allowsImplicitAnimation = true
            changes()
        } completionHandler: {
            MainActor.assumeIsolated { completion?() }
        }
    }
}
