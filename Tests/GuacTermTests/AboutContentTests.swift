@testable import GuacTerm
import XCTest

/// The About window carries its own copy of the legal text, because neither
/// `LICENSE` nor `THIRD_PARTY_NOTICES.md` is part of the app bundle. These
/// tests read those two files and compare, so the copy cannot drift from what
/// the repository actually says — and a new dependency added to the notices
/// fails here until it is shown in the window too.
final class AboutContentTests: XCTestCase {
    // MARK: - The repository

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // GuacTermTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // the repository
    }

    private func repositoryFile(_ path: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    // MARK: - GuacTerm's own license

    /// What the window shows has to be the license file itself, word for word:
    /// an About pane that paraphrases a license is worse than none.
    func testTheLicenseInTheWindowIsTheLicenseInTheRepository() throws {
        let license = try repositoryFile("LICENSE")
        XCTAssertEqual(
            AboutContent.licenseText.trimmingCharacters(in: .whitespacesAndNewlines),
            license.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// The user asked for a specific holder and year, and both the header and
    /// the license body have to name them the same way.
    func testTheCopyrightNamesTheHolderAndYearInBothPlaces() {
        XCTAssertEqual(AboutContent.copyrightHolder, "Kaan C. Barmore-Genc")
        XCTAssertEqual(AboutContent.copyrightYear, "2026")
        XCTAssertTrue(AboutContent.licenseText.contains(AboutContent.copyrightLine))
    }

    // MARK: - Third-party notices

    /// Every notice is reproduced verbatim, in the order the notices file
    /// lists them, so the window is not a summary of the attributions.
    func testEveryThirdPartyNoticeIsReproducedVerbatim() throws {
        let notices = try repositoryFile("THIRD_PARTY_NOTICES.md")
        let blocks = fencedBlocks(in: notices)
        let components = AboutContent.components

        XCTAssertEqual(
            blocks.count,
            components.count,
            "THIRD_PARTY_NOTICES.md has \(blocks.count) license blocks but the window shows \(components.count)"
        )

        for (block, component) in zip(blocks, components) {
            XCTAssertEqual(
                component.licenseText.trimmingCharacters(in: .whitespacesAndNewlines),
                block.trimmingCharacters(in: .whitespacesAndNewlines),
                "the \(component.name) license differs from the one in THIRD_PARTY_NOTICES.md"
            )
        }
    }

    /// Each component is shown with a link that goes somewhere, and the notices
    /// that ship with the app point at the same projects the repository does.
    func testEveryComponentPointsAtAnUpstreamProjectTheNoticesName() throws {
        let notices = try repositoryFile("THIRD_PARTY_NOTICES.md")
        XCTAssertFalse(AboutContent.components.isEmpty, "the window needs a component to show")

        for component in AboutContent.components {
            XCTAssertNotNil(URL(string: component.upstream), "\(component.name) has no usable URL")
            XCTAssertTrue(
                notices.contains(component.upstream),
                "THIRD_PARTY_NOTICES.md does not mention \(component.upstream)"
            )
            XCTAssertFalse(component.usage.isEmpty)
            XCTAssertFalse(component.licenseName.isEmpty)
            XCTAssertTrue(component.licenseText.contains(component.copyright))
        }
    }

    // MARK: - Helpers

    /// The contents of every ```-fenced block, in order.
    private func fencedBlocks(in markdown: String) -> [String] {
        var blocks: [String] = []
        var lines: [String] = []
        var insideFence = false

        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("```") {
                if insideFence {
                    blocks.append(lines.joined(separator: "\n"))
                    lines = []
                }
                insideFence.toggle()
                continue
            }
            if insideFence {
                lines.append(line)
            }
        }

        return blocks
    }
}
