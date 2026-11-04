@testable import GuacTerm
import XCTest

/// The two window behaviours the drop-down cannot work without, and the shape
/// the content view draws.
///
/// None of this needs the panel on screen: these are properties of the window
/// AppKit honours whenever it is ordered in, which is why they are worth pinning
/// here rather than noticing them in a recording of the slide.
@MainActor
final class DropDownPanelTests: XCTestCase {
    private func makePanel() -> DropDownPanel {
        DropDownPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
    }

    /// A borderless window says no to keyboard focus unless it is told
    /// otherwise, and a terminal that cannot take keystrokes is a picture of a
    /// terminal. The shortcut is the whole way into this app, so the first
    /// keystroke after it has to land in the shell.
    func testBorderlessPanelStillTakesKeyboardAndMainFocus() {
        let panel = makePanel()
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.canBecomeMain)
    }

    /// AppKit keeps windows on screen by clamping their frame, and the panel's
    /// whole animation is a window parked *above* the top edge of the display.
    /// If this ever returned a clamped rect the panel would appear instantly at
    /// its resting place and the drop would silently disappear.
    func testPanelKeepsAFrameThatSitsEntirelyAboveTheScreen() {
        let panel = makePanel()

        let onScreen = NSRect(x: 0, y: 555, width: 1200, height: 500)
        XCTAssertEqual(panel.constrainFrameRect(onScreen, to: nil), onScreen)

        // Where a slide starts and where it ends up: completely off the top of
        // the display, which is exactly what AppKit would normally undo.
        let parked = NSRect(x: 0, y: 1055, width: 1200, height: 500)
        XCTAssertEqual(panel.constrainFrameRect(parked, to: nil), parked)

        // Taller and wider than any screen, for a panel whose height setting was
        // pushed past what the display can show.
        let oversized = NSRect(x: -200, y: 4000, width: 6000, height: 5000)
        XCTAssertEqual(panel.constrainFrameRect(oversized, to: nil), oversized)
    }

    /// A panel that can be dragged around would be dragged off the top edge and
    /// left there, and it would take part in window cycling. Nothing may turn
    /// that back on, including a stray assignment.
    func testPanelIsNeverMovable() {
        let panel = makePanel()
        XCTAssertFalse(panel.isMovable)

        panel.isMovable = true
        XCTAssertFalse(panel.isMovable)
    }

    /// The rounded corners are drawn by the layer, not by the terminal or the
    /// material behind it, so the radius has to reach the layer or the window
    /// keeps square corners however the setting is set.
    func testCornerRadiusReachesTheLayer() throws {
        let container = DropDownContainerView(frame: NSRect(x: 0, y: 0, width: 1200, height: 500))
        let layer = try XCTUnwrap(container.layer)
        XCTAssertEqual(layer.cornerRadius, container.cornerRadius)
        XCTAssertTrue(layer.masksToBounds)

        container.cornerRadius = 4
        XCTAssertEqual(layer.cornerRadius, 4)
    }

    /// Only the two corners away from the top of the screen are round. That is
    /// what makes the window read as something pulled down from the top edge
    /// instead of a floating box, and it has to stay that way if the radius
    /// changes.
    func testOnlyTheTwoCornersAwayFromTheScreenEdgeAreRounded() throws {
        let container = DropDownContainerView(frame: NSRect(x: 0, y: 0, width: 1200, height: 500))
        let layer = try XCTUnwrap(container.layer)

        XCTAssertEqual(layer.maskedCorners, [.layerMinXMinYCorner, .layerMaxXMinYCorner])
        XCTAssertFalse(layer.maskedCorners.contains(.layerMinXMaxYCorner))
        XCTAssertFalse(layer.maskedCorners.contains(.layerMaxXMaxYCorner))
    }

    /// The container sits in front of the desktop, and on the glass material it
    /// has to stay transparent: an opaque backing would hide the model the
    /// material is drawing and the panel would go solid.
    func testContainerStaysTransparentSoWhatIsBehindItShowsThrough() {
        let container = DropDownContainerView(frame: NSRect(x: 0, y: 0, width: 1200, height: 500))
        XCTAssertFalse(container.isOpaque)
    }
}
