# GuacTerm

A dead simple, guake-style terminal for MacOS. Pull it down and dismiss it back up with a single keyboard shortcut.

No tabs or splits or profiles to manage, just the essentials and some quality of life features. 
For stuff like tabs, you can always use tmux or zellij.

## Features

- Fully native terminal with GPU accelerated rendering
- Graphics support including sixel, iTerm2, and kitty images
- Mouse reporting & OSC 52 clipboard control
- Liquid glass background for native look and feel
- Support for iTerm2 color schemes, with 800+ color schemes from [mbadolato/iterm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes)

## Install

Download `GuacTerm.<version>.dmg` from the downloads page.

## The terminal

GuacTerm is built around SwiftTerm. Sessions get:

| | |
| --- | --- |
| `TERM` | `xterm-256color`, `COLORTERM=truecolor` |
| Colors | 16 ANSI, 256-color and 24-bit truecolor, from the selected theme |
| Sixel | on |
| iTerm2 inline images | OSC 1337, on |
| kitty graphics | on, 64 MB per screen, local transfer media allowed |
| Clipboard | OSC 52 and kitty's OSC 5522 both read and write the system pasteboard, which is how Claude Code and friends copy and paste |
| Mouse | button, drag, wheel, SGR and urxvt encodings, as reported by SwiftTerm |
| Rendering | Metal (GPU) with a Core Graphics fallback |
| Input | bracketed paste, alt/meta keys, IME input |

## Development

Building needs the Xcode command line tools and
[xcodegen](https://github.com/yonaskolb/XcodeGen):

```sh
make project     # regenerate GuacTerm.xcodeproj from project.yml
make run         # build, then launch
```

Formatting and lint are checked before every commit. `./setup-dev.sh` installs
that hook. The two tools it runs,
[SwiftFormat](https://github.com/nicklockwood/SwiftFormat) and
[SwiftLint](https://github.com/realm/SwiftLint), are expected on `PATH`; the
script names them if they are missing but never installs anything itself:

```sh
brew install swiftformat swiftlint
./setup-dev.sh
make format      # rewrite the sources to the style in .swiftformat
make check       # exactly what the hook runs, without touching a file
```

`git commit --no-verify` skips the check once.

## License

GuacTerm is licensed under [MIT](LICENSE).

It bundles the color schemes of
[iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes) and
links [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), both MIT. Their
notices, and the per-scheme credits, are reproduced in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

