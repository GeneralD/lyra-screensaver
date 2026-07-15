import AVFoundation
import LyraKit
import ScreenSaver
import os

/// Screen saver that renders lyra's configured video wallpaper.
///
/// Reuses lyra's playback pipeline through `LyraKit` — the same
/// `WallpaperPresenter` the daemon drives — so the saver reads the user's
/// existing `~/.config/lyra/config.toml` `[wallpaper]` set and
/// `~/.cache/lyra/wallpapers/` cache instead of persisting its own
/// `ScreenSaverDefaults` (GeneralD/lyra#325, plan B). Lyrics and overlays are
/// intentionally omitted — this surface only plays the wallpaper.
final class LyraScreenSaverView: ScreenSaverView {
    private static let log = Logger(subsystem: "com.generald.lyra-screensaver", category: "saver")

    /// Constructed lazily so `redirectXDGToRealHome()` runs first: the
    /// `legacyScreenSaver` host runs us sandboxed under a redirected HOME, so
    /// lyra's `NSHomeDirectory()` fallback would resolve config/cache inside the
    /// empty container. The presenter (and its config lookup) must not exist
    /// until the XDG env vars point at the real home.
    private lazy var presenter = WallpaperPresenter()
    private let playerLayer = AVPlayerLayer()

    override init?(frame: NSRect, isPreview: Bool) {
        Self.redirectXDGToRealHome()
        super.init(frame: frame, isPreview: isPreview)
        configureLayerHierarchy()
        bindPresenter()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func startAnimation() {
        super.startAnimation()
        Self.log.info("startAnimation: starting presenter")
        presenter.start()
    }

    override func stopAnimation() {
        presenter.stop()
        super.stopAnimation()
    }

    override func layout() {
        super.layout()
        reassertPlayerLayerGeometry()
    }

    // lyra owns wallpaper configuration; the saver has no settings sheet.
    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
}

private extension LyraScreenSaverView {
    func configureLayerHierarchy() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspectFill
        reassertPlayerLayerGeometry()
        layer?.addSublayer(playerLayer)
    }

    /// Mirrors lyra's `AppWindow`: register once, attach the stable `AVPlayer`
    /// instance the presenter keeps across item swaps, and track per-item zoom.
    func bindPresenter() {
        presenter.onPlayerAvailable { [weak self] player in
            let url = (player.currentItem?.asset as? AVURLAsset)?.url.path ?? "(no item yet)"
            Self.log.info("player available; currentItem=\(url, privacy: .public)")
            self?.playerLayer.player = player
        }
        presenter.onWallpaperScaleChange { [weak self] scale in
            self?.applyWallpaperScale(scale)
        }
    }

    /// The layer carries the wallpaper-scale affine transform, so `frame` is
    /// undefined — drive `bounds` + `position` like lyra's `reassertGeometry`.
    func reassertPlayerLayerGeometry() {
        playerLayer.bounds = bounds
        playerLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    func applyWallpaperScale(_ scale: Double) {
        let sanitized = scale.isFinite ? max(1.0, scale) : 1.0
        playerLayer.setAffineTransform(CGAffineTransform(scaleX: sanitized, y: sanitized))
    }
}

private extension LyraScreenSaverView {
    /// Point lyra's XDG lookup at the user's real home.
    ///
    /// Under `legacyScreenSaver` we run sandboxed with a redirected HOME, so
    /// `NSHomeDirectory()` (lyra's fallback) returns the container's Data dir,
    /// which has no `.config/lyra` or `.cache/lyra`. `getpwuid` reads the real
    /// passwd entry and still returns `/Users/<name>`, so resolve the real home
    /// there and export `XDG_CONFIG_HOME` / `XDG_CACHE_HOME`, which lyra honours
    /// ahead of its `NSHomeDirectory()` fallback.
    static func redirectXDGToRealHome() {
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else {
            log.error("getpwuid failed; cannot resolve real home for XDG redirect")
            return
        }
        let realHome = String(cString: dir)
        setenv("XDG_CONFIG_HOME", realHome + "/.config", 1)
        setenv("XDG_CACHE_HOME", realHome + "/.cache", 1)
        log.info("real home resolved: \(realHome, privacy: .public)")
        probeReadability(realHome: realHome)
    }

    /// One-shot sandbox read probe. If the config file or wallpaper cache is not
    /// readable from inside the saver's sandbox, the screen stays black no matter
    /// how paths resolve — the fix then needs a sandbox entitlement, not just the
    /// XDG redirect above. These log lines make that verdict visible in
    /// Console.app / `log show --predicate 'subsystem == "com.generald.lyra-screensaver"'`.
    static func probeReadability(realHome: String) {
        let config = realHome + "/.config/lyra/config.toml"
        if let data = FileManager.default.contents(atPath: config) {
            log.info("config readable: \(data.count, privacy: .public) bytes")
        } else {
            log.error("config NOT readable at \(config, privacy: .public) — sandbox deny or missing")
        }
        let cache = realHome + "/.cache/lyra/wallpapers"
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: cache) {
            log.info("wallpaper cache readable: \(entries.count, privacy: .public) entries")
        } else {
            log.error("wallpaper cache NOT readable at \(cache, privacy: .public) — sandbox deny or missing")
        }
    }
}
