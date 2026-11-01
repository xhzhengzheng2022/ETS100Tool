import CZlib
import Foundation

public struct ZipEntry: Hashable, Sendable {
    public var name: String
    public var flags: UInt16
    public var method: UInt16
    public var dosTime: UInt16
    public var crc32: UInt32
    public var compressedSize: Int
    public var uncompressedSize: Int
    public var localHeaderOffset: Int

    public var isEncrypted: Bool { (flags & 0x0001) != 0 }
    public var isDirectory: Bool { name.hasSuffix("/") }
}

/// Minimal ZIP reader with support for traditional ZipCrypto encryption
/// (the scheme produced by ZipCrypto/zip4j) and raw DEFLATE entries.
public struct ZipArchive: Sendable {
    private let bytes: [UInt8]
    public let entries: [ZipEntry]

    public init(data: Data) throws {
        self.bytes = [UInt8](data)
        self.entries = try Self.readCentralDirectory(bytes)
    }

    public static func isValidMagic(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let head = [UInt8](data.prefix(4))
        return head[0] == 0x50 && head[1] == 0x4B && (
            (head[2] == 0x03 && head[3] == 0x04)
                || (head[2] == 0x05 && head[3] == 0x06)
                || (head[2] == 0x07 && head[3] == 0x08)
        )
    }

    public func data(for name: String, password: String? = nil) throws -> Data {
        guard let entry = entries.first(where: { $0.name == name }) else {
            throw ETSError.noContentJSON
        }
        return try extract(entry, password: password)
    }

    /// Finds `content.json`, preferring an exact root entry and falling back to
    /// the shallowest nested copy (the Android reader is tolerant here too).
    public func contentJSON(password: String? = nil) throws -> Data {
        let candidates = entries
            .filter { $0.name.split(separator: "/").last == "content.json" }
            .sorted { $0.name.count < $1.name.count }
        guard let entry = candidates.first else { throw ETSError.noContentJSON }
        return try extract(entry, password: password)
    }

    public func extractAll(to directory: URL, password: String? = nil) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for entry in entries where !entry.isDirectory {
            let components = entry.name.split(separator: "/", omittingEmptySubsequences: true)
            guard !components.contains(where: { $0 == ".." }) else { continue }
            let target = directory.appendingPathComponent(entry.name)
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try extract(entry, password: password).write(to: target)
        }
    }

    // MARK: - Extraction

    private func extract(_ entry: ZipEntry, password: String?) throws -> Data {
        let localOffset = entry.localHeaderOffset
        guard localOffset >= 0, localOffset + 30 <= bytes.count else {
            throw ETSError.archiveCorrupt
        }
        guard readU32(localOffset) == 0x04034B50 else {
            throw ETSError.archiveCorrupt
        }
        let nameLength = Int(readU16(localOffset + 26))
        let extraLength = Int(readU16(localOffset + 28))
        let dataStart = localOffset + 30 + nameLength + extraLength
        let dataEnd = dataStart + entry.compressedSize
        guard dataEnd <= bytes.count else { throw ETSError.archiveCorrupt }

        var payload = Array(bytes[dataStart..<dataEnd])

        if entry.isEncrypted {
            guard let password, !password.isEmpty else { throw ETSError.archiveCorrupt }
            payload = try ZipCrypto.decrypt(payload, password: password, entry: entry)
        }

        let plain: Data
        switch entry.method {
        case 0:
            plain = Data(payload)
        case 8:
            plain = try Inflate.raw(Data(payload), expectedSize: entry.uncompressedSize)
        default:
            throw ETSError.archiveUnsupported("压缩方式 \(entry.method)")
        }

        if entry.uncompressedSize > 0, plain.count != entry.uncompressedSize {
            throw ETSError.archiveCorrupt
        }
        if entry.crc32 != 0, CRC32.checksum(plain) != entry.crc32 {
            throw ETSError.archiveCorrupt
        }
        return plain
    }

    // MARK: - Central directory

    private static func readCentralDirectory(_ bytes: [UInt8]) throws -> [ZipEntry] {
        guard bytes.count >= 22 else { throw ETSError.archiveTooSmall }

        var eocd = -1
        let lowest = max(0, bytes.count - 22 - 0xFFFF)
        var cursor = bytes.count - 22
        while cursor >= lowest {
            if readU32(bytes, cursor) == 0x06054B50 {
                eocd = cursor
                break
            }
            cursor -= 1
        }
        guard eocd >= 0 else { throw ETSError.archiveCorrupt }

        let entryCount = Int(readU16(bytes, eocd + 10))
        let directorySize = Int(readU32(bytes, eocd + 12))
        let directoryOffset = Int(readU32(bytes, eocd + 16))

        if entryCount == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
            throw ETSError.archiveUnsupported("ZIP64")
        }
        guard directoryOffset >= 0, directoryOffset + directorySize <= bytes.count else {
            throw ETSError.archiveCorrupt
        }

        var entries: [ZipEntry] = []
        entries.reserveCapacity(entryCount)
        var offset = directoryOffset
        for _ in 0..<entryCount {
            guard offset + 46 <= bytes.count, readU32(bytes, offset) == 0x02014B50 else {
                throw ETSError.archiveCorrupt
            }
            let flags = readU16(bytes, offset + 8)
            let method = readU16(bytes, offset + 10)
            let dosTime = readU16(bytes, offset + 12)
            let crc = readU32(bytes, offset + 16)
            let compressed = Int(readU32(bytes, offset + 20))
            let uncompressed = Int(readU32(bytes, offset + 24))
            let nameLength = Int(readU16(bytes, offset + 28))
            let extraLength = Int(readU16(bytes, offset + 30))
            let commentLength = Int(readU16(bytes, offset + 32))
            let localOffset = Int(readU32(bytes, offset + 42))

            let nameStart = offset + 46
            let nameEnd = nameStart + nameLength
            guard nameEnd <= bytes.count else { throw ETSError.archiveCorrupt }
            let name = String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self)

            entries.append(
                ZipEntry(
                    name: name,
                    flags: flags,
                    method: method,
                    dosTime: dosTime,
                    crc32: crc,
                    compressedSize: compressed,
                    uncompressedSize: uncompressed,
                    localHeaderOffset: localOffset
                )
            )
            offset = nameEnd + extraLength + commentLength
        }
        return entries
    }

    private func readU16(_ offset: Int) -> UInt16 { Self.readU16(bytes, offset) }
    private func readU32(_ offset: Int) -> UInt32 { Self.readU32(bytes, offset) }

    private static func readU16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= bytes.count else { return 0 }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readU32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}

