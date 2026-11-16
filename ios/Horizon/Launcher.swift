import UIKit

final class Launcher: UIViewController {

    private static var window: UIWindow?
    private static let accent = UIColor(red: 0.72, green: 0.45, blue: 1.0, alpha: 1)

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

        let backdrop = CAGradientLayer()
        backdrop.colors = [
            UIColor(red: 0.09, green: 0.05, blue: 0.16, alpha: 1).cgColor,
            UIColor(red: 0.03, green: 0.02, blue: 0.05, alpha: 1).cgColor,
        ]
        backdrop.startPoint = CGPoint(x: 0.1, y: 0)
        backdrop.endPoint = CGPoint(x: 0.9, y: 1)
        backdrop.frame = UIScreen.main.bounds
        view.layer.addSublayer(backdrop)
        self.backdrop = backdrop

        let page = UIScrollView()
        page.translatesAutoresizingMaskIntoConstraints = false
        page.showsVerticalScrollIndicator = false
        view.addSubview(page)

        let column = UIStackView()
        column.axis = .vertical
        column.spacing = 10
        column.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(column)

        let eyebrow = UILabel()
        eyebrow.text = "MINECRAFT: JAVA EDITION · RUST"
        eyebrow.font = .systemFont(ofSize: 11, weight: .semibold)
        eyebrow.textColor = UIColor(white: 1, alpha: 0.38)
        eyebrow.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let wordmark = UILabel()
        wordmark.text = "ihorizon"
        wordmark.font = .systemFont(ofSize: 46, weight: .black)
        wordmark.textColor = .white

        let tagline = UILabel()
        tagline.text = "手机上的 Java 版"
        tagline.font = .systemFont(ofSize: 14, weight: .medium)
        tagline.textColor = UIColor(white: 1, alpha: 0.55)

        column.addArrangedSubview(eyebrow)
        column.addArrangedSubview(wordmark)
        column.addArrangedSubview(tagline)
        column.setCustomSpacing(26, after: tagline)

        column.addArrangedSubview(accountCard())
        column.setCustomSpacing(22, after: column.arrangedSubviews.last!)

        column.addArrangedSubview(primary("开始游戏", symbol: "play.fill") { [weak self] in self?.dismiss() })
        column.setCustomSpacing(14, after: column.arrangedSubviews.last!)

        column.addArrangedSubview(row("资源包", symbol: "shippingbox") { [weak self] in
            self?.importResources()
        })
        column.addArrangedSubview(row("设置", symbol: "slider.horizontal.3") { [weak self] in
            self?.showSettings()
        })
        column.addArrangedSubview(row("关于", symbol: "info.circle") { [weak self] in
            self?.showAbout()
        })

        let footer = UILabel()
        footer.text = "2.0 · 不含 Mojang 的游戏文件"
        footer.font = .systemFont(ofSize: 11, weight: .regular)
        footer.textColor = UIColor(white: 1, alpha: 0.30)
        column.setCustomSpacing(26, after: column.arrangedSubviews.last!)
        column.addArrangedSubview(footer)

        NSLayoutConstraint.activate([
            page.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            page.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            page.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            column.topAnchor.constraint(equalTo: page.topAnchor, constant: 28),
            column.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -28),
            column.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 34),
            column.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -34),
        ])
    }

    private var backdrop: CAGradientLayer?

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
        avatar.backgroundColor = Launcher.accent.withAlphaComponent(0.22)
        avatar.layer.cornerRadius = 21
        avatar.translatesAutoresizingMaskIntoConstraints = false

        let head = UILabel()
        head.text = "i"
        head.font = .systemFont(ofSize: 22, weight: .black)
        head.textColor = Launcher.accent
        head.translatesAutoresizingMaskIntoConstraints = false
        avatar.addSubview(head)

        let name = UILabel()
        name.text = "本地玩家"
        name.font = .systemFont(ofSize: 16, weight: .semibold)
        name.textColor = .white

        let status = UILabel()
        status.text = "未登录 · 单人游戏可用"
        status.font = .systemFont(ofSize: 12)
        status.textColor = UIColor(white: 1, alpha: 0.45)

        let lines = UIStackView(arrangedSubviews: [name, status])
        lines.axis = .vertical
        lines.spacing = 2

        let row = UIStackView(arrangedSubviews: [avatar, lines])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 42),
            avatar.heightAnchor.constraint(equalToConstant: 42),
            head.centerXAnchor.constraint(equalTo: avatar.centerXAnchor),
            head.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
        ])
        return card
    }

    private func primary(_ title: String, symbol: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePadding = 10
        configuration.baseForegroundColor = .black
        configuration.baseBackgroundColor = Launcher.accent
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 18, leading: 22, bottom: 18, trailing: 22)
        let control = UIButton(configuration: configuration)
        control.titleLabel?.font = .systemFont(ofSize: 19, weight: .bold)
        control.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return control
    }

    private func row(_ title: String, symbol: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePadding = 14
        configuration.baseForegroundColor = .white
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 16, leading: 18, bottom: 16, trailing: 18)
        let control = UIButton(configuration: configuration)
        control.contentHorizontalAlignment = .leading
        control.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
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
            let alert = UIAlertController(title: "放不进去", message: "\(error)", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
        }
    }
}

@_silgen_name("hz_launcher_closing")
func hz_launcher_closing()
