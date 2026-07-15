# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

`lyra-screensaver` is a macOS **screen saver** (`.saver` bundle) that plays
[lyra](https://github.com/GeneralD/lyra)'s video wallpaper on the lock / idle
screen. Lyrics and overlays are intentionally excluded — this surface only
plays the wallpaper.

It does **not** persist its own settings. Following "plan B"
([GeneralD/lyra#325]), it reuses lyra's configuration and cache directly:

- Config: `~/.config/lyra/config.toml` `[wallpaper]`
- Video cache: `~/.cache/lyra/wallpapers/` (maintained by the lyra daemon)

Playback is driven by lyra's `WallpaperPresenter`, imported through the
**`LyraKit`** SwiftPM library product
([docs](https://github.com/GeneralD/lyra/blob/main/docs/LyraKit.md)).

## Build & Test

The Xcode project is **generated from `project.yml` by
[XcodeGen](https://github.com/yonaskolb/XcodeGen)** and is git-ignored — never
edit or commit `LyraScreenSaver.xcodeproj`; change `project.yml` instead.

```sh
brew install xcodegen        # one-time
make generate                # project.yml -> LyraScreenSaver.xcodeproj
make build                   # generate + build the .saver (Release)
make install                 # build + copy into ~/Library/Screen Savers
make uninstall               # remove the installed .saver
make clean                   # remove build/ and the generated project
```

Prefer `make build` over a hand-written `xcodebuild` line — the Makefile carries
the exact flags the build needs (see "Build gotchas"). CI runs the same flags in
`.github/workflows/release.yml`.

### Build gotchas

Linking LyraKit pulls in lyra's full implementation graph (MediaRemote, Audio,
the pointfree `swift-dependencies` ecosystem), so the screensaver build compiles
a large chunk of lyra. Two things bite under `xcodebuild` (but not `swift
build`), both handled in the `Makefile` `build:` target and the CI `Build` step
(keep those two in sync):

- **Swift macros must be trusted non-interactively** → `-skipMacroValidation`
  (lyra transitively uses the `papyrus` macro plugin).
- **Relocate output with `-derivedDataPath`, never `SYMROOT`.** `SYMROOT=build`
  desyncs the inter-package module search paths, so a transitive SwiftPM dep
  (`combine-schedulers`) fails to find its own dep (`ConcurrencyExtras`) with
  `no such module`. `-derivedDataPath build` relocates the whole build tree
  coherently; the `.saver` then lives at `build/Build/Products/Release/`.

Do **not** re-add `EXPLICIT_BUILT_MODULES=NO` / `SWIFT_ENABLE_EXPLICIT_MODULES=NO`
— disabling explicitly-built modules is what *caused* the `no such module`
failure on stable Xcode 16.4. (Xcode 26 betas carry a separate, still-open
"Explicitly Built Modules" bug that breaks this build locally regardless — build
on a stable Xcode, or wait for the fix.)

There is no unit-test target: all display logic is a thin map onto lyra's
already-tested `WallpaperPresenter`. Verification is a manual on-device smoke
test (`make install` → System Settings → Screen Saver → LyraScreenSaver).

## Architecture

One view, `Sources/LyraScreenSaverView.swift` (`ScreenSaverView` subclass):

- hosts an `AVPlayerLayer`, `videoGravity = .resizeAspectFill`
- attaches the presenter's stable `AVPlayer` **once** via `onPlayerAvailable`
- tracks per-item zoom via `onWallpaperScaleChange` → `setAffineTransform`
- mirrors lyra's own `AppWindow`: because the layer carries the scale transform,
  drive `bounds` + `position`, never `frame`

`Sources/Info.plist` binds `NSPrincipalClass = $(PRODUCT_MODULE_NAME).LyraScreenSaverView`.

## Version Management

`version.txt` is the single source of truth. On push to `main`,
`.github/workflows/release.yml` reads it, creates the `v<version>` tag + GitHub
release with the packaged `.saver`, and updates the Homebrew cask
`Casks/lyra-screensaver.rb` in `GeneralD/homebrew-tap` (which declares
`depends_on formula: "generald/tap/lyra"`).

**Bump `version.txt` in every PR** — `feat:` → minor, `fix:`/`refactor:`/`chore:`
→ patch, breaking → major.

## Git Workflow

**Never commit directly to `main`** (except the initial scaffold). Changes go
through a branch → PR → merge flow. Self-assign PRs and open them non-draft so
review bots start.

## Known follow-ups

- **Code signing / notarization** is not wired — CI ships an unsigned `.saver`,
  so Gatekeeper may block it until signing + notarization are added.
- **Sandbox access** to `~/.config/lyra` / `~/.cache/lyra` from the
  `legacyScreenSaver` host process is unverified on-device.

[GeneralD/lyra#325]: https://github.com/GeneralD/lyra/issues/325
