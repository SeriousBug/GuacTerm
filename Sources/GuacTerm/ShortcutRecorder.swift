import AppKit
import SwiftUI

/// The AppKit control behind ``ShortcutRecorder``: a small capsule that shows
/// the current shortcut and, once clicked, captures the next key combination.
///
/// It is a custom view rather than a text field on purpose. A text field would
/// let the user type a spelling of a shortcut that may not match the key code
/// the Carbon hotkey registers, while an `NSEvent` gives us exactly the key code
/// and modifier mask `RegisterEventHotKey` wants.
final class ShortcutRecorderView: NSView {
    /// Virtual key codes, as in Carbon's `HIToolbox` key code table.
    private enum VirtualKey {
        static let escape: UInt16 = 0x35 // kVK_Escape
        static let delete: UInt16 = 0x33 // kVK_Delete, the Backspace key
        static let forwardDelete: UInt16 = 0x75 // kVK_ForwardDelete
    }

    private enum Metrics {
        static let width: CGFloat = 132
        static let height: CGFloat = 26
        static let cornerRadius: CGFloat = 7
        static let borderWidth: CGFloat = 1
        static let fontSize: CGFloat = 13
        static let horizontalInset: CGFloat = 6
    }

    /// The shortcut on display. Assigning redraws the capsule but never starts
    /// or stops recording.
    var combo: KeyCombo = .default {
        didSet {
            guard combo != oldValue else { return }
            needsDisplay = true
            updateAccessibilityValue()
        }
    }

    /// Called once the user completes a combination we can actually register.
    var onChange: ((KeyCombo) -> Void)?

    private(set) var isRecording = false

    // MARK: - Life cycle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Toggle Shortcut")
        updateAccessibilityValue()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("ShortcutRecorderView is created in code")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Metrics.width, height: Metrics.height)
    }

    // MARK: - First responder

    override var acceptsFirstResponder: Bool {
        true
    }

    /// A click on an inactive window should start recording straight away.
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        startRecording()
        return true
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func mouseDown(with _: NSEvent) {
        if window?.makeFirstResponder(self) ?? false {
            startRecording()
        }
    }

    // MARK: - Recording

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            // Not recording: behave like any other view so shortcuts and normal
            // typing keep working.
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case VirtualKey.escape:
            // Silent cancel, the old combination stays.
            stopRecording()
            return
        case VirtualKey.delete, VirtualKey.forwardDelete:
            NSSound.beep()
            stopRecording()
            return
        default:
            break
        }

        let candidate = KeyCombo.from(event: event)
        let isFunctionKey = KeyName.functionKeyCodes.contains(event.keyCode)

        // A global hotkey without ⌘⌥⌃⇧ would swallow ordinary typing, with the
        // sole exception of the function keys, which are fair game.
        guard candidate.hasModifier || isFunctionKey else {
            NSSound.beep()
            return // stay in recording mode
        }

        combo = candidate
        onChange?(candidate)
        stopRecording()
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        needsDisplay = true
        updateAccessibilityValue()
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        needsDisplay = true
        updateAccessibilityValue()
    }

    private func updateAccessibilityValue() {
        setAccessibilityValue(isRecording ? "Press keys" : combo.displayString)
    }

    // MARK: - Drawing

    override func draw(_: NSRect) {
        let outline = bounds.insetBy(dx: Metrics.borderWidth / 2, dy: Metrics.borderWidth / 2)
        let capsule = NSBezierPath(
            roundedRect: outline,
            xRadius: Metrics.cornerRadius,
            yRadius: Metrics.cornerRadius
        )
        capsule.lineWidth = Metrics.borderWidth

        if isRecording {
            NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
            capsule.fill()
            NSColor.controlAccentColor.setStroke()
        } else {
            NSColor.controlBackgroundColor.setFill()
            capsule.fill()
            NSColor.separatorColor.setStroke()
        }
        capsule.stroke()

        drawLabel()
    }

    private func drawLabel() {
        let text = isRecording ? "Press keys…" : combo.displayString
        let font = NSFont.systemFont(ofSize: Metrics.fontSize, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]

        let string = text as NSString
        var size = string.size(withAttributes: attributes)

        // Long combinations shrink instead of spilling out of the capsule.
        let available = bounds.width - Metrics.horizontalInset * 2
        if size.width > available, available > 0 {
            let scaled = NSFont.systemFont(
                ofSize: max(9, Metrics.fontSize * available / size.width),
                weight: .medium
            )
            let scaledAttributes: [NSAttributedString.Key: Any] = [
                .font: scaled,
                .foregroundColor: NSColor.labelColor,
            ]
            size = string.size(withAttributes: scaledAttributes)
            string.draw(
                at: NSPoint(
                    x: bounds.midX - size.width / 2,
                    y: bounds.midY - size.height / 2
                ),
                withAttributes: scaledAttributes
            )
            return
        }

        string.draw(
            at: NSPoint(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2
            ),
            withAttributes: attributes
        )
    }
}

/// A capsule that records the next key combination into `combo`.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var combo: KeyCombo

    func makeNSView(context _: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.combo = combo
        // Without this the capsule stretches to whatever width the row offers.
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        view.onChange = { newCombo in
            combo = newCombo
        }
        return view
    }

    func sizeThatFits(
        _: ProposedViewSize,
        nsView: ShortcutRecorderView,
        context _: Context
    ) -> CGSize? {
        nsView.intrinsicContentSize
    }

    func updateNSView(_ nsView: ShortcutRecorderView, context _: Context) {
        // While the user is recording, the view owns the value: writing it back
        // from stale state would drop the combination under their fingers.
        guard !nsView.isRecording else { return }
        if nsView.combo != combo {
            nsView.combo = combo
        }
    }
}
