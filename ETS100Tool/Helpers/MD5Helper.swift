import Foundation
import CommonCrypto

/// MD5 哈希计算工具
/// 对照安卓 ETS100ApiClient.kt 中的 md5() 方法，使用 CommonCrypto 实现
enum MD5Helper {

    /// 计算字符串的 MD5 哈希值，返回小写十六进制字符串
    /// 对照安卓: fun md5(input: String): String = BigInteger(1, MessageDigest.getInstance("MD5").digest(input.toByteArray())).toString(16).padStart(32, '0')
    static func md5(_ input: String) -> String {
        guard let data = input.data(using: .utf8) else { return "" }
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_MD5(ptr.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 计算 Data 的 MD5 哈希值，返回小写十六进制字符串
    static func md5(_ data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_MD5(ptr.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
