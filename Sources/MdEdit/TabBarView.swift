import AppKit

struct TabDescriptor: Equatable {
    /// Follows the document, so a tab keeps its segment as tabs come and go.
    var id: UUID
    var title: String
    var isDirty: Bool
}

@MainActor
protocol TabBarViewDelegate: AnyObject {
    func tabBar(_ bar: TabBarView, didSelect index: Int)
    func tabBar(_ bar: TabBarView, didRequestClose index: Int)
    func tabBarDidRequestNewTab(_ bar: TabBarView)
    func tabBar(_ bar: TabBarView, moveTabAt source: Int, to destination: Int)
    func tabBar(_ bar: TabBarView, didDragOutTabAt index: Int)
}

/// The tab strip, shaped like a segmented control: one recessed track spanning
/// the window, equal-width segments inside it, and a single raised glass thumb
/// that slides to whichever segment is selected.
///
/// The track is a tinted fill rather than glass, so the thumb is the only glass
/// here — glass stacked on glass reads as muddy, and the thumb is what should
/// look lifted.
///
/// Segments and the thumb are placed by frame rather than constraints, so a
/// change of tabs is one animation: a new tab opens out from nothing, a closed
/// one folds away, and the rest slide to their new places with the thumb.
final class TabBarView: NSView {
    weak var delegate: TabBarViewDelegate?

    private let track = NSView()
    private let thumb: GlassPanel
    private let newTabButton: GlassPanel
    private let plusButton = NSButton()
    private var segments: [TabSegment] = []

    /// The position of the tab being dragged, which moves as it is reordered.
    private var draggedIndex: Int?

    private(set) var tabs: [TabDescriptor] = []
    private(set) var selectedIndex = 0

    private var theme: Theme = .current(for: NSApp.effectiveAppearance)

    override init(frame frameRect: NSRect) {
        thumb = GlassPanel(
            content: NSView(),
            cornerRadius: (Metrics.trackHeight - 2 * Metrics.thumbInset) / 2,
            interactive: true
        )
        plusButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: String(localized: "New tab"))
        plusButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        plusButton.isBordered = false
        plusButton.bezelStyle = .accessoryBarAction
        plusButton.translatesAutoresizingMaskIntoConstraints = false
        newTabButton = GlassPanel(
            content: plusButton,
            cornerRadius: Metrics.plusDiameter / 2,
            interactive: true
        )

        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        track.translatesAutoresizingMaskIntoConstraints = false
        track.wantsLayer = true
        track.layer?.cornerRadius = Metrics.trackHeight / 2
        track.layer?.cornerCurve = .continuous

        thumb.translatesAutoresizingMaskIntoConstraints = true
        // Thumb first: it sits behind the segment labels.
        track.addSubview(thumb)
        addSubview(track)
        addSubview(newTabButton)

        plusButton.target = self
        plusButton.action = #selector(newTab)
        plusButton.toolTip = String(localized: "New Tab (⌘T)")

        // To VoiceOver the strip is a tab group of radio-button tabs.
        setAccessibilityElement(true)
        setAccessibilityRole(.tabGroup)
        setAccessibilityLabel(String(localized: "Tabs"))

        NSLayoutConstraint.activate([
            track.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.chromeInset),
            track.centerYAnchor.constraint(equalTo: centerYAnchor),
            track.heightAnchor.constraint(equalToConstant: Metrics.trackHeight),
            track.trailingAnchor.constraint(equalTo: newTabButton.leadingAnchor, constant: -Metrics.tabGap),

            newTabButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.chromeInset),
            newTabButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            newTabButton.widthAnchor.constraint(equalToConstant: Metrics.plusDiameter),
            newTabButton.heightAnchor.constraint(equalToConstant: Metrics.plusDiameter),

