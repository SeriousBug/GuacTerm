import AppKit

/// The drop-down window.
///
/// Two things separate this from a plain `NSWindow`:
///
/// - A borderless window refuses keyboard focus by default. A terminal that
///   cannot take keystrokes is useless, so `canBecomeKey` is forced on.
/// - AppKit keeps windows on screen by clamping their frame during
///   `setFrame`. The slide-in works by parking the window *above* the top edge
///   of the screen and animating it down, which AppKit would otherwise undo.
final class DropDownPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func constrainFrameRect(_ frameRect: NSRect, to _: NSScreen?) -> NSRect {
        frameRect
    }

    /// The panel is never dragged around, so it should not take part in window
    /// cycling or be raised by a click.
    override var isMovable: Bool {
        get { false }
        set {}
    }
}

/// Content view of the panel: paints the theme background and clips the
/// terminal to rounded bottom corners, so the window reads as something pulled
/// down from the top of the screen rather than a floating box.
final class DropDownContainerView: NSView {
    var cornerRadius: CGFloat = 12 {
        didSet { layer?.cornerRadius = cornerRadius }
    }

    var backgroundColor: NSColor = .black {
        didSet {
            layer?.backgroundColor = backgroundColor.cgColor
            needsDisplay = true
        }
    }

    /// Called when the appearance this view inherits changes, which is how a
    /// switch between light and dark reaches the terminal: with two schemes
    /// selected, that is what decides which one it is painted with.
    var onEffectiveAppearanceChange: (() -> Void)?

    override var isOpaque: Bool {
        false
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = cornerRadius
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChange?()
    }
}
