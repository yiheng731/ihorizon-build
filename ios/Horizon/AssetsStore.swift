import Foundation

/// The one place that knows where game data lives inside the iOS container.
///
/// There is no `~/.minecraft` in an app sandbox, and no JDK to run
/// `horizon-prepare` on the device. So the data arrives as a directory the
/// player picks once (or as a zip this class unpacks), and everything under
/// `Application Support/horizon` is what the desktop `--prepare` step produced:
///
///   Application Support/horizon/assets/   textures, sounds, languages, fonts
///   Application Support/horizon/data/     recipes, loot tables, tags, dimensions
///
/// Plan B (small ipa): these two directories are *not* in the bundle; the player
/// imports them on first launch. Plan A (fat ipa) would put them in
/// `Bundle.main.resourceURL` and this class would point there instead.
final class AssetsStore {
    static let shared = AssetsStore()

    /// `…/Library/Application Support/horizon` — survives app updates, excluded
    /// from iCloud backup because it is re-importable.
    let root: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appendingPathComponent("horizon", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = root
        try? mutable.setResourceValues(values)
    }

    /// 0 = ready, 1 = root missing, 2 = assets/ missing, 3 = data/ missing.
    /// Delegated to Rust so Swift and the game can never disagree.
    var state: Int32 {
        root.path.withCString { hz_assets_state($0) }
    }

    var isReady: Bool { state == 0 }

    var isEmpty: Bool { state != 0 }

    /// Installs a player-picked folder or zip. Both paths end in the same shape:
    /// `root/assets` and `root/data` exist and are non-empty.
    func install(from picked: URL) throws {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }

        if picked.pathExtension.lowercased() == "zip" {
            try unzip(picked)
        } else {
            try flatten(picked)
        }

        guard state == 0 else {
            throw AssetsError.incompleteLayout(state: state)
        }
    }

    /// Copies assets/ and data/ out of the picked folder, whether the player
    /// picked the `.local` directory itself or one wrapping it.
    private func flatten(_ picked: URL) throws {
        let fm = FileManager.default
        guard let inner = Self.findPayloadRoot(picked) else {
            throw AssetsError.noPayload
        }
        for name in ["assets", "data"] {
            let source = inner.appendingPathComponent(name, isDirectory: true)
            let destination = root.appendingPathComponent(name, isDirectory: true)
            guard fm.fileExists(atPath: source.path) else { throw AssetsError.noPayload }
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: source, to: destination)
        }
    }

    /// A prepared tree may be `<picked>/assets`, `<picked>/.local/assets`, or
    /// `<picked>/horizon/assets` depending on how the player zipped it.
    private static func findPayloadRoot(_ url: URL, depth: Int = 0) -> URL? {
        guard depth < 4 else { return nil }
        let fm = FileManager.default
        if fm.fileExists(atPath: url.appendingPathComponent("assets").path),
           fm.fileExists(atPath: url.appendingPathComponent("data").path) {
            return url
        }
        let children = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for child in children {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: child.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            if let found = findPayloadRoot(child, depth: depth + 1) { return found }
        }
        return nil
    }

    private func unzip(_ archive: URL) throws {
        let zip = try ZipArchive(url: archive)
        let fm = FileManager.default
        // Unpack into a scratch directory first: a half-extracted tree must never
        // look "ready" to the gate screen.
        let scratch = root.appendingPathComponent(".incoming", isDirectory: true)
        if fm.fileExists(atPath: scratch.path) { try fm.removeItem(at: scratch) }
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        try zip.extract(to: scratch)
        guard let inner = Self.findPayloadRoot(scratch) else { throw AssetsError.noPayload }
        for name in ["assets", "data"] {
            let source = inner.appendingPathComponent(name, isDirectory: true)
            let destination = root.appendingPathComponent(name, isDirectory: true)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: source, to: destination)
        }
        try? fm.removeItem(at: scratch)
    }
}

enum AssetsError: LocalizedError {
    case noPayload
    case incompleteLayout(state: Int32)

    var errorDescription: String? {
        switch self {
        case .noPayload:
            return String(
                localized: "没有找到 assets/ 和 data/。请导入 horizon-prepare 产出的 .local 目录，或它打包成的 zip。"
            )
        case .incompleteLayout(let state):
            switch state {
            case 2: return String(localized: "导入后缺少 assets/ 目录。")
            case 3: return String(localized: "导入后缺少 data/ 目录。")
            default: return String(localized: "导入的目录不完整。")
            }
        }
    }
}
