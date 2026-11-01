import Foundation

/// Errors surfaced by the cloud client. Messages are user-facing (Chinese).
public enum ETSError: Error, LocalizedError, Equatable {
    case network(String)
    case http(status: Int)
    case invalidResponse
    case server(code: Int, message: String)
    case deviceBindRequired
    case smsRequired
    case smsCodeInvalid
    case missingToken
    case missingAccount
    case notLoggedIn
    case archiveTooSmall
    case invalidArchiveSignature
    case archiveUnsupported(String)
    case archiveCorrupt
    case noContentJSON
    case parsingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .network(let message): return "网络连接失败：\(message)"
        case .http(let status): return "服务器返回 HTTP \(status)"
        case .invalidResponse: return "服务器响应格式异常"
        case .server(let code, let message):
            return message.isEmpty ? "服务端错误（\(code)）" : message
        case .deviceBindRequired: return "当前设备需要绑定验证"
        case .smsRequired: return "该账号需要短信验证码登录"
        case .smsCodeInvalid: return "验证码错误，请重新输入"
        case .missingToken: return "登录成功但未获取到 Token"
        case .missingAccount: return "未找到可用的 E 卡账号"
        case .notLoggedIn: return "尚未登录 ETS100 账号"
        case .archiveTooSmall: return "资源包过小，无法读取尾部密码种子"
        case .invalidArchiveSignature: return "资源包签名无效，可能不是 ETS100 加密资源"
        case .archiveUnsupported(let detail): return "不支持的资源包格式：\(detail)"
        case .archiveCorrupt: return "资源包已损坏或密码错误"
        case .noContentJSON: return "资源包中未找到 content.json"
        case .parsingFailed(let detail): return "答案解析失败：\(detail)"
        }
    }
}
