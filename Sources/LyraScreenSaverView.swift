import AVFoundation
import Darwin
import Foundation
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

    /// Guards `startPresenting()` / `stopPresenting()` so the presenter is
    /// started and torn down at most once per cycle. `legacyScreenSaver` can
    /// deliver overlapping lifecycle callbacks, and our `viewDidMoveToWindow`
    /// fallback races `stopAnimation()`, so both transitions must be idempotent.
    private var isPresenting = false

    override init?(frame: NSRect, isPreview: Bool) {
        Self.redirectXDGToRealHome()
        super.init(frame: frame, isPreview: isPreview)
        configureLayerHierarchy()
        // Presenter binding is deferred to startPresenting() so it re-subscribes
        // on every start (stop() clears the presenter's subscriptions), keeping
        // resume after a fallback teardown working.
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func startAnimation() {
        super.startAnimation()
        startPresenting()
    }

    override func stopAnimation() {
        stopPresenting(trigger: "stopAnimation")
        super.stopAnimation()
    }

    /// `legacyScreenSaver` frequently keeps the view alive on dismissal without
    /// calling `stopAnimation()`, leaving the presenter (and its video decoder)
    /// running indefinitely — the root cause of issue #2. Detaching from the
    /// window is the reliable dismissal signal, so tear down here as a fallback.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window == nil else {
            Self.log.info("viewDidMoveToWindow: window attached")
            return
        }
        stopPresenting(trigger: "viewDidMoveToWindow")
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
    /// Idempotent start: (re)subscribe the presenter callbacks and begin
    /// playback. Safe to call repeatedly — the `isPresenting` guard collapses
    /// duplicate host callbacks, and rebinding is required because a prior
    /// `stopPresenting()` cleared the presenter's subscriptions.
    func startPresenting() {
        guard !isPresenting else { return }
        isPresenting = true
        Self.log.info("startPresenting: binding + starting presenter")
        bindPresenter()
        presenter.start()
    }

    /// Idempotent teardown. Beyond stopping the presenter (which nils out its
    /// own AVPlayer), detach the player from the layer: the layer holds the only
    /// remaining strong reference to the presenter's AVPlayer, so without this
    /// the instance — and its warm video decoder — survives the stop (issue #2).
    func stopPresenting(trigger: String) {
        guard isPresenting else { return }
        isPresenting = false
        Self.log.info("stopPresenting(\(trigger, privacy: .public)): stopping presenter + detaching player layer")
        presenter.stop()
        playerLayer.player = nil
    }

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
            // Log only the cache filename, never the full ~/.cache path (username PII).
            let item = (player.currentItem?.asset as? AVURLAsset)?.url.lastPathComponent ?? "(no item yet)"
            Self.log.info("player available; item=\(item, privacy: .public)")
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
        // overwrite=0: only synthesize the real-home default when the var is
        // unset. If the user exported XDG_CONFIG_HOME / XDG_CACHE_HOME into the
        // GUI session, lyra reads those first — respect them rather than
        // clobbering with ~/.config, which would make the saver ignore the very
        // config lyra is using (and could leave the screen black).
        setenv("XDG_CONFIG_HOME", realHome + "/.config", 0)
        setenv("XDG_CACHE_HOME", realHome + "/.cache", 0)
        // The resolved path carries the username; log only that the redirect ran.
        log.info("real home resolved via getpwuid; XDG redirect applied")
        probeReadability()
    }

    /// One-shot sandbox read probe against the EFFECTIVE XDG locations lyra will
    /// use — the real-home defaults, or the user's exported overrides. If the
    /// config or cache is not readable from inside the saver's sandbox, the
    /// screen stays black no matter how paths resolve — the fix then needs a
    /// sandbox entitlement, not just the XDG redirect above. These log lines make
    /// that verdict visible in Console.app / `log show --predicate
    /// 'subsystem == "com.generald.lyra-screensaver"'`. Log only non-PII facts
    /// (readable? size?) — never the username-bearing path.
    static func probeReadability() {
        // Actually read the config (~1.4 KB): a real read is the authoritative
        // test of whether the sandbox permits reads at lyra's config location —
        // access()-style checks don't exercise the sandbox read path, and it's
        // tiny so the cost is negligible.
        if let configHome = getenv("XDG_CONFIG_HOME").map({ String(cString: $0) }) {
            let config = configHome + "/lyra/config.toml"
            if let data = FileManager.default.contents(atPath: config) {
                log.info("config readable: \(data.count, privacy: .public) bytes")
            } else {
                log.error("config NOT readable (XDG_CONFIG_HOME/lyra/config.toml) — sandbox deny or missing")
            }
        }
        // The cache holds a large mp4; check readability without reading it or
        // enumerating the directory. The config read above is the primary verdict.
        if let cacheHome = getenv("XDG_CACHE_HOME").map({ String(cString: $0) }) {
            let cache = cacheHome + "/lyra/wallpapers"
            if FileManager.default.isReadableFile(atPath: cache) {
                log.info("wallpaper cache readable")
            } else {
                log.error("wallpaper cache NOT readable (XDG_CACHE_HOME/lyra/wallpapers) — sandbox deny or missing")
            }
        }
    }
}
