import Compression
import Foundation

/// A read-only zip reader, just enough to open a `.filbox`.
///
/// iOS has no public unzip, and the alternative to ~200 lines here is a third-party dependency in a
/// shipped app. Writing goes the other way: `NSFileCoordinator`'s `.forUploading` option already
/// produces a zip for free, so only reading needed code.
///
/// Zip stays the container (rather than AppleArchive, which iOS *can* read natively) because the
/// `readable/` layer only earns its place if someone can double-click the backup on a Mac years from
/// now and find Markdown. An archive format only Fil can open would defeat the point of writing it.
struct FilBoxArchive {
    struct Entry {
        let path: String
        let compressedSize: Int
        let uncompressedSize: Int
        let method: UInt16
        let localHeaderOffset: Int
    }

    private let data: Data
    private(set) var entries: [String: Entry] = [:]

    /// Memory-maps rather than reads: a backup with a couple of years of voice and photos in it runs
    /// to hundreds of MB, and only the entries actually asked for should ever be resident.
    init(url: URL) throws {
        guard let mapped = try? Data(contentsOf: url, options: .mappedIfSafe), mapped.count > 22 else {
            throw FilBoxError.notAnArchive
        }
        self.data = mapped
        self.entries = try Self.readCentralDirectory(data: mapped)
    }

    var paths: [String] { Array(entries.keys) }

    /// Bytes for one entry, inflated if needed. Returns nil when the entry isn't in the archive, so a
    /// missing attachment can be skipped rather than failing the whole import.
    func data(for path: String) -> Data? {
        guard let entry = entries[path] else { return nil }
        guard let payload = localPayload(for: entry) else { return nil }

        switch entry.method {
        case 0:
            return payload
        case 8:
            return Self.inflate(payload, expectedSize: entry.uncompressedSize)
        default:
            return nil
        }
    }

    func decode<T: Decodable>(_ type: T.Type, at path: String) throws -> T? {
        guard let bytes = data(for: path) else { return nil }
        return try FilBoxFormat.decoder.decode(type, from: bytes)
    }

    // MARK: - Local headers

    /// The central directory records where a local header starts, but the payload sits past a
    /// variable-length name and extra field that only the local header knows the size of.
    private func localPayload(for entry: Entry) -> Data? {
        let base = entry.localHeaderOffset
        guard base + 30 <= data.count, read32(base) == 0x0403_4b50 else { return nil }
        let nameLength = Int(read16(base + 26))
        let extraLength = Int(read16(base + 28))
        let start = base + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard end <= data.count else { return nil }
        return data.subdata(in: start..<end)
    }

