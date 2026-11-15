import Compression
import Foundation

/// Minimal, dependency-free ZIP reader: enough for the `horizon-assets.zip` that
/// `scripts/prepare_assets` produces (stored + deflate, no encryption, no zip64).
///
/// iOS has no `/usr/bin/unzip` and `Foundation` still has no archive API, so the
/// choice is a 30 MB Swift library or these 180 lines. Deflate comes from
/// `libcompression`, which is part of the system.
struct ZipEntry {
    let name: String
    let method: UInt16
    let compressedSize: Int
    let uncompressedSize: Int
    let localHeaderOffset: Int
}

enum ZipError: LocalizedError {
    case tooSmall
    case noEndOfCentralDirectory
    case corrupt(String)
    case zip64Unsupported
    case encryptedUnsupported
    case methodUnsupported(UInt16)
    case inflateFailed(String)
    case unsafePath(String)

    var errorDescription: String? {
        switch self {
        case .tooSmall: return "文件太小，不是 zip"
        case .noEndOfCentralDirectory: return "找不到 zip 中央目录"
        case .corrupt(let detail): return "zip 结构损坏：\(detail)"
        case .zip64Unsupported: return "不支持 zip64 归档，请用 4GB 以下的分卷重打"
        case .encryptedUnsupported: return "不支持加密的 zip"
        case .methodUnsupported(let method): return "不支持的压缩方式 \(method)"
        case .inflateFailed(let detail): return "解压失败：\(detail)"
        case .unsafePath(let name): return "压缩包里有可疑路径：\(name)"
        }
    }
}

final class ZipArchive {
    private let data: Data

    init(url: URL) throws {
        data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count > 22 else { throw ZipError.tooSmall }
    }

    // MARK: little-endian reads

    private func u16(_ offset: Int) -> UInt16 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
    }

    private func u32(_ offset: Int) -> UInt32 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
    }

    // MARK: directory

    func entries() throws -> [ZipEntry] {
        let eocd = try endOfCentralDirectory()
        let count = Int(u16(eocd + 10))
        var cursor = Int(u32(eocd + 16))
        var result: [ZipEntry] = []
        result.reserveCapacity(count)

        for _ in 0..<count {
            guard cursor + 46 <= data.count, u32(cursor) == 0x0201_4b50 else {
                throw ZipError.corrupt("中央目录条目签名错误 @\(cursor)")
            }
            let flags = u16(cursor + 8)
            let method = u16(cursor + 10)
            let compressedSize = Int(u32(cursor + 20))
            let uncompressedSize = Int(u32(cursor + 24))
            let nameLength = Int(u16(cursor + 28))
            let extraLength = Int(u16(cursor + 30))
            let commentLength = Int(u16(cursor + 32))
            let localOffset = Int(u32(cursor + 42))

            guard flags & 0x0001 == 0 else { throw ZipError.encryptedUnsupported }
            guard compressedSize != 0xFFFF_FFFF, uncompressedSize != 0xFFFF_FFFF, localOffset != 0xFFFF_FFFF else {
                throw ZipError.zip64Unsupported
            }

            let nameStart = cursor + 46
            guard nameStart + nameLength <= data.count else {
                throw ZipError.corrupt("文件名越界")
            }
            let nameData = data.subdata(in: nameStart..<(nameStart + nameLength))
            let name = String(data: nameData, encoding: .utf8) ?? ""

            result.append(
                ZipEntry(
                    name: name,
                    method: method,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localOffset
                )
            )
            cursor = nameStart + nameLength + extraLength + commentLength
        }
        return result
    }

    private func endOfCentralDirectory() throws -> Int {
        // The record is 22 bytes plus a comment of up to 64 KiB.
        let lowerBound = max(0, data.count - 22 - 65_535)
        var offset = data.count - 22
        while offset >= lowerBound {
            if data.withUnsafeBytes({ $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }) == 0x0605_4b50 {
                return offset
            }
            offset -= 1
        }
        throw ZipError.noEndOfCentralDirectory
    }

    // MARK: extraction

    func extract(to destination: URL) throws {
        let fm = FileManager.default
        for entry in try entries() {
            let path = try safePath(entry.name, under: destination)
            if entry.name.hasSuffix("/") {
                try fm.createDirectory(at: path, withIntermediateDirectories: true)
                continue
            }
            try fm.createDirectory(
                at: path.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let payload = try payload(for: entry)
            try payload.write(to: path, options: .atomic)
        }
    }

    private func payload(for entry: ZipEntry) throws -> Data {
        let local = entry.localHeaderOffset
        guard local + 30 <= data.count, u32(local) == 0x0403_4b50 else {
            throw ZipError.corrupt("本地头签名错误：\(entry.name)")
        }
        let nameLength = Int(u16(local + 26))
        let extraLength = Int(u16(local + 28))
        let start = local + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard end <= data.count else { throw ZipError.corrupt("数据越界：\(entry.name)") }
        let raw = data.subdata(in: start..<end)

        switch entry.method {
        case 0:
            return raw
        case 8:
            return try inflate(raw, expectedSize: entry.uncompressedSize, name: entry.name)
        default:
            throw ZipError.methodUnsupported(entry.method)
        }
    }

    /// `COMPRESSION_ZLIB` in Apple's `Compression` framework is raw DEFLATE —
    /// which is exactly what ZIP method 8 stores (no zlib header, no gzip wrapper).
    private func inflate(_ input: Data, expectedSize: Int, name: String) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return input.withUnsafeBytes { source -> Int in
                guard let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    destinationBase, expectedSize,
                    sourceBase, input.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == expectedSize else {
            throw ZipError.inflateFailed("\(name)：期望 \(expectedSize) 字节，得到 \(written)")
        }
        return output
    }

    /// Refuses absolute paths, drive letters and `..`, so an archive can never
    /// write outside the container.
    private func safePath(_ name: String, under root: URL) throws -> URL {
        guard !name.hasPrefix("/"), !name.contains(".."), !name.contains(":") else {
            throw ZipError.unsafePath(name)
        }
        return root.appendingPathComponent(name)
    }
}
