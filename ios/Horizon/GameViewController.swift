import QuartzCore
import UIKit

final class GameViewController: UIViewController {
    private var shell: UnsafeMutableRawPointer?
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var reportedError: String?

    
    
    private let hud = UILabel()
    private var hudTimer: Timer?
    private var lastSampleCount: UInt64 = 0
    private var lastSampleTime: CFTimeInterval = 0

    private var gameView: GameView { view as! GameView }

    override func loadView() {
        view = GameView(frame: .zero)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(willSuspend),
            name: .horizonWillSuspend,
            object: nil
        )

        hud.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        hud.textColor = UIColor(white: 1, alpha: 0.55)
        hud.numberOfLines = 2
        hud.text = "…"
        hud.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hud)
        NSLayoutConstraint.activate([
            hud.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            hud.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
        ])
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        link?.invalidate()
        hudTimer?.invalidate()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        createShellIfNeeded()
        startDisplayLink()
        startHUD()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        link?.invalidate()
        link = nil
        hudTimer?.invalidate()
        hudTimer = nil
        
        
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        createShellIfNeeded()
        guard let shell else { return }
        let size = gameView.drawableSize
        hz_resize(shell, UInt32(size.width), UInt32(size.height))
    }

    

    private func createShellIfNeeded() {
        guard shell == nil, view.window != nil else { return }
        let size = gameView.drawableSize
        guard size.width > 0, size.height > 0 else { return }

        let scale = Float(gameView.contentScaleFactor)
        let layer = Unmanaged.passUnretained(gameView.metalLayer).toOpaque()
        guard let created = hz_create(layer, UInt32(size.width), UInt32(size.height), scale) else {
            reportOnce(errorMessage())
            return
        }
        shell = created
        gameView.shell = created

        let ready = AssetsStore.shared.root.path.withCString { hz_set_assets_root($0) }
        if !ready {
            reportOnce(errorMessage())
        }
    }

    private func errorMessage() -> String {
        guard let pointer = hz_last_error() else { return "未知错误" }
        let message = String(cString: pointer)
        return message.isEmpty ? "未知错误" : message
    }

    
    private func reportOnce(_ message: String) {
        guard reportedError == nil else { return }
        reportedError = message
        let alert = UIAlertController(
            title: "Horizon 启动失败",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    

    private func startDisplayLink() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(step))
        
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        }
        link.add(to: .main, forMode: .common)
        self.link = link
        lastTimestamp = 0
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let shell else { return }
        let dt: CFTimeInterval
        if lastTimestamp == 0 {
            dt = link.duration
        } else {
            dt = link.targetTimestamp - lastTimestamp
        }
        lastTimestamp = link.targetTimestamp
        hz_frame(shell, Float(min(dt, 0.1)))
    }

    
    
    private func startHUD() {
        guard hudTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshHUD()
        }
        RunLoop.main.add(timer, forMode: .common)
        hudTimer = timer
        lastSampleCount = 0
        lastSampleTime = 0
    }

    private func refreshHUD() {
        guard let shell else { return }
        let count = hz_frame_count(shell)
        let now = CACurrentMediaTime()
        var fpsText = "…"
        if lastSampleTime > 0, now > lastSampleTime {
            let fps = Double(count &- lastSampleCount) / (now - lastSampleTime)
            fpsText = String(format: "%.0f FPS", fps)
        }
        lastSampleCount = count
        lastSampleTime = now

        let adapter: String
        if let pointer = hz_adapter_info(shell) {
            adapter = String(cString: pointer)
        } else {
            adapter = "未知 GPU"
        }
        hud.text = "\(fpsText) · 共 \(count) 帧\n\(adapter)"
    }

    @objc private func willSuspend() {
        
    }
}
