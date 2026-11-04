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

    /// Where GuacTerm's own source lives, so the window can point at it the same
    /// way it points at the projects it is built on.
    static let sourceCode = "https://github.com/SeriousBug/GuacTerm"

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
    GuacTerm is built on top of the projects listed below. We thank the authors \
    of these projects for their amazing work.
    """

    /// The per-scheme credits of the color scheme collection, which is where the
    /// authorship of each individual scheme is recorded.
    static let iTerm2Credits =
        "https://github.com/mbadolato/iTerm2-Color-Schemes/blob/master/CREDITS.md"

    /// One bundled or linked project.
    struct Component: Identifiable, Sendable {
        let id: String
        let name: String
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
            id: "swiftterm",
            name: "SwiftTerm",
            licenseName: "MIT",
            copyright: "Copyright (c) 2019-2026 Miguel de Icaza",
            upstream: "https://github.com/migueldeicaza/SwiftTerm",
            licenseText: swiftTermLicense
        ),
        Component(
            id: "iterm2-color-schemes",
            name: "iTerm2-Color-Schemes",
            licenseName: "MIT",
            copyright: "Copyright (c) 2011 to Present Mark Badolato",
            upstream: "https://github.com/mbadolato/iTerm2-Color-Schemes",
            notice: """
            Each scheme is owned by the person who created that theme. Please \
            see [CREDITS.md](\(iTerm2Credits)) in the project.
            """,
            licenseText: iTerm2ColorSchemesLicense
        ),
        Component(
            id: "sparkle",
            name: "Sparkle",
            licenseName: "MIT",
            copyright: "Copyright (c) 2006-2013 Andy Matuschak",
            upstream: "https://github.com/sparkle-project/Sparkle",
            licenseText: sparkleLicense
        ),
        Component(
            id: "bsdiff",
            name: "bsdiff/bspatch",
            licenseName: "BSD 2-Clause",
            copyright: "Copyright 2003-2005 Colin Percival",
            upstream: "http://www.daemonology.net/bsdiff/",
            licenseText: bsdiffLicense
        ),
        Component(
            id: "sais-lite",
            name: "sais-lite",
            licenseName: "MIT",
            copyright: "Copyright (c) 2008-2010 Yuta Mori",
            upstream: "https://sites.google.com/site/yuta256/sais",
            licenseText: saisLicense
        ),
        Component(
            id: "ed25519",
            name: "Ed25519",
            licenseName: "zlib",
            copyright: "Copyright (c) 2015 Orson Peters",
            upstream: "https://github.com/orlp/ed25519",
            licenseText: ed25519License
        ),
        Component(
            id: "susignatureverifier",
            name: "SUSignatureVerifier",
            licenseName: "BSD 2-Clause",
            copyright: "Copyright (c) 2011 Mark Hamlin",
            upstream: "https://github.com/sparkle-project/Sparkle/blob/2.10.1/Autoupdate/SUSignatureVerifier.m",
            licenseText: susignatureVerifierLicense
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

    /// The four pieces of third-party code Sparkle compiles into
    /// `Sparkle.framework`, and the notices its own `LICENSE` gives them.
    private static let bsdiffLicense = """
    Copyright 2003-2005 Colin Percival
    All rights reserved

    Redistribution and use in source and binary forms, with or without
    modification, are permitted providing that the following conditions
    are met:
    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.

    THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
    IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
    WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
    ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
    DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
    DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
    OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
    HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
    STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
    IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
    """

    private static let saisLicense = """
    Copyright (c) 2008-2010 Yuta Mori All Rights Reserved.

    Permission is hereby granted, free of charge, to any person
    obtaining a copy of this software and associated documentation
    files (the "Software"), to deal in the Software without
    restriction, including without limitation the rights to use,
    copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the
    Software is furnished to do so, subject to the following
    conditions:

    The above copyright notice and this permission notice shall be
    included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
    EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
    OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
    NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
    HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
    WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
    OTHER DEALINGS IN THE SOFTWARE.
    """

    private static let ed25519License = """
    Copyright (c) 2015 Orson Peters <orsonpeters@gmail.com>

    This software is provided 'as-is', without any express or implied warranty. In no event will the
    authors be held liable for any damages arising from the use of this software.

    Permission is granted to anyone to use this software for any purpose, including commercial
    applications, and to alter it and redistribute it freely, subject to the following restrictions:

    1. The origin of this software must not be misrepresented; you must not claim that you wrote the
       original software. If you use this software in a product, an acknowledgment in the product
       documentation would be appreciated but is not required.

    2. Altered source versions must be plainly marked as such, and must not be misrepresented as
       being the original software.

    3. This notice may not be removed or altered from any source distribution.
    """

    private static let susignatureVerifierLicense = """
    Copyright (c) 2011 Mark Hamlin.

    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted providing that the following conditions
    are met:
    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.

    THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
    IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
    WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
    ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
    DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
    DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
    OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
    HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
    STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
    IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
    """
}
