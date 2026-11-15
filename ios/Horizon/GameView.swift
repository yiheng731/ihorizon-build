import Metal
import UIKit

/// The surface. A `UIView` whose backing layer *is* the `CAMetalLayer` wgpu
/// draws into, so there is no extra view or sublayer to keep in sync.
final class GameView: UIView {
    /// Set by `GameViewController` once the shell exists.
    var shell: UnsafeMutableRawPointer?

    override class var layerClass: AnyClass { CAMetalLayer.self }

    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isOpaque = true
        backgroundColor = .black
        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm
        // wgpu may present with MSAA resolve or a blit, so the drawable cannot be
        // framebuffer-only. Costs a little bandwidth, buys correctness.
        metalLayer.framebufferOnly = false
        metalLayer.maximumDrawableCount = 3
        metalLayer.allowsNextDrawableTimeout = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Drawable size in pixels. UIKit keeps the layer's bounds in points; the
    /// drawable must be pixels or the game renders at 1/3 resolution on a phone.
    var drawableSize: CGSize {
        let scale = contentScaleFactor
        return CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        metalLayer.contentsScale = contentScaleFactor
        guard let shell, bounds.width > 0, bounds.height > 0 else { return }
        let size = drawableSize
        hz_resize(shell, UInt32(size.width), UInt32(size.height))
    }

    // MARK: - touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        forward(touches, phase: 0)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        forward(touches, phase: 1)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        forward(touches, phase: 2)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        forward(touches, phase: 3)
    }

    /// Raw points go straight to Rust in pixels. The mapping to Horizon's input
    /// actions (virtual stick, look drag, break, place) belongs on that side,
    /// next to `crates/horizon-client-input/src/actions.rs`, not in UIKit.
    private func forward(_ touches: Set<UITouch>, phase: UInt32) {
        guard let shell else { return }
        let scale = Float(contentScaleFactor)
        for touch in touches {
            let point = touch.location(in: self)
            let id = UInt32(truncatingIfNeeded: touch.hashValue)
            hz_touch(shell, id, phase, Float(point.x) * scale, Float(point.y) * scale)
        }
    }
}
