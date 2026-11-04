@testable import GuacTerm
import XCTest

/// Where the drop-down window sits on a screen, worked out from the screen's
/// visible area alone.
///
/// These are the numbers a person sees every time the panel drops down, and the
/// height slider is the setting most likely to be fiddled with: the size of the
/// window is resolved here, as a pure function, so the panel can follow the
/// slider without waiting for the next launch.
@MainActor
final class PanelGeometryTests: XCTestCase {
    /// The visible area of a 16-inch display: 1920 wide, 1055 tall once the menu
    /// bar and the Dock have taken their share.
    private var typicalVisibleFrame: NSRect {
        NSRect(x: 0, y: 0, width: 1920, height: 1055)
    }

    /// A display to the right of and above the main one, which is what a second
    /// screen usually looks like: its own origin, not the main screen's.
    private var secondDisplayVisibleFrame: NSRect {
        NSRect(x: 1920, y: 105, width: 1440, height: 900)
    }

    /// The panel is a strip across the very top of the screen, like a projector
    /// screen being pulled down: full width, hanging from the top edge, never
    /// centred and never floating in the middle of the desktop.
    func testPanelSpansTheWidthOfTheScreenAndHangsFromItsTopEdge() {
        let visibleFrame = typicalVisibleFrame
        let frame = TerminalController.frame(forVisibleFrame: visibleFrame, heightFraction: 0.45)

        XCTAssertEqual(frame.minX, visibleFrame.minX)
        XCTAssertEqual(frame.width, visibleFrame.width)
        XCTAssertEqual(frame.maxY, visibleFrame.maxY, "the panel's top edge is the visible area's top edge")
        // 474.75 points on a 1920x1055 display: the top 45% of the screen.
        XCTAssertEqual(frame.height, visibleFrame.height * 0.45)
    }

    /// The slider goes down to 15% and a hand-edited default can go lower, but
    /// a window that is a few points tall is not a terminal: it would collapse
    /// to an unreadable smear rather than show anything.
    func testATinyFractionStillLeavesAWindowWorthLookingAt() {
        let visibleFrame = typicalVisibleFrame

        let squeezed = TerminalController.frame(forVisibleFrame: visibleFrame, heightFraction: 0.001)
        XCTAssertEqual(squeezed.height, 120)
        XCTAssertEqual(squeezed.maxY, visibleFrame.maxY)

        // Nothing in `Limits` stops a written-by-hand negative fraction, and the
        // panel still has to be somewhere usable.
        let negative = TerminalController.frame(forVisibleFrame: visibleFrame, heightFraction: -0.5)
        XCTAssertEqual(negative.height, 120)
    }

    /// The fraction is a fraction of the screen, so asking for more than all of
    /// it must not produce a window that runs under the menu bar and off the
    /// bottom of the display.
    func testAFractionAboveOneNeverGrowsPastTheVisibleHeight() {
        let visibleFrame = typicalVisibleFrame
        for fraction in [1.0, 1.5, 12.0] {
            let frame = TerminalController.frame(forVisibleFrame: visibleFrame, heightFraction: fraction)
            XCTAssertEqual(
                frame.height,
                visibleFrame.height,
                "a fraction of \(fraction) should be capped at the screen"
            )
            XCTAssertEqual(frame.maxY, visibleFrame.maxY)
        }
    }

    /// A second display has its own origin and its own top edge, and the panel
    /// has to drop down there — over that screen — rather than at the main
    /// screen's coordinates.
    func testASecondDisplayKeepsItsOwnLeftAndTopEdge() {
        let visibleFrame = secondDisplayVisibleFrame
        let frame = TerminalController.frame(forVisibleFrame: visibleFrame, heightFraction: 0.45)

        XCTAssertEqual(frame.minX, visibleFrame.minX)
        XCTAssertEqual(frame.maxY, visibleFrame.maxY)
        XCTAssertEqual(frame.width, visibleFrame.width)
        XCTAssertEqual(frame.height, visibleFrame.height * 0.45)
        XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY, "the panel stays clear of the Dock")
    }

    /// The slide-in is a window parked above the screen edge animating down. If
    /// the park is not exactly one window-height above the resting place the
    /// panel either peeks in before it is shown or travels further than it has
    /// to, and the animation looks like a glitch rather than a drop.
    func testParkingPutsThePanelExactlyOneWindowHeightAboveWhereItRests() {
        let visibleFrame = typicalVisibleFrame
        let resting = TerminalController.frame(forVisibleFrame: visibleFrame, heightFraction: 0.45)
        let park = TerminalController.offscreenFrame(from: resting)

        XCTAssertEqual(park.minX, resting.minX, "the slide is vertical only")
        XCTAssertEqual(park.width, resting.width)
        XCTAssertEqual(park.height, resting.height)
        XCTAssertEqual(park.minY, resting.maxY, "the park's bottom edge meets the resting frame's top edge")
        XCTAssertEqual(park.minY - resting.minY, resting.height)
        XCTAssertGreaterThanOrEqual(park.minY, visibleFrame.maxY, "the park is entirely above the screen")
    }

    /// A height fraction that is not a number falls cleanly out of the two
    /// clamps: it produces a full-height window rather than a broken frame or
    /// none at all.
    ///
    /// The settings model no longer hands this function a NaN — a stored one is
    /// replaced with the default when it is loaded — so this is the arithmetic's
    /// own answer rather than a state the app can reach. It is worth keeping:
    /// the alternative to "as tall as possible" is a frame AppKit cannot use.
    func testAHeightFractionThatIsNotANumberFallsThroughToAFullHeightWindow() {
        let visibleFrame = typicalVisibleFrame
        let frame = TerminalController.frame(forVisibleFrame: visibleFrame, heightFraction: .nan)

        XCTAssertEqual(frame.height, visibleFrame.height)
        XCTAssertEqual(frame.maxY, visibleFrame.maxY)
        XCTAssertEqual(frame.width, visibleFrame.width)
    }

    /// `argv[0]` is how a program is told to behave as a login shell, and only
    /// the leading dash matters: without it `zsh` skips `.zprofile` and `.zshrc`
    /// and the terminal opens with a bare prompt and none of the user's aliases.
    func testLoginProgramNameIsTheBasenameWithALeadingDash() {
        XCTAssertEqual(TerminalController.loginName(for: "/bin/zsh"), "-zsh")
        XCTAssertEqual(TerminalController.loginName(for: "zsh"), "-zsh")
        XCTAssertEqual(TerminalController.loginName(for: "/opt/homebrew/bin/fish"), "-fish")
        XCTAssertEqual(TerminalController.loginName(for: "/bin/sh"), "-sh")
    }
}