// MARK: - Inflate

enum Inflate {
    static func raw(_ data: Data, expectedSize: Int) throws -> Data {
        let input = [UInt8](data)
        guard !input.isEmpty else { throw ETSError.archiveCorrupt }

        var capacity = max(expectedSize, 4096)
        for _ in 0..<10 {
            var output = [UInt8](repeating: 0, count: capacity)
            let written: Int = input.withUnsafeBytes { sourceBuffer in
                output.withUnsafeMutableBytes { destinationBuffer in
                    let source = sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
                    let destination = destinationBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
                    return Int(czlib_inflate_raw(source, input.count, destination, capacity))
                }
            }
            if written >= 0 {
                return Data(output[0..<written])
            }
            capacity *= 2
        }
        throw ETSError.archiveCorrupt
    }
}

// MARK: - ZipCrypto

enum ZipCrypto {
    static func decrypt(_ payload: [UInt8], password: String, entry: ZipEntry) throws -> [UInt8] {
        guard payload.count >= 12 else { throw ETSError.archiveCorrupt }
        var state = Keys(password: password)

        var decrypted = [UInt8](repeating: 0, count: payload.count)
        for index in 0..<payload.count {
            decrypted[index] = state.decrypt(payload[index])
        }

        // Traditional PKZIP check byte: the high byte of the CRC or DOS time.
        let crcCheck = UInt8((entry.crc32 >> 24) & 0xFF)
        let timeCheck = UInt8((entry.dosTime >> 8) & 0xFF)
        let check = decrypted[11]
        guard check == crcCheck || check == timeCheck else {
            throw ETSError.archiveCorrupt
        }
        return Array(decrypted[12...])
    }

    private struct Keys {
        private var key0: UInt32 = 0x1234_5678
        private var key1: UInt32 = 0x2345_6789
        private var key2: UInt32 = 0x3456_7890

        init(password: String) {
            for byte in password.utf8 {
                update(byte)
            }
        }

        mutating func decrypt(_ byte: UInt8) -> UInt8 {
            let plain = byte ^ nextKeyByte()
            update(plain)
            return plain
        }

        private mutating func update(_ byte: UInt8) {
            key0 = CRC32.update(key0, byte)
            let mixed = key1 &+ (key0 & 0xFF)
            key1 = mixed &* 134_775_813 &+ 1
            key2 = CRC32.update(key2, UInt8((key1 >> 24) & 0xFF))
        }

        private func nextKeyByte() -> UInt8 {
            let temp = key2 | 2
            return UInt8(((temp &* (temp ^ 1)) >> 8) & 0xFF)
        }
    }
}

// MARK: - CRC32

enum CRC32 {
    static let table: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for index in 0..<256 {
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
            }
            table[index] = value
        }
        return table
    }()

    /// Running key update used by ZipCrypto (no initial/final XOR).
    static func update(_ crc: UInt32, _ byte: UInt8) -> UInt32 {
        table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}
