import AVFoundation
import LyraKit
import ScreenSaver

/// Screen saver that renders lyra's configured video wallpaper.
///
/// Reuses lyra's playback pipeline through `LyraKit` — the same
/// `WallpaperPresenter` the daemon drives — so the saver reads the user's
/// existing `~/.config/lyra/config.toml` `[wallpaper]` set and
/// `~/.cache/lyra/wallpapers/` cache instead of persisting its own
/// `ScreenSaverDefaults` (GeneralD/lyra#325, plan B). Lyrics and overlays are
/// intentionally omitted — this surface only plays the wallpaper.
final class LyraScreenSaverView: ScreenSaverView {
    private let presenter = WallpaperPresenter()
    private let playerLayer = AVPlayerLayer()

    override init?(frame: NSRect, isPreview: Bool) {
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
