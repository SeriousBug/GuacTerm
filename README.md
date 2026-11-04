# GuacTerm

A drop-down terminal for macOS. One global shortcut pulls a terminal down from
the top of the screen; the same shortcut puts it away. It stays running in the
menu bar in between, so the shell, its history and its working directory are
still there when you come back.

GuacTerm does one thing. There are no tabs, no splits, no profiles and no
plugins. If you want tabs and splits, run tmux or zellij inside it — that is
what the terminal is for.

- **One shortcut, one terminal.** ⌥⌘T by default, changeable in Settings.
- **No permissions to grant.** The global shortcut uses Carbon hot keys, so
  macOS never asks for Accessibility or Input Monitoring.
- **A real terminal.** PTY, VT/xterm emulation, truecolor, sixel, inline images,
  kitty graphics, OSC 52 clipboard, full mouse reporting — all via
  [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).
- **GPU rendering.** Metal by default, with a Core Graphics fallback.
- **891 color schemes.** The whole [iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes)
  collection, plus two of our own.
- **Liquid Glass.** Optionally draw the terminal on macOS's native glass
  material, so the desktop shows through it (macOS 26 and later).

Requires macOS 14 or later. Liquid Glass requires macOS 26 or later.

---

## Install

Download `GuacTerm-<version>.zip` from the releases page, unzip it, and move
`GuacTerm.app` to `/Applications`. It is signed with a Developer ID and
notarized, so it opens without a Gatekeeper warning, and it is not sandboxed
because it has to fork/exec your shell.

GuacTerm has no Dock icon. Look for the terminal glyph in the menu bar:
left-click toggles the terminal, right-click opens the menu (Show/Hide,
Settings, Quit).

## Build from source

Requirements: macOS 14+, Xcode 26 or later (the project uses the Swift 6
language mode with complete concurrency checking), and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) if you want to regenerate the
project (`brew install xcodegen`).

```sh
make build      # Release build -> dist/GuacTerm.app (ad-hoc signed)
make run        # build, then launch
```

`GuacTerm.xcodeproj` is committed, so `open GuacTerm.xcodeproj` works without
XcodeGen. `project.yml` is the source of truth: run `make project` after changing
it.

Command-line builds pass `-skipPackagePluginValidation -skipMacroValidation`,
because SwiftTerm ships a SwiftPM build-tool plugin that Xcode would otherwise
ask you to trust interactively.

### Distributing

```sh
NOTARY_PROFILE=guacterm-notary make dist
```

`scripts/notarize.sh` signs with a Developer ID, submits to `notarytool`, staples
the ticket and writes `dist/GuacTerm-<version>.zip`. Credentials come from the
environment or a `notarytool` keychain profile, never from the repository; see
the header of the script for the accepted variables.

---

## Using it

| | |
| --- | --- |
| ⌥⌘T (default) | Show or hide the terminal |
| Menu bar, left click | Same as the shortcut |
| Menu bar, right click | Settings, About, Quit |
| ⌘C / ⌘V | Copy and paste, through the Edit menu |
| Right click in the panel | Copy, Paste, Select All |

The terminal drops down over whatever you were doing and takes keyboard focus.
Hiding it does **not** close the shell: hide it all day and the same session is
waiting when you come back. Only `exit`, or quitting GuacTerm, ends it. Changing
the shell or the scrollback setting starts a new session the next time the panel
opens, so a running command is never killed underneath you.

Clicking anywhere in the panel reaches the terminal immediately, even when
another app was frontmost — the first click is not spent on focusing the window.

### Settings

Everything lives in one window (menu bar › Settings); there is no Apply button.
The terminal stays on screen behind it, so every change can be seen as you make
it — even with "Hide When Focus Is Lost" on, which is ignored while Settings is
open.

| Setting | What it does |
| --- | --- |
| Toggle Shortcut | Records any combination with at least one modifier, or a bare function key. Conflicting shortcuts are reported instead of silently ignored. |
| Shell | Type a program and press return; a bare name (`zsh`, `fish`, `zellij`) is looked up in `PATH`, or give a full path. The menu lists the installed shells and multiplexers, and nothing that is not there. It runs as a login shell, so it reads the same startup files Terminal.app would. |
| Scrollback | Lines of history to keep. Applies to the next session. |
| Window Height | How much of the screen the panel takes, 15–100%. The panel follows the slider. |
| Font | Any installed fixed-pitch family, 8–48 pt. |
| Appearance | System, Light or Dark. This is the app's chrome only; the terminal follows the theme. |
| Theme | A searchable list of every scheme, applied live as you browse. Cancel puts the old one back. |
| Liquid Glass | Paints the theme over macOS's native glass material instead of a solid background (macOS 26+). Hidden on older systems. |
| Glass Tint | How much theme color sits on the glass: 100% is nearly solid, 20% lets the desktop through almost untouched. |
| Hide When Focus Is Lost | Drop the panel away when you switch to another app. Settings is exempt so the preview stays visible. |
| Launch at Login | Registers the app with `SMAppService`. Needs a signed bundle to take effect. |

