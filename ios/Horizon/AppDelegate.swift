import UIKit

/// The whole app is one window, one view controller. UIKit owns the view and the
/// display link; Rust owns the GPU work. There is no `winit` here on purpose:
/// its UIKit backend would fight us for the event loop and give nothing back.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.backgroundColor = .black
        window.rootViewController = RootViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // TODO(port): ask the game to flush the world before iOS suspends us.
        // jetsam kills suspended games without warning; a lost chunk is a lost base.
        NotificationCenter.default.post(name: .horizonWillSuspend, object: nil)
    }
}

extension Notification.Name {
    static let horizonWillSuspend = Notification.Name("HorizonWillSuspend")
}

/// Shows the import screen until assets are in place, then swaps in the game.
final class RootViewController: UIViewController {
    private var game: GameViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        if AssetsStore.shared.isReady {
            showGame()
        } else {
            showImport()
        }
    }

    private func showImport() {
        let importer = ImportViewController()
        importer.onReady = { [weak self] in self?.showGame() }
        addChild(importer)
        importer.view.frame = view.bounds
        importer.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(importer.view)
        importer.didMove(toParent: self)
    }

    private func showGame() {
        guard game == nil else { return }
        view.subviews.forEach { $0.removeFromSuperview() }
        let game = GameViewController()
        addChild(game)
        game.view.frame = view.bounds
        game.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(game.view)
        game.didMove(toParent: self)
        self.game = game
    }
}
