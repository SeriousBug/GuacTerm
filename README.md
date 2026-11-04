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

## Development

Install XCode command line tools and [xcodegen](https://github.com/yonaskolb/XcodeGen), then:

```sh
make project     # regenerate GuacTerm.xcodeproj from project.yml
make run         # build and launch
make dmg         # build and package a disk image in dist/
```

Run `./scripts/setup-dev.sh` to install the pre-commit hook
which will run lints and formatting checks before each commit.

## License

GuacTerm is licensed under [MIT](LICENSE).

It bundles the color schemes of
[iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes) and
links [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), both MIT. Their
notices, and the per-scheme credits, are reproduced in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