Settings are stored in `UserDefaults` under `com.guacterm.GuacTerm`, so they can
be scripted or reset:

```sh
defaults read com.guacterm.GuacTerm
defaults delete com.guacterm.GuacTerm          # back to defaults
defaults write com.guacterm.GuacTerm themeID -string nord
defaults write com.guacterm.GuacTerm shellPath -string zellij
defaults write com.guacterm.GuacTerm scrollbackLines -int 50000
defaults write com.guacterm.GuacTerm glassBackground -bool YES
defaults write com.guacterm.GuacTerm glassTint -float 0.55
```

Quit and relaunch after editing by hand — GuacTerm reads these once at launch.

### Launch flags

Handy while developing, ignored otherwise:

| Flag | Effect |
| --- | --- |
| `--show` | Drop the terminal down at launch |
| `--settings` | Open the settings window |
| `--theme-picker` | Open settings with the theme sheet already up |

### Environment

`GUACTERM_CPU_RENDER=1` skips the Metal renderer and draws with Core Graphics.
That is the first thing to try if a machine shows rendering glitches; the
startup log says which renderer is in use.

---

## The terminal

GuacTerm is a shell around SwiftTerm, so the emulation is a real VT parser backed
by a real PTY, not a text view. Sessions get:

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

The shell inherits the environment GuacTerm was started with, plus the variables
above, and `XPC_*` leftovers are removed so build tools behave.

## How it works

```
Sources/GuacTerm/
  main.swift                  NSApplication bootstrap; accessory app, no Dock icon
  AppDelegate.swift           Menu bar item, global hotkey, main menu, settings window
  GlobalHotKey.swift          Carbon RegisterEventHotKey — no permission prompts
  KeyCombo.swift              Shortcut model: Codable, display string, key names
  DropDownPanel.swift         Borderless panel that may sit above the screen edge
  TerminalController.swift    Show/hide, slide animation, session, theme and glass
  GuacTerminalView.swift      Metal enablement, first-click handling, context menu
  ShellEnvironment.swift      The environment a new shell starts with
  Settings.swift              Every setting, persisted; limits; shell and font lists
  SettingsView.swift          The settings pane
  ShortcutRecorder.swift      The shortcut field
  ThemePicker.swift           The searchable theme sheet
  TerminalTheme.swift         A scheme and its NSColor/SwiftTerm conversions
  ThemeCatalog.swift          The two signature schemes, merged with the collection
  ThemeCatalogLoader.swift    Parses Themes.json once, degrades to 2 themes if missing
  SettingsWindowController.swift
Resources/Themes.json         891 schemes, generated, MIT
Resources/Info.plist          Generated by XcodeGen from project.yml
scripts/build.sh              Release build -> dist/GuacTerm.app
scripts/notarize.sh           Sign, notarize, staple, zip
scripts/generate-themes.py    Rebuilds Resources/Themes.json from a scheme checkout
```

A few decisions worth knowing:

- **The window slides by moving its origin, never its size.** The PTY is never
  resized mid-animation, so nothing reflows and no program sees a spurious
  `SIGWINCH` storm.
- **`constrainFrameRect` is overridden.** AppKit keeps windows on screen; the
  panel has to be parked above the top edge to slide in.
- **Hot keys are Carbon, not `CGEventTap`.** Registration needs no permission
  and conflicts are detectable. The trade-off is that a shortcut must be a
  combination with a modifier (or a function key) — a lone-modifier tap or a
  double-tap of ⌥ would need an Accessibility-granted event tap, which GuacTerm
  deliberately does not require.
- **Glass is a real material, not alpha.** `NSGlassEffectView` samples the
  desktop behind the non-opaque panel; the theme is then painted over it at the
  glass tint. The terminal view lives in the material's `contentView`, because
  the material composites above sibling views.
- **No App Sandbox.** A sandboxed app cannot fork/exec an arbitrary login shell
  and have it behave like a terminal.

## Limitations

- **One window, one session.** That is the product.
- **Carbon hot key constraints:** the shortcut needs a modifier (or a bare
  function key); some F-keys are swallowed by macOS as media keys; nothing
  arrives while Secure Input is on (password prompts, some password managers).
- Some renderers, notably a few implementations of synchronized output, are
  whatever SwiftTerm supports today.
- Changing the theme recolors cells that have already been drawn but keeps the
  scrolled-off history; nothing is re-rendered.

## License

GuacTerm is MIT-licensed — see [LICENSE](LICENSE).

It bundles the color schemes of
[iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes) and
links [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), both MIT. Their
notices, and the per-scheme credits, are reproduced in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
