import UIKit

final class Launcher: UIViewController {

    private static var window: UIWindow?
    private static let accent = UIColor(red: 0.769, green: 0.522, blue: 1.0, alpha: 1)

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

    private var backdrop: CAGradientLayer?

    override func viewDidLoad() {
        super.viewDidLoad()

        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor(red: 0.10, green: 0.055, blue: 0.18, alpha: 1).cgColor,
            UIColor(red: 0.027, green: 0.016, blue: 0.051, alpha: 1).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0.1, y: 0)
        gradient.endPoint = CGPoint(x: 0.9, y: 1)
        view.layer.addSublayer(gradient)
        backdrop = gradient

        let left = UIStackView()
        left.axis = .vertical
        left.alignment = .leading
        left.spacing = 8

        let eyebrow = UILabel()
        eyebrow.text = "MINECRAFT: JAVA EDITION · RUST"
        eyebrow.font = .systemFont(ofSize: 11, weight: .semibold)
        eyebrow.textColor = UIColor(white: 1, alpha: 0.40)

        let wordmark = UILabel()
        wordmark.text = "ihorizon"
        wordmark.font = .systemFont(ofSize: 40, weight: .black)
        wordmark.textColor = .white

        let tagline = UILabel()
        tagline.text = "手机上的 Java 版"
        tagline.font = .systemFont(ofSize: 13, weight: .medium)
        tagline.textColor = UIColor(white: 1, alpha: 0.57)

        left.addArrangedSubview(eyebrow)
        left.addArrangedSubview(wordmark)
        left.addArrangedSubview(tagline)
        left.setCustomSpacing(18, after: tagline)
        left.addArrangedSubview(accountCard())

        let footer = UILabel()
        footer.text = "2.0 · 不含 Mojang 的游戏文件"
        footer.font = .systemFont(ofSize: 10)
        footer.textColor = UIColor(white: 1, alpha: 0.32)

        let right = UIStackView()
        right.axis = .vertical
        right.alignment = .fill
        right.spacing = 9
        right.addArrangedSubview(primary("开始游戏", symbol: "play.fill") { [weak self] in
            self?.dismiss()
        })
        right.setCustomSpacing(14, after: right.arrangedSubviews.last!)
        right.addArrangedSubview(row("资源包", symbol: "shippingbox") { [weak self] in
            self?.importResources()
        })
        right.addArrangedSubview(row("设置", symbol: "slider.horizontal.3") { [weak self] in
            self?.showSettings()
        })
        right.addArrangedSubview(row("关于", symbol: "info.circle") { [weak self] in
            self?.showAbout()
        })

        let columns = UIStackView(arrangedSubviews: [left, right])
        columns.axis = .horizontal
        columns.alignment = .top
        columns.spacing = 46
        columns.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(columns)

        footer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(footer)

        NSLayoutConstraint.activate([
            columns.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            columns.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 34),
            columns.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -34),

            left.widthAnchor.constraint(equalTo: right.widthAnchor, multiplier: 0.56),

            footer.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 34),
            footer.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdrop?.frame = view.bounds
    }

    private func accountCard() -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(white: 1, alpha: 0.06)
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous

        let avatar = UIView()
        avatar.backgroundColor = Launcher.accent.withAlphaComponent(0.24)
        avatar.layer.cornerRadius = 22
        avatar.translatesAutoresizingMaskIntoConstraints = false

        let mark = UILabel()
        mark.text = "i"
        mark.font = .systemFont(ofSize: 24, weight: .black)
        mark.textColor = Launcher.accent
        mark.translatesAutoresizingMaskIntoConstraints = false
        avatar.addSubview(mark)

        let name = UILabel()
        name.text = "本地玩家"
        name.font = .systemFont(ofSize: 16, weight: .semibold)
        name.textColor = .white

        let status = UILabel()
        status.text = "未登录 · 单人游戏可用"
        status.font = .systemFont(ofSize: 11)
        status.textColor = UIColor(white: 1, alpha: 0.45)

        let lines = UIStackView(arrangedSubviews: [name, status])
        lines.axis = .vertical
        lines.spacing = 2

        let row = UIStackView(arrangedSubviews: [avatar, lines])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 44),
            avatar.heightAnchor.constraint(equalToConstant: 44),
            mark.centerXAnchor.constraint(equalTo: avatar.centerXAnchor),
            mark.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 13),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -13),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
        ])
        return card
    }

    private func primary(_ title: String, symbol: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePadding = 10
        configuration.baseForegroundColor = UIColor(red: 0.05, green: 0.02, blue: 0.08, alpha: 1)
        configuration.baseBackgroundColor = Launcher.accent
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 16, leading: 20, bottom: 16, trailing: 20)
        let control = UIButton(configuration: configuration)
        control.contentHorizontalAlignment = .leading
        control.titleLabel?.font = .systemFont(ofSize: 19, weight: .bold)
        control.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return control
    }

    private func row(_ title: String, symbol: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePadding = 14
        configuration.baseForegroundColor = UIColor(white: 1, alpha: 0.92)
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 14, leading: 18, bottom: 14, trailing: 18)
        let control = UIButton(configuration: configuration)
        control.contentHorizontalAlignment = .leading
        control.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        control.backgroundColor = UIColor(white: 1, alpha: 0.06)
        control.layer.cornerRadius = 14
        control.layer.cornerCurve = .continuous
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
        let alert = UIAlertController(
            title: "设置",
            message: "渲染距离与触控布局在游戏内调整。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    private func showAbout() {
        let alert = UIAlertController(
            title: "ihorizon 2.0",
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
            let alert = UIAlertController(
                title: "放不进去", message: "\(error)", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
        }
    }
}

@_silgen_name("hz_launcher_closing")
func hz_launcher_closing()
