import AppKit

/// The left sidebar: Files, Outline and Search, one at a time, picked by a
/// capsule switcher at the top.
///
/// It sits on a surface a shade off the canvas, the way Notion sets its
/// sidebar back from the page, with a hairline rather than a rule between.
final class SidebarView: NSView {
    enum Pane: Int, CaseIterable {
        case files, outline, search

        var symbol: String {
            switch self {
            case .files: "folder"
            case .outline: "list.bullet.indent"
            case .search: "magnifyingglass"
            }
        }

        var label: String {
            switch self {
            case .files: String(localized: "Files")
            case .outline: String(localized: "Outline")
            case .search: String(localized: "Find in Folder")
            }
        }
    }

    let files = FileTreeView()
    let outline = OutlineView()
    let search = SearchPaneView()

    /// Called when the user switches panes with the segmented control.
    var onPaneChange: ((Pane) -> Void)?

    private let picker = PanePicker()
    /// A plain view, not a separator `NSBox`: a box decides it is horizontal
    /// and hugs its height, which pinned top to bottom collapses the window.
    private let divider = NSView()

    private(set) var pane: Pane = .outline

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        picker.onSelect = { [weak self] pane in self?.pickerChanged(pane) }
        picker.translatesAutoresizingMaskIntoConstraints = false

        divider.wantsLayer = true
        divider.translatesAutoresizingMaskIntoConstraints = false

        addSubview(picker)
        addSubview(divider)
        var constraints = [
            picker.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            picker.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            picker.trailingAnchor.constraint(equalTo: divider.leadingAnchor, constant: -12),

            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.topAnchor.constraint(equalTo: topAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            widthAnchor.constraint(equalToConstant: Metrics.sidebarWidth),
        ]
        for view in [files, outline, search] as [NSView] {
            addSubview(view)
            constraints += [
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: divider.leadingAnchor),
                view.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 8),
                view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        show(.outline)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func applyTheme(_ theme: Theme) {
        layer?.backgroundColor = theme.sidebarFill.cgColor
        divider.layer?.backgroundColor = theme.hairline.cgColor
        picker.applyTheme(theme)
        files.applyTheme(theme)
        outline.applyTheme(theme)
        search.applyTheme(theme)
    }

    func show(_ pane: Pane) {
        let changed = pane != self.pane
        self.pane = pane
        picker.select(pane, animated: changed && window?.isVisible == true)
        let views: [Pane: NSView] = [.files: files, .outline: outline, .search: search]
        for (key, view) in views { view.isHidden = key != pane }
        // The incoming pane rises into place as the thumb slides to it.
        guard changed, window?.isVisible == true, Motion.isEnabled, let incoming = views[pane] else { return }
        incoming.alphaValue = 0
        Motion.animate(Motion.standard) { incoming.animator().alphaValue = 1 }
    }

    private func pickerChanged(_ pane: Pane) {
        guard pane != self.pane else { return }
        show(pane)
        onPaneChange?(pane)
    }
}

/// The pane switcher: a recessed capsule with a raised thumb that slides to
/// the chosen pane, like a segmented control in iOS.
final class PanePicker: NSView {
    var onSelect: ((SidebarView.Pane) -> Void)?

    private let thumb = NSView()
    private var buttons: [NSButton] = []
    private var selected: SidebarView.Pane = .outline
    private var theme: Theme = .light

    private static let height: CGFloat = 28
    private static let inset: CGFloat = 2

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Self.height / 2
        layer?.cornerCurve = .continuous

        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = (Self.height - 2 * Self.inset) / 2
        thumb.layer?.cornerCurve = .continuous
        thumb.layer?.shadowOpacity = 1
        thumb.layer?.shadowRadius = 2
        thumb.layer?.shadowOffset = CGSize(width: 0, height: -0.5)
        addSubview(thumb)

        for pane in SidebarView.Pane.allCases {
            let button = NSButton()
            button.isBordered = false
            button.bezelStyle = .accessoryBarAction
            button.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.label)
            button.symbolConfiguration = .init(pointSize: 12, weight: .medium)
            button.toolTip = pane.label
            button.setAccessibilityLabel(pane.label)
            button.tag = pane.rawValue
            button.target = self
            button.action = #selector(clicked(_:))
            addSubview(button)
            buttons.append(button)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel(String(localized: "Sidebar"))
        heightAnchor.constraint(equalToConstant: Self.height).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func applyTheme(_ theme: Theme) {
        self.theme = theme
        layer?.backgroundColor = theme.trackFill.cgColor
        thumb.layer?.backgroundColor = (theme.isDark ? theme.text.withAlphaComponent(0.14) : theme.canvas).cgColor
        thumb.layer?.shadowColor = NSColor.black.withAlphaComponent(theme.isDark ? 0.4 : 0.12).cgColor
        tintButtons()
    }

    func select(_ pane: SidebarView.Pane, animated: Bool) {
        selected = pane
        tintButtons()
        let target = slot(pane.rawValue).insetBy(dx: Self.inset, dy: Self.inset)
        if animated {
            Motion.animate(Motion.standard) { thumb.animator().frame = target }
        } else {
            thumb.frame = target
        }
    }

    private func slot(_ index: Int) -> NSRect {
        let width = bounds.width / CGFloat(max(buttons.count, 1))
        return NSRect(x: CGFloat(index) * width, y: 0, width: width, height: bounds.height)
    }

    override func layout() {
        super.layout()
        for (index, button) in buttons.enumerated() { button.frame = slot(index) }
        thumb.frame = slot(selected.rawValue).insetBy(dx: Self.inset, dy: Self.inset)
    }

    private func tintButtons() {
        for button in buttons {
            button.contentTintColor = button.tag == selected.rawValue ? theme.text : theme.secondaryText
        }
    }

    @objc private func clicked(_ sender: NSButton) {
        guard let pane = SidebarView.Pane(rawValue: sender.tag) else { return }
        onSelect?(pane)
    }
}

/// A sidebar row: a rounded wash under the pointer and a deeper one when
/// chosen, keeping the text its own colour instead of turning it white.
final class SidebarRowView: NSTableRowView {
    var theme: Theme = .light {
        didSet { needsDisplay = true }
    }

    private var isHovering = false {
        didSet { if isHovering != oldValue { needsDisplay = true } }
    }

    override var isEmphasized: Bool {
        get { false }
        set {}
    }

    private var wash: NSRect {
        bounds.insetBy(dx: Metrics.rowInset, dy: 1)
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isHovering, !isSelected else { return }
        theme.hoverFill.setFill()
        NSBezierPath(roundedRect: wash, xRadius: Metrics.rowRadius, yRadius: Metrics.rowRadius).fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        theme.selectionFill.setFill()
        NSBezierPath(roundedRect: wash, xRadius: Metrics.rowRadius, yRadius: Metrics.rowRadius).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func prepareForReuse() {
        super.prepareForReuse()
        isHovering = false
    }
}
