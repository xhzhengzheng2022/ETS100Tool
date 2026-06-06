import Foundation

/// ZIP 解压密码生成器
/// 严格对照安卓 ZipPasswordGenerator.kt 的算法实现
///
/// 算法流程：
/// 1. 读取 ZIP 文件尾部 336 字节
/// 2. 验证文件签名 "MSTCHINA" 或 "EPLAT"
/// 3. 从偏移 16 开始取 128 字节作为种子
/// 4. 第一次 MD5（小写）
/// 5. 转大写后再 MD5
/// 6. 拼接两次 MD5 结果得到 64 字符密码
enum ZipPasswordGenerator {

    private static let TAIL_SIZE = 336
    private static let SEED_OFFSET = 16
    private static let SEED_LENGTH = 128
    private static let SIGNATURE_MST = "MSTCHINA"
    private static let SIGNATURE_EPL = "EPLAT"

    enum PasswordError: Error, LocalizedError {
        case fileNotFound(String)
        case fileTooSmall(Int)
        case invalidSignature(String)
        case seedExtractionFailed

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let path):
                return "ZIP 文件不存在: \(path)"
            case .fileTooSmall(let size):
                return "ZIP 文件过小 (\(size) 字节)，无法提取密码种子"
            case .invalidSignature(let sig):
                return "无效的 ZIP 签名: \(sig)，期望 MSTCHINA 或 EPLAT"
            case .seedExtractionFailed:
                return "密码种子提取失败"
            }
        }
    }

    /// 从 ZIP 文件生成解压密码
    /// - Parameter zipPath: ZIP 文件的绝对路径
    /// - Returns: 64 字符的解压密码
    /// - Throws: PasswordError
    static func generate(from zipPath: String) throws -> String {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: zipPath) else {
            throw PasswordError.fileNotFound(zipPath)
        }

        guard let fileHandle = FileHandle(forReadingAtPath: zipPath) else {
            throw PasswordError.fileNotFound(zipPath)
        }
        defer { try? fileHandle.close() }

        let fileSize = try fileHandle.seekToEnd()
        try fileHandle.seek(toOffset: 0)

        guard fileSize >= TAIL_SIZE else {
            throw PasswordError.fileTooSmall(Int(fileSize))
        }

        // 读取尾部 336 字节（对照安卓 readTail）
        try fileHandle.seek(toOffset: fileSize - UInt64(TAIL_SIZE))
        guard let tailData = try fileHandle.read(upToCount: TAIL_SIZE), tailData.count == TAIL_SIZE else {
            throw PasswordError.seedExtractionFailed
        }

        // 验证签名（对照安卓 verifySignature）
        let tailStr = String(data: tailData, encoding: .utf8) ?? String(data: tailData, encoding: .ascii) ?? ""
        guard tailStr.contains(SIGNATURE_MST) || tailStr.contains(SIGNATURE_EPL) else {
            throw PasswordError.invalidSignature(tailStr)
        }

        // 提取种子：偏移 16，长度 128（对照安卓 extractSeed）
        let seedStart = tailData.index(tailData.startIndex, offsetBy: SEED_OFFSET)
        let seedEnd = seedStart.advanced(by: SEED_LENGTH)
        guard seedEnd <= tailData.endIndex else {
            throw PasswordError.seedExtractionFailed
        }
        let seed = tailData[seedStart..<seedEnd]

        // 第一次 MD5（小写，对照安卓 firstHash）
        let firstHash = MD5Helper.md5(Data(seed))

        // 大写后再 MD5（对照安卓 secondHash）
        let secondHash = MD5Helper.md5(firstHash.uppercased())

        // 拼接得到 64 字符密码（对照安卓 both）
        return firstHash + secondHash
    }

    /// 从 Data 直接生成密码（内存中操作，避免写磁盘）
    static func generate(from data: Data) throws -> String {
        guard data.count >= TAIL_SIZE else {
            throw PasswordError.fileTooSmall(data.count)
        }

        let tailStart = data.index(data.endIndex, offsetBy: -TAIL_SIZE)
        let tailData = data[tailStart..<data.endIndex]

        let tailStr = String(data: tailData, encoding: .utf8) ?? ""
        guard tailStr.contains(SIGNATURE_MST) || tailStr.contains(SIGNATURE_EPL) else {
            throw PasswordError.invalidSignature(tailStr)
        }

        let seedStart = tailData.startIndex.advanced(by: SEED_OFFSET)
        let seedEnd = seedStart.advanced(by: SEED_LENGTH)
        guard seedEnd <= tailData.endIndex else {
            throw PasswordError.seedExtractionFailed
        }
        let seed = tailData[seedStart..<seedEnd]

        let firstHash = MD5Helper.md5(Data(seed))
        let secondHash = MD5Helper.md5(firstHash.uppercased())

        return firstHash + secondHash
    }
}
