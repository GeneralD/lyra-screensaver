# AGENTS.md

Codex entrypoint for `lyra-screensaver`. Long-form conventions live in
[`.claude/CLAUDE.md`](.claude/CLAUDE.md); this is the short version.

## What this is

A macOS screen saver (`.saver`) that plays [lyra](https://github.com/GeneralD/lyra)'s
video wallpaper (no lyrics). It reuses lyra's `~/.config/lyra/config.toml`
`[wallpaper]` config and `~/.cache/lyra/wallpapers/` cache via the **LyraKit**
SwiftPM library product instead of persisting its own settings
([GeneralD/lyra#325]).

## Build

The Xcode project is generated from `project.yml` by
[XcodeGen](https://github.com/yonaskolb/XcodeGen) and is git-ignored — edit
`project.yml`, never the `.xcodeproj`.

```sh
brew install xcodegen   # one-time
make build              # generate + build the .saver (Release)
make install            # + copy into ~/Library/Screen Savers
```

Use `make build`, not a hand-written `xcodebuild` — the Makefile carries the
required flags (`-skipMacroValidation` for lyra's macro plugin, plus the
pointfree module-resolution flags). CI (`.github/workflows/release.yml`) uses the
same flags; keep the two in sync.

No unit-test target — display logic is a thin map onto lyra's tested
`WallpaperPresenter`; verify with a manual on-device smoke test.

## Guardrails

- **Never commit directly to `main`** (except the initial scaffold): branch → PR → merge.
- **Bump `version.txt`** in every PR (feat → minor, fix/refactor/chore → patch, breaking → major). CI tags + releases + updates the Homebrew cask from it.
- Don't edit the generated `.xcodeproj`; change `project.yml`.

[GeneralD/lyra#325]: https://github.com/GeneralD/lyra/issues/325
