@testable import GuacTerm
import SwiftTerm
import XCTest

/// Tabs are how `ls` pads its columns, so a grid that loses its tab stops makes
/// every listing look wrapped at random. These tests pin the SwiftTerm behaviour
/// GuacTerm works around in ``GuacTerminalView/repairTabStopsIfNeeded()``.
@MainActor
final class TabStopsTests: XCTestCase {
    private final class SilentDelegate: TerminalDelegate {
        func send(source _: Terminal, data _: ArraySlice<UInt8>) {}
    }

    /// A 376-column grid: wide enough to have columns past the 80-column default
    /// that SwiftTerm's buffers are built for.
    private let wideCols = 376

    private func makeTerminal(cols: Int) -> Terminal {
        Terminal(delegate: SilentDelegate(), options: TerminalOptions(cols: cols, rows: 6))
    }

    /// Column the character `marker` ended up in, after `prefix` was printed and
    /// a TAB was sent.
    private func columnAfterTab(cols: Int, prefixLength: Int, nudged: Bool) -> Int? {
        let terminal = makeTerminal(cols: cols)
        if nudged {
            // What `repairTabStopsIfNeeded()` does: a resize, and back.
            terminal.resize(cols: cols / 2, rows: 6)
            terminal.resize(cols: cols, rows: 6)
        }
        terminal.feed(text: String(repeating: "a", count: prefixLength) + "\tB\r\n")

        guard let line = terminal.getLine(row: 0) else { return nil }
        for column in 0 ..< cols where line[column].getCharacter() == "B" {
            return column
        }
        return nil
    }

    /// The stop a TAB from `column` should reach: the next eighth column.
    private func expectedStop(from column: Int, cols: Int) -> Int {
        min(((column / 8) + 1) * 8, cols - 1)
    }

    func testFreshWideGridLosesItsStopsPastColumn72() throws {
        // Documents the library behaviour this app cannot rely on: a stop that
        // should be at column 80 sends the text to the last column instead.
        let column = try XCTUnwrap(columnAfterTab(cols: wideCols, prefixLength: 72, nudged: false))
        XCTAssertEqual(column, wideCols - 1)
    }

    func testResizeRestoresStopsAcrossTheWholeGrid() throws {
        for prefix in [0, 8, 64, 72, 80, 128, 200, 360, 368] {
            let column = try XCTUnwrap(columnAfterTab(cols: wideCols, prefixLength: prefix, nudged: true))
            XCTAssertEqual(
                column,
                expectedStop(from: prefix, cols: wideCols),
                "TAB after \(prefix) cells should reach column \(expectedStop(from: prefix, cols: wideCols))"
            )
        }
    }

    func testNarrowGridNeedsNoRepair() throws {
        // Below the threshold GuacTerm does not nudge, so this has to be right
        // without one.
        let cols = GuacTerminalView.narrowestGridNeedingTabRepair - 1
        for prefix in [0, 8, 40, 64] {
            let column = try XCTUnwrap(columnAfterTab(cols: cols, prefixLength: prefix, nudged: false))
            XCTAssertEqual(column, expectedStop(from: prefix, cols: cols))
        }
    }

    func testRepairIsOnlyAskedForOnGridsThatNeedIt() {
        let size = NSSize(width: 3008, height: 748)
        XCTAssertNil(GuacTerminalView.tabStopRepairSize(
            for: size,
            cols: GuacTerminalView.narrowestGridNeedingTabRepair - 1
        ))
        let intermediate = GuacTerminalView.tabStopRepairSize(
            for: size,
            cols: GuacTerminalView.narrowestGridNeedingTabRepair
        )
        XCTAssertNotNil(intermediate)
        XCTAssertLessThan(intermediate?.width ?? size.width, size.width)
        XCTAssertEqual(intermediate?.height, size.height)
        XCTAssertNil(GuacTerminalView.tabStopRepairSize(for: .zero, cols: wideCols))
    }

    func testRepairKeepsTheGridAtItsOwnSize() {
        let view = GuacTerminalView(
            frame: NSRect(x: 0, y: 0, width: 1200, height: 400),
            font: nil,
            options: TerminalOptions(cursorStyle: .blinkBlock)
        )
        let before = view.terminalDimensions
        XCTAssertGreaterThanOrEqual(before.cols, GuacTerminalView.narrowestGridNeedingTabRepair)

        view.repairTabStopsIfNeeded()

        XCTAssertEqual(view.terminalDimensions.cols, before.cols)
        XCTAssertEqual(view.terminalDimensions.rows, before.rows)
    }

    func testThresholdIsWhereTheStopsRunOut() throws {
        let cols = GuacTerminalView.narrowestGridNeedingTabRepair
        // The last column the 80-column default has a stop for is 72.
        let column = try XCTUnwrap(columnAfterTab(cols: cols, prefixLength: 72, nudged: false))
        XCTAssertEqual(column, cols - 1, "a grid this wide still needs the repair")
    }
}