            heightAnchor.constraint(equalToConstant: Metrics.trackHeight + 2 * Metrics.tabGap),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setTabs(_ tabs: [TabDescriptor], selected: Int) {
        // Typing asks on every keystroke; usually nothing has changed.
        guard tabs != self.tabs || selected != selectedIndex || segments.count != tabs.count else { return }
        let oldIDs = segments.map(\.id)
        let reused = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })
        let ids = Set(tabs.map(\.id))
        let removed = segments.filter { !ids.contains($0.id) }
        var added: [TabSegment] = []
        segments = tabs.enumerated().map { index, tab in
            if let segment = reused[tab.id] {
                segment.index = index
                return segment
            }
            let segment = makeSegment(id: tab.id, index: index)
            added.append(segment)
            return segment
        }
        let moved = oldIDs != segments.map(\.id) || selected != selectedIndex
        self.tabs = tabs
        selectedIndex = selected
        for (index, segment) in segments.enumerated() {
            segment.apply(tabs[index], isSelected: index == selected, theme: theme)
        }

        // Typing refreshes the tabs on every keystroke; only a change of
        // tabs or selection moves anything.
        guard moved else { return }
        layoutSubtreeIfNeeded()
        guard shouldAnimate else {
            for segment in removed { segment.removeFromSuperview() }
            layoutSegments(animated: false)
            return
        }

        // A new tab opens out from a sliver where it will sit.
        let count = segments.count
        for segment in added {
            let slot = slotFrame(at: segment.index, count: count)
            segment.frame = NSRect(x: slot.minX, y: slot.minY, width: 0, height: slot.height)
            segment.alphaValue = 0
        }
        // A closing tab no longer answers clicks while it folds away.
        for segment in removed {
            segment.onSelect = nil
            segment.onClose = nil
            segment.onDrag = nil
        }
        // With no thumb to slide from, it fades in where it lands.
        if thumb.isHidden { thumb.alphaValue = 0 }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.standard
            context.timingFunction = Motion.curve
            // Lets each segment's title follow its frame instead of jumping.
            context.allowsImplicitAnimation = true
            layoutSegments(animated: true)
            for segment in added { segment.alphaValue = 1 }
            for segment in removed {
                var folded = segment.frame
                folded.size.width = 0
                segment.frame = folded
                segment.alphaValue = 0
            }
            thumb.alphaValue = 1
            track.layoutSubtreeIfNeeded()
        } completionHandler: {
            // AppKit calls it on the main thread, though its type does not say so.
            MainActor.assumeIsolated {
                for segment in removed { segment.removeFromSuperview() }
            }
        }
    }

    func applyTheme(_ theme: Theme) {
        self.theme = theme
        track.layer?.backgroundColor = theme.trackFill.cgColor
        plusButton.contentTintColor = theme.secondaryText
        thumb.tint = nil
        for (index, segment) in segments.enumerated() where index < tabs.count {
            segment.apply(tabs[index], isSelected: index == selectedIndex, theme: theme)
        }
    }

    override func layout() {
        super.layout()
        layoutSegments(animated: false)
    }

    /// Animations play only where someone can see them, and not for anyone
    /// who has asked for less motion.
    private var shouldAnimate: Bool {
        window?.isVisible == true
            && track.bounds.width > 0
            && Motion.isEnabled
    }

    private func slotFrame(at index: Int, count: Int) -> NSRect {
        let width = track.bounds.width / CGFloat(max(count, 1))
        return NSRect(x: CGFloat(index) * width, y: 0, width: width, height: track.bounds.height)
    }

    /// Puts each segment in its slot and the thumb under the selected one.
    /// This is also the tab-switch animation: one piece of glass moving, not
    /// a crossfade.
    private func layoutSegments(animated: Bool) {
        let count = segments.count
        for (index, segment) in segments.enumerated() {
            let slot = slotFrame(at: index, count: count)
            // Unchanged frames are left alone so a layout pass mid-animation
            // does not cut it short.
            guard segment.frame != slot else { continue }
            if animated { segment.animator().frame = slot } else { segment.frame = slot }
        }

        guard segments.indices.contains(selectedIndex) else {
            thumb.isHidden = true
            return
        }
        thumb.isHidden = false
        let target = slotFrame(at: selectedIndex, count: count).insetBy(dx: Metrics.thumbInset, dy: Metrics.thumbInset)
        guard thumb.frame != target else { return }
        if animated { thumb.animator().frame = target } else { thumb.frame = target }
    }

    private func makeSegment(id: UUID, index: Int) -> TabSegment {
        let segment = TabSegment(index: index, id: id)
        segment.onSelect = { [weak self] index in
            guard let self else { return }
            draggedIndex = index
            delegate?.tabBar(self, didSelect: index)
        }
        segment.onDrag = { [weak self] event in self?.dragTab(with: event) }
        segment.onRelease = { [weak self] in self?.draggedIndex = nil }
        segment.onClose = { [weak self] index in
            guard let self else { return }
            delegate?.tabBar(self, didRequestClose: index)
        }
        track.addSubview(segment)
        return segment
    }

    /// Reorders live: crossing into a neighbour's segment swaps places, and
    /// the thumb slides along with the tab.
    private func dragTab(with event: NSEvent) {
        guard let source = draggedIndex, !segments.isEmpty else { return }
        // Pulled well clear of the strip, the tab leaves for a window of its own.
        let point = convert(event.locationInWindow, from: nil)
        if point.y < -Metrics.tearOffDistance || point.y > bounds.height + Metrics.tearOffDistance {
            draggedIndex = nil
            delegate?.tabBar(self, didDragOutTabAt: source)
            return
        }
        let x = track.convert(event.locationInWindow, from: nil).x
        let width = track.bounds.width / CGFloat(segments.count)
        guard width > 0 else { return }
        let target = min(max(0, Int(x / width)), segments.count - 1)
        guard target != source else { return }
        draggedIndex = target
        delegate?.tabBar(self, moveTabAt: source, to: target)
    }

    @objc private func newTab() {
        delegate?.tabBarDidRequestNewTab(self)
    }
}

