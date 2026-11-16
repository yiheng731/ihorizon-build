import UIKit

/// 启动页：游戏已经在下面跑起来，这一层盖在上面。
final class Launcher: UIViewController {

    private static var window: UIWindow?

    static func present() {
        guard window == nil else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        let created = UIWindow(windowScene: scene)
        created.windowLevel = .alert + 1
        created.rootViewController = Launcher()
        created.makeKeyAndVisible()
        window = created
    }

    private func dismiss() {
        hz_launcher_closing()
        Launcher.window?.isHidden = true
        Launcher.window = nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.055, green: 0.043, blue: 0.098, alpha: 1)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let title = UILabel()
        title.text = "ihorizon"
        title.textColor = .white
        title.font = .systemFont(ofSize: 44, weight: .heavy)
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = "我的世界 · Java 版 · Rust 移植"
        subtitle.textColor = UIColor(white: 1, alpha: 0.65)
        subtitle.font = .systemFont(ofSize: 14, weight: .medium)
        subtitle.textAlignment = .center

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        stack.setCustomSpacing(28, after: subtitle)
        stack.addArrangedSubview(button("开始游戏", filled: true) { [weak self] in self?.dismiss() })
        stack.addArrangedSubview(button("导入资源包") { [weak self] in self?.importResources() })
        stack.addArrangedSubview(button("设置") { [weak self] in self?.showSettings() })
        stack.addArrangedSubview(button("关于") { [weak self] in self?.showAbout() })

        let hint = UILabel()
        hint.text = "资源包放在「文件 → 我的 iPhone → ihorizon → ihorizon → 任意 .zip」，下次启动会自动导入。"
        hint.textColor = UIColor(white: 1, alpha: 0.45)
        hint.font = .systemFont(ofSize: 12)
        hint.numberOfLines = 0
        hint.textAlignment = .center
        stack.addArrangedSubview(hint)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),
        ])
    }

    private func button(_ title: String, filled: Bool = false, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.baseForegroundColor = filled ? .black : .white
        configuration.baseBackgroundColor = filled
            ? UIColor(red: 0.80, green: 0.55, blue: 1.0, alpha: 1)
            : UIColor(white: 1, alpha: 0.10)
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
        let control = UIButton(configuration: configuration)
        control.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        control.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return control
    }

    private func importResources() {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.zip, .archive, .folder],
            asCopy: true
        )
        picker.allowsMultipleSelection = false
        picker.delegate = self
        present(picker, animated: true)
    }

    private func showSettings() {
        let alert = UIAlertController(title: "设置", message: "渲染距离与触控布局在游戏内调整。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    private func showAbout() {
        let alert = UIAlertController(
            title: "ihorizon",
            message: "Minecraft: Java Edition 的 Rust 重写版，运行在 iPhone 上。\n不含任何 Mojang 的游戏文件，资源由你自己准备。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

extension Launcher: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let source = urls.first else { return }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let target = documents.appendingPathComponent(source.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.moveItem(at: source, to: target)
            let alert = UIAlertController(
                title: "已放进资源包",
                message: "\(source.lastPathComponent)\n下次启动时自动导入。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
        } catch {
            let alert = UIAlertController(title: "放不进去", message: "\(error)", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
        }
    }
}

@_silgen_name("hz_launcher_closing")
func hz_launcher_closing()
