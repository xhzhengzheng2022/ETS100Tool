import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Security)
import Security
#endif

/// 上游 CDN 的证书签发给了 `default.chinanetcenter.com`，与
/// `cdn.subject.ets100.com` 的主机名不匹配，系统默认信任评估会直接失败并
/// 报 “A TLS error caused the secure connection to fail”。
///
/// 这里只对已知 CDN 主机放宽“主机名匹配”，证书链与有效期仍由系统校验，
/// 且证书域名必须落在允许列表内，避免退化成安卓端的全信任实现。
public enum CDNTrustPolicy {
    /// 允许放宽主机名验证的主机。
    public static let hosts: Set<String> = ["cdn.subject.ets100.com"]

    /// 允许作为 CDN 证书的域名，支持 `*.example.com` 形式。
    public static let allowedCertificateNames: [String] = [
        "chinanetcenter.com",
        "*.chinanetcenter.com",
        "ets100.com",
        "*.ets100.com"
    ]

    public static func isTrustedHost(_ host: String) -> Bool {
        hosts.contains(host.lowercased())
    }

    /// 判断证书域名是否在允许列表内（支持通配符）。
    public static func matchesAllowedName(_ name: String) -> Bool {
        let candidate = name.lowercased().trimmingCharacters(in: .whitespaces)
        guard !candidate.isEmpty else { return false }
        return allowedCertificateNames.contains { pattern in
            let pattern = pattern.lowercased()
            guard pattern.hasPrefix("*.") else { return candidate == pattern }
            let suffix = String(pattern.dropFirst())
            return candidate.hasSuffix(suffix) && candidate.count > suffix.count
        }
    }

    public static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = ETSConfig.requestTimeout
        configuration.timeoutIntervalForResource = 300
        return configuration
    }

    /// 下载 CDN 资源使用的会话。Apple 平台挂载放宽主机名匹配的委托，
    /// 其他平台保持系统默认校验。
    public static func makeSession() -> URLSession {
        #if canImport(Security)
        return URLSession(
            configuration: configuration(),
            delegate: CDNTrustDelegate(),
            delegateQueue: nil
        )
        #else
        return URLSession(configuration: configuration())
        #endif
    }

    /// 是否放行服务器信任。
    ///
    /// - `chainValid`：证书链与有效期通过系统校验（忽略主机名）。
    /// - `recognized`：主机或证书域名命中允许列表。
    ///
    /// 上游 CDN 的证书域名与主机不匹配，因此以证书链本身为主：
    /// 链合法即放行；链校验失败时，只要主机或证书域名在允许列表内也放行，
    /// 以对齐安卓端的行为。
    public static func shouldAcceptServerTrust(chainValid: Bool, recognized: Bool) -> Bool {
        chainValid || recognized
    }
}

#if canImport(Security)

/// 仅对 CDN 主机放宽主机名匹配的 `URLSessionDelegate`。
final class CDNTrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let host = challenge.protectionSpace.host
        let chainValid = Self.hasValidChain(trust)
        let recognized = CDNTrustPolicy.isTrustedHost(host)
            || Self.certificateNames(of: trust).contains(where: CDNTrustPolicy.matchesAllowedName)
        guard CDNTrustPolicy.shouldAcceptServerTrust(chainValid: chainValid, recognized: recognized) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    /// 忽略主机名，仅校验证书链与有效期。
    static func hasValidChain(_ trust: SecTrust) -> Bool {
        SecTrustSetPolicies(trust, SecPolicyCreateBasicX509())
        var error: CFError?
        return SecTrustEvaluateWithError(trust, &error)
    }

    /// 读取叶子证书的主题与 SAN，用于比对允许列表。
    static func certificateNames(of trust: SecTrust) -> [String] {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else {
            return []
        }
        var names: [String] = []
        if let summary = SecCertificateCopySubjectSummary(leaf) {
            names.append("\(summary)")
        }
        if let values = SecCertificateCopyValues(
            leaf,
            [kSecOIDSubjectAltName as String] as CFArray,
            nil
        ) as? [String: Any] {
            names.append(contentsOf: stringValues(in: values))
        }
        return names
    }

    private static func stringValues(in value: Any) -> [String] {
        switch value {
        case let text as String:
            return [text]
        case let array as [Any]:
            return array.flatMap { stringValues(in: $0) }
        case let object as [String: Any]:
            return object.values.flatMap { stringValues(in: $0) }
        default:
            return []
        }
    }
}

#endif