/// One segment of the track: a centred title, a dirty dot, and a close button
/// that appears on hover.
final class TabSegment: NSView {
    /// Where the segment sits, which changes as tabs are reordered or closed.
    var index: Int
    let id: UUID
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onDrag: ((NSEvent) -> Void)?
    var onRelease: (() -> Void)?

    private let label = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let dirtyDot = NSView()
    private var isDirty = false
    private var isSelected = false
    private var isHovering = false
    private var hoverFill: NSColor = .clear

    init(index: Int, id: UUID = UUID()) {
        self.index = index
        self.id = id
        super.init(frame: .zero)
        // Placed by the tab bar's frames; clipped so it can open from nothing.
        wantsLayer = true
        clipsToBounds = true
        layer?.cornerRadius = Metrics.trackHeight / 2
        layer?.cornerCurve = .continuous

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: String(localized: "Close tab"))
        closeButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        closeButton.isBordered = false
        closeButton.bezelStyle = .accessoryBarAction
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isHidden = true
        closeButton.target = self
        closeButton.action = #selector(close)

        dirtyDot.wantsLayer = true
        dirtyDot.layer?.cornerRadius = 3
        dirtyDot.translatesAutoresizingMaskIntoConstraints = false
        dirtyDot.isHidden = true

        addSubview(label)
        addSubview(closeButton)
        addSubview(dirtyDot)

        // Short of required: a segment opening or folding away is briefly
        // narrower than its margins.
        let labelLeading = label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24)
        let labelTrailing = label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24)
        labelLeading.priority = .init(999)
        labelTrailing.priority = .init(999)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            // Short of required: a segment opening or folding away is briefly
            // narrower than its margins.
            labelLeading,
            labelTrailing,

            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 14),

            dirtyDot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            dirtyDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dirtyDot.widthAnchor.constraint(equalToConstant: 6),
            dirtyDot.heightAnchor.constraint(equalToConstant: 6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func apply(_ tab: TabDescriptor, isSelected: Bool, theme: Theme) {
        label.stringValue = tab.title
        label.textColor = isSelected ? theme.text : theme.secondaryText
        closeButton.contentTintColor = theme.secondaryText
        dirtyDot.layer?.backgroundColor = theme.secondaryText.cgColor
        hoverFill = theme.hoverFill
        isDirty = tab.isDirty
        self.isSelected = isSelected
        toolTip = tab.title
        updateHoverItems()
        // The close button only shows on hover, so VoiceOver gets an action instead.
        label.setAccessibilityElement(false)
        closeButton.setAccessibilityLabel(String(localized: "Close \(tab.title)"))
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: String(localized: "Close Tab")) { [weak self] in
                guard let self else { return false }
                onClose?(index)
                return true
            },
        ])
    }

    // MARK: - Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .radioButton }
    override func accessibilityRoleDescription() -> String? { String(localized: "tab") }
    override func accessibilityLabel() -> String? {
        isDirty ? String(localized: "\(label.stringValue), edited") : label.stringValue
    }
    override func accessibilityValue() -> Any? { isSelected ? 1 : 0 }
    override func isAccessibilitySelected() -> Bool { isSelected }

    override func accessibilityPerformPress() -> Bool {
        onSelect?(index)
        onRelease?()
        return true
    }

    private func updateHoverItems() {
        closeButton.isHidden = !isHovering
        dirtyDot.isHidden = !isDirty
        // A wash under the pointer on tabs the thumb is not already marking.
        layer?.backgroundColor = (isHovering && !isSelected ? hoverFill : .clear).cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateHoverItems()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateHoverItems()
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?(index)
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag?(event)
    }

    override func mouseUp(with event: NSEvent) {
        onRelease?()
    }

    @objc private func close() {
        onClose?(index)
    }
}
