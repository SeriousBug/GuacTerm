import Foundation

/// The legal text the About window shows: GuacTerm's own license and the
/// notices of the third-party work it bundles or links.
///
/// Held as data rather than read from the repository's `LICENSE` and
/// `THIRD_PARTY_NOTICES.md`, because neither file is part of the app bundle.
/// `AboutContentTests` compares the copies here against both files, so the
/// text cannot quietly drift from what the repository ships.
enum AboutContent {
    // MARK: - GuacTerm

    static let licenseName = "MIT License"
    static let copyrightHolder = "Kaan C. Barmore-Genc"
    static let copyrightYear = "2026"

    /// The line the MIT license itself carries, so the header and the license
    /// body cannot disagree about who holds the copyright.
    static let copyrightLine = "Copyright (c) \(copyrightYear) \(copyrightHolder)"

    static let licenseSummary = """
    MIT: use, change and share it, as long as this notice stays with it and \
    the warranty stays disclaimed.
    """

    static let licenseText = """
    MIT License

    \(copyrightLine)

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    """

    // MARK: - Third party

    static let thirdPartySummary = """
    GuacTerm bundles or links the work below. Each project keeps its own \
    copyright, and its license is reproduced in full.
    """

    /// One bundled or linked project.
    struct Component: Identifiable, Sendable {
        let id: String
        let name: String
        /// What GuacTerm uses it for, and how it is shipped.
        let usage: String
        let licenseName: String
        let copyright: String
        /// The project's home page, as text so a malformed entry degrades into
        /// a line that is simply not a link.
        let upstream: String
        /// Something the license text does not say on its own, if anything.
        var notice: String?
        let licenseText: String
    }

    static let components: [Component] = [
        Component(
            id: "iterm2-color-schemes",
            name: "iTerm2-Color-Schemes",
            usage: "Color schemes, bundled as theme data",
            licenseName: "MIT",
            copyright: "Copyright (c) 2011 to Present Mark Badolato",
            upstream: "https://github.com/mbadolato/iTerm2-Color-Schemes",
            notice: """
            Each scheme stays the copyright of the person who created it; the \
            project's CREDITS.md is the authoritative list.
            """,
            licenseText: iTerm2ColorSchemesLicense
        ),
        Component(
            id: "swiftterm",
            name: "SwiftTerm",
            usage: "Terminal emulator core, linked as a package",
            licenseName: "MIT",
            copyright: "Copyright (c) 2019-2026 Miguel de Icaza",
            upstream: "https://github.com/migueldeicaza/SwiftTerm",
            notice: """
            SwiftTerm in turn depends on other MIT-licensed packages \
            (swift-argument-parser, swift-png, h), resolved from their own \
            repositories at build time.
            """,
            licenseText: swiftTermLicense
        ),
        Component(
            id: "sparkle",
            name: "Sparkle",
            usage: "Application updates, linked and embedded",
            licenseName: "MIT",
            copyright: "Copyright (c) 2006-2013 Andy Matuschak",
            upstream: "https://github.com/sparkle-project/Sparkle",
            notice: """
            Sparkle bundles bsdiff/bspatch (© 2003-2005 Colin Percival, \
            BSD-style) and sais-lite (© 2008-2010 Yuta Mori, MIT) inside \
            Sparkle.framework; both notices ship in its own LICENSE.
            """,
            licenseText: sparkleLicense
        ),
    ]

    // MARK: - License texts

    /// Reproduced verbatim, including the extra paragraphs upstream appends.
    private static let iTerm2ColorSchemesLicense = """
    MIT License

    Copyright (c) 2011 to Present Mark Badolato

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

    This license covers the iTerm-Color-Schemes repository collection of themes.

    The copyright/license for each individual theme belongs to the author of that theme.
    """

    private static let swiftTermLicense = """
    Copyright (c) 2019-2026 Miguel de Icaza (https://github.com/migueldeicaza)
    Copyright (c) 2017-2019, The xterm.js authors (https://github.com/xtermjs/xterm.js)
    Copyright (c) 2014-2016, SourceLair Private Company (https://www.sourcelair.com)
    Copyright (c) 2012-2013, Christopher Jeffrey (https://github.com/chjj/)
    Copyright (c) 2016 Ryan L McIntyre (Powerline Extra Symbols flame silhouette, https://github.com/ryanoasis/powerline-extra-symbols)

    Permission is hereby granted, free of charge, to any person obtaining
    a copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to
    the following conditions:

    The above copyright notice and this permission notice shall be
    included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
    EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
    NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
    LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
    OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
    WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """

    private static let sparkleLicense = """
    Copyright (c) 2006-2013 Andy Matuschak.
    Copyright (c) 2009-2013 Elgato Systems GmbH.
    Copyright (c) 2011-2014 Kornel Lesiński.
    Copyright (c) 2015-2017 Mayur Pawashe.
    Copyright (c) 2014 C.W. Betts.
    Copyright (c) 2014 Petroules Corporation.
    Copyright (c) 2014 Big Nerd Ranch.
    All rights reserved.

    Permission is hereby granted, free of charge, to any person obtaining a copy of
    this software and associated documentation files (the "Software"), to deal in
    the Software without restriction, including without limitation the rights to
    use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
    the Software, and to permit persons to whom the Software is furnished to do so,
    subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
    FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
    COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
    IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
    CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """
}
