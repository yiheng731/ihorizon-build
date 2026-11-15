import Metal
import UIKit

final class GameView: UIView {
    
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
        
        
        metalLayer.framebufferOnly = false
        metalLayer.maximumDrawableCount = 3
        metalLayer.allowsNextDrawableTimeout = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    
    
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
