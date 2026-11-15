import UIKit
import UniformTypeIdentifiers

/// Plan B's first screen: the ipa ships without Mojang's assets, so the player
/// brings their own. One pick, one copy, then the game.
///
/// The desktop side of this is `scripts/prepare_assets.ps1|sh`, which runs
/// `horizon-prepare` against the player's own 26.3 `server.jar` and writes
/// `horizon-assets.zip`. Nothing Mojang-made is redistributed by this app.
final class ImportViewController: UIViewController, UIDocumentPickerDelegate {
    var onReady: (() -> Void)?

    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let statusLabel = UILabel()
    private let folderButton = UIButton(type: .system)
    private let zipButton = UIButton(type: .system)
    private let startButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1)

        titleLabel.text = "导入游戏数据"
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center

        bodyLabel.text = """
        Horizon 需要一个资源目录：从你自己的 Minecraft 26.3 里用 horizon-prepare 抽出来的 assets/ 与 data/。

        选一个包含 assets/ 和 data/ 的文件夹，或者那个目录打成的 zip。
        """
        bodyLabel.numberOfLines = 0
        bodyLabel.font = .systemFont(ofSize: 15)
        bodyLabel.textColor = UIColor(white: 0.78, alpha: 1)
        bodyLabel.textAlignment = .center

        statusLabel.numberOfLines = 0
        statusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        statusLabel.textColor = UIColor(white: 0.55, alpha: 1)
        statusLabel.textAlignment = .center
        statusLabel.text = "状态：等待导入"

        configure(folderButton, title: "导入文件夹", primary: true)
        folderButton.addTarget(self, action: #selector(pickFolder), for: .touchUpInside)

        configure(zipButton, title: "导入 zip", primary: false)
        zipButton.addTarget(self, action: #selector(pickZip), for: .touchUpInside)

        configure(startButton, title: "开始游戏", primary: true)
        startButton.addTarget(self, action: #selector(start), for: .touchUpInside)
        startButton.isHidden = true

        spinner.color = .white
        spinner.hidesWhenStopped = true

        let stack = UIStackView(arrangedSubviews: [
            titleLabel, bodyLabel, folderButton, zipButton, statusLabel, spinner, startButton,
        ])
        stack.axis = .vertical
        stack.spacing = 18
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28),
            folderButton.heightAnchor.constraint(equalToConstant: 50),
            zipButton.heightAnchor.constraint(equalToConstant: 50),
            startButton.heightAnchor.constraint(equalToConstant: 50),
        ])

        if AssetsStore.shared.isReady {
            statusLabel.text = "状态：数据已就绪"
            startButton.isHidden = false
        }
    }

    private func configure(_ button: UIButton, title: String, primary: Bool) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.layer.cornerRadius = 12
        button.layer.cornerCurve = .continuous
        if primary {
            button.backgroundColor = UIColor(red: 0.36, green: 0.72, blue: 0.45, alpha: 1)
            button.setTitleColor(.black, for: .normal)
        } else {
            button.backgroundColor = UIColor(white: 0.16, alpha: 1)
            button.setTitleColor(.white, for: .normal)
        }
    }

    // MARK: - picking

    @objc private func pickFolder() {
        // asCopy 必须为 false：给 .folder 传 true，iOS 会直接抛异常闪退。
        // 安全作用域访问已经在 AssetsStore.install 里用 startAccessingSecurityScopedResource 处理了。
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    @objc private func pickZip() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.zip], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        install(from: url)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        statusLabel.text = "状态：已取消"
    }

    // MARK: - install

    private func install(from url: URL) {
        setBusy(true, message: "状态：正在导入…（1GB 级数据可能要一两分钟）")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try AssetsStore.shared.install(from: url)
                DispatchQueue.main.async { [weak self] in
                    self?.setBusy(false, message: "状态：数据已就绪")
                    self?.startButton.isHidden = false
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.setBusy(false, message: "状态：导入失败 — \(error.localizedDescription)")
                }
            }
        }
    }

    private func setBusy(_ busy: Bool, message: String) {
        folderButton.isEnabled = !busy
        zipButton.isEnabled = !busy
        startButton.isEnabled = !busy
        statusLabel.text = message
        if busy { spinner.startAnimating() } else { spinner.stopAnimating() }
    }

    @objc private func start() {
        onReady?()
    }
}