    private static func inflate(_ payload: Data, expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return Data() }
        var out = Data(count: expectedSize)
        let written = out.withUnsafeMutableBytes { dst -> Int in
            payload.withUnsafeBytes { src -> Int in
                guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress,
                      let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                // COMPRESSION_ZLIB is raw DEFLATE in Apple's implementation, which is what zip stores.
                return compression_decode_buffer(
                    dstBase, expectedSize, srcBase, payload.count, nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == expectedSize else { return nil }
        return out
    }

    // MARK: - Central directory

    private static func readCentralDirectory(data: Data) throws -> [String: Entry] {
        guard let eocd = findEOCD(in: data) else { throw FilBoxError.notAnArchive }

        var count = Int(read16(data, eocd + 10))
        var directoryOffset = Int(read32(data, eocd + 16))

        // Zip64: the 32-bit fields saturate, and the real values live in a separate record. A library
        // with years of media in it can cross 4 GB, so this is a real case, not a theoretical one.
        if count == 0xFFFF || directoryOffset == 0xFFFF_FFFF {
            guard let zip64 = findZip64EOCD(in: data, eocd: eocd) else { throw FilBoxError.notAnArchive }
            count = Int(read64(data, zip64 + 32))
            directoryOffset = Int(read64(data, zip64 + 48))
        }

        var entries: [String: Entry] = [:]
        var cursor = directoryOffset
        for _ in 0..<count {
            guard cursor + 46 <= data.count, read32(data, cursor) == 0x0201_4b50 else { break }

            let method = read16(data, cursor + 10)
            var compressed = Int(read32(data, cursor + 20))
            var uncompressed = Int(read32(data, cursor + 24))
            let nameLength = Int(read16(data, cursor + 28))
            let extraLength = Int(read16(data, cursor + 30))
            let commentLength = Int(read16(data, cursor + 32))
            var localOffset = Int(read32(data, cursor + 42))

            let nameStart = cursor + 46
            guard nameStart + nameLength <= data.count else { break }
            let name = String(decoding: data.subdata(in: nameStart..<(nameStart + nameLength)), as: UTF8.self)

            if compressed == 0xFFFF_FFFF || uncompressed == 0xFFFF_FFFF || localOffset == 0xFFFF_FFFF {
                readZip64Extra(
                    data: data,
                    start: nameStart + nameLength,
                    length: extraLength,
                    uncompressed: &uncompressed,
                    compressed: &compressed,
                    localOffset: &localOffset
                )
            }

            if !name.hasSuffix("/") {
                entries[name] = Entry(
                    path: name,
                    compressedSize: compressed,
                    uncompressedSize: uncompressed,
                    method: method,
                    localHeaderOffset: localOffset
                )
            }
            cursor = nameStart + nameLength + extraLength + commentLength
        }
        return stripCommonRoot(entries)
    }

    /// `NSFileCoordinator`'s `.forUploading` zip puts the staging folder itself at the root, so
    /// every entry arrives as `filbox-<uuid>/manifest.json` rather than `manifest.json`. Finder's
    /// Compress does the same thing to a folder, and adds `__MACOSX/` resource forks beside it. When
    /// every real entry shares one top-level folder, address them as if it weren't there.
    private static func stripCommonRoot(_ entries: [String: Entry]) -> [String: Entry] {
        let real = entries.filter { !$0.key.hasPrefix("__MACOSX/") && !$0.key.hasSuffix("/.DS_Store") && $0.key != ".DS_Store" }
        let roots = Set(real.keys.compactMap { $0.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first })
        guard roots.count == 1, let root = roots.first,
              real.keys.allSatisfy({ $0.hasPrefix("\(root)/") }) else { return real }

        var stripped: [String: Entry] = [:]
        for (path, entry) in real {
            let relative = String(path.dropFirst(root.count + 1))
            stripped[relative] = Entry(
                path: relative,
                compressedSize: entry.compressedSize,
                uncompressedSize: entry.uncompressedSize,
                method: entry.method,
                localHeaderOffset: entry.localHeaderOffset
            )
        }
        return stripped
    }

    /// The end-of-central-directory record sits last but carries a variable-length comment, so it has
    /// to be found by scanning backwards for its signature.
    private static func findEOCD(in data: Data) -> Int? {
        let maxComment = 65_535 + 22
        let lowerBound = max(0, data.count - maxComment)
        var i = data.count - 22
        while i >= lowerBound {
            if read32(data, i) == 0x0605_4b50 { return i }
            i -= 1
        }
        return nil
    }

    private static func findZip64EOCD(in data: Data, eocd: Int) -> Int? {
        let locator = eocd - 20
        guard locator >= 0, read32(data, locator) == 0x0706_4b50 else { return nil }
        let offset = Int(read64(data, locator + 8))
        guard offset >= 0, offset + 56 <= data.count, read32(data, offset) == 0x0606_4b50 else { return nil }
        return offset
    }

    /// Zip64 extra field (header id 0x0001). Present fields appear in a fixed order, but only the ones
    /// whose 32-bit counterpart saturated are actually written, so each read is conditional.
    private static func readZip64Extra(
        data: Data,
        start: Int,
        length: Int,
        uncompressed: inout Int,
        compressed: inout Int,
        localOffset: inout Int
    ) {
        var cursor = start
        let end = start + length
        while cursor + 4 <= end, cursor + 4 <= data.count {
            let headerID = read16(data, cursor)
            let size = Int(read16(data, cursor + 2))
            let body = cursor + 4
            if headerID == 0x0001 {
                var field = body
                if uncompressed == 0xFFFF_FFFF, field + 8 <= body + size { uncompressed = Int(read64(data, field)); field += 8 }
                if compressed == 0xFFFF_FFFF, field + 8 <= body + size { compressed = Int(read64(data, field)); field += 8 }
                if localOffset == 0xFFFF_FFFF, field + 8 <= body + size { localOffset = Int(read64(data, field)) }
                return
            }
            cursor = body + size
        }
    }

    // MARK: - Little-endian reads

    private func read16(_ offset: Int) -> UInt16 { Self.read16(data, offset) }
    private func read32(_ offset: Int) -> UInt32 { Self.read32(data, offset) }

    private static func read16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func read32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        var value: UInt32 = 0
        for i in 0..<4 { value |= UInt32(data[offset + i]) << (8 * UInt32(i)) }
        return value
    }

    private static func read64(_ data: Data, _ offset: Int) -> UInt64 {
        guard offset + 8 <= data.count else { return 0 }
        var value: UInt64 = 0
        for i in 0..<8 { value |= UInt64(data[offset + i]) << (8 * UInt64(i)) }
        return value
    }
}
