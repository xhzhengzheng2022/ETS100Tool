import Foundation

/// Derives the 64-character decryption password from the 336-byte ETS100
/// archive footer. The algorithm matches `ZipPasswordGenerator.kt` byte for byte.
public enum ZipPasswordGenerator {
    public static let footerSize = ETSConfig.archiveFooterSize
    private static let seedRange = 16..<144

    public static func password(from data: Data) throws -> String {
        guard data.count >= footerSize else { throw ETSError.archiveTooSmall }
        let bytes = [UInt8](data)
        let footer = Array(bytes[(bytes.count - footerSize)..<bytes.count])
        return try password(fromFooter: footer)
    }

    public static func password(fromFooter footer: [UInt8]) throws -> String {
        guard footer.count >= footerSize else { throw ETSError.archiveTooSmall }
        guard hasValidSignature(footer) else { throw ETSError.invalidArchiveSignature }

        let seed = Data(footer[seedRange])
        let first = MD5.hash(seed).uppercased()
        let second = MD5.hash(Data(first.utf8)).uppercased()
        return first + second
    }

    public static func hasValidSignature(_ footer: [UInt8]) -> Bool {
        guard footer.count >= footerSize else { return false }
        let mstchina = Array("MSTCHINA".utf8)
        let eplat = Array("EPLAT".utf8)
        return Array(footer[0..<8]) == mstchina || Array(footer[144..<149]) == eplat
    }
}
