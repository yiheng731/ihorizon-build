import UIKit

@_silgen_name("hz_run")
func hz_run()

@_silgen_name("hz_input")
func hz_input(_ line: UnsafePointer<CChar>)

enum Bridge {
    static func send(_ line: String) {
        line.withCString { hz_input($0) }
    }
}

NotificationCenter.default.addObserver(
    forName: UIApplication.didFinishLaunchingNotification,
    object: nil,
    queue: .main
) { _ in
    Launcher.present()
}

hz_run()
