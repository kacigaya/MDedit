import AppKit

/// Decides which block shows its raw markdown.
///
/// The caret's own line is revealed — that is how you edit syntax you can
/// otherwise no longer see — and everything else stays rendered. Typewriter and
/// focus modes hang off the same selection hook.
@MainActor
final class ActiveLineController {
    weak var textView: NSTextView?
    private let storage: MarkdownTextStorage

    var typewriterMode = false {
        didSet { if typewriterMode { centreCaret(animated: false) } }
    }

    var focusMode = false {
        didSet { selectionChanged() }
    }

    static let maxRevealedLines = 100

    /// A picture of the text as it was, fading out over the new layout.
    private var crossfade: NSView?

    init(storage: MarkdownTextStorage, textView: NSTextView) {
        self.storage = storage
        self.textView = textView
    }

    func selectionChanged() {
        guard let textView else { return }
        let selection = textView.selectedRange()
        let firstLine = storage.line(at: selection.location)
        let lastLine = selection.length > 0
            ? storage.line(at: NSMaxRange(selection))
            : firstLine

        // The caret never sits in a fold: moving into one opens it.
        for line in [firstLine, lastLine] where storage.isHidden(line: line) {
            storage.reveal(line: line)
        }
        // Past a screenful, a selection is for copying, moving or deleting,
        // not for editing its syntax: only the line it ends on shows as
        // written, instead of every line in it restyling and reflowing.
        let revealed = lastLine - firstLine <= Self.maxRevealedLines ? firstLine...lastLine : lastLine...lastLine
        if revealed != storage.revealedLines, shouldCrossfade {
            // Markers appearing push the line's text along and can nudge the
            // lines below; fading from the old layout softens that jump.
            crossfade(in: textView) { storage.revealedLines = revealed }
        } else {
            storage.revealedLines = revealed
        }

        if let manager = textView.layoutManager as? MarkdownLayoutManager {
            let old = manager.focusRange
            let new = focusMode ? storage.characterRange(forLines: firstLine...lastLine) : nil
            manager.focusRange = new
            switch (old, new) {
            case let (old?, new?) where old != new:
                // Only the lines leaving and entering focus change how they are dimmed.
                for range in [old, new] {
                    let location = min(range.location, storage.length)
                    manager.invalidateDisplay(forCharacterRange: NSRange(location: location, length: min(range.length, storage.length - location)))
                }
            case (nil, _?), (_?, nil):
                manager.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: storage.length))
            default:
                break
            }
        }

        if typewriterMode {
            centreCaret(animated: true)
        }
    }

    /// Only a move the reader made, by clicking or with the arrow keys, fades:
    /// not typing a new line, and not each step of a drag selection.
    private var shouldCrossfade: Bool {
        guard Motion.isEnabled, textView?.window?.isVisible == true, let event = NSApp.currentEvent else { return false }
        switch event.type {
        case .leftMouseDown, .leftMouseUp:
            return true
        case .keyDown:
            let navigation: [NSEvent.SpecialKey] = [.upArrow, .downArrow, .leftArrow, .rightArrow, .pageUp, .pageDown, .home, .end]
            return event.specialKey.map(navigation.contains) ?? false
        default:
            return false
        }
    }

    /// Lays a snapshot of the visible text over the view, makes the change
    /// underneath, and fades the snapshot away.
    private func crossfade(in textView: NSTextView, _ change: () -> Void) {
        let rect = textView.visibleRect
        crossfade?.removeFromSuperview()
        crossfade = nil
        guard rect.width > 0, rect.height > 0, let snapshot = textView.bitmapImageRepForCachingDisplay(in: rect) else {
            return change()
        }
        textView.cacheDisplay(in: rect, to: snapshot)
        let overlay = PassThroughView(frame: rect)
        overlay.wantsLayer = true
        overlay.layer?.contents = snapshot.cgImage
        overlay.layer?.contentsGravity = .resize
        textView.addSubview(overlay)
        crossfade = overlay

        change()
        Motion.animate(Motion.fade) {
            overlay.animator().alphaValue = 0
        } completion: { [weak self, weak overlay] in
            overlay?.removeFromSuperview()
            if self?.crossfade === overlay { self?.crossfade = nil }
        }
    }

    /// Keeps the caret's line vertically centred, the way a typewriter's platen
    /// keeps the writing line in place.
    private func centreCaret(animated: Bool) {
        guard let textView,
              let scrollView = textView.enclosingScrollView,
              let manager = textView.layoutManager,
              let container = textView.textContainer
        else { return }

        let selection = textView.selectedRange()
        let glyphRange = manager.glyphRange(forCharacterRange: selection, actualCharacterRange: nil)
        let caretRect = manager.boundingRect(forGlyphRange: glyphRange, in: container)
        let caretCentre = caretRect.midY + textView.textContainerInset.height

        let visible = scrollView.contentView.bounds
        var target = caretCentre - visible.height / 2
        let maximum = max(0, textView.bounds.height - visible.height)
        target = min(max(0, target), maximum)

        guard abs(target - visible.origin.y) > 1 else { return }
        let point = NSPoint(x: visible.origin.x, y: target)
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                scrollView.contentView.animator().setBoundsOrigin(point)
            }
            scrollView.reflectScrolledClipView(scrollView.contentView)
        } else {
            scrollView.contentView.setBoundsOrigin(point)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}

/// A view the mouse goes straight through, so a click or the second half of
/// a double-click lands on the text beneath it.
private final class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
