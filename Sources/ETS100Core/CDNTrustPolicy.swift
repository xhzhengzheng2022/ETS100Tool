import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Security)
import Security
#endif

/// CDN 资源下载会话的 TLS 策略。
///
/// 上游 CDN 的证书实际签发给 `default.chinanetcenter.com`，与
/// `cdn.subject.ets100.com` 主机名不匹配，系统默认信任评估必然失败并报
/// “A TLS error caused the secure connection to fail”
/// （`NSURLErrorSecureConnectionFailed`）。
///
/// 该会话只用于下载作业资源包，不携带账号凭据；API 请求使用独立会话，
/// 仍由系统严格校验。因此这里对齐安卓端 `ETS100ApiDownload` 的做法：
/// 直接接受 CDN 的服务器证书。
public enum CDNTrustPolicy {
    public static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = ETSConfig.requestTimeout
        configuration.timeoutIntervalForResource = 300
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

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
}

#if canImport(Security)

/// 接受 CDN 服务器证书的 `URLSessionDelegate`。
final class CDNTrustDelegate: NSObject, URLSessionDelegate {
    @objc
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
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

#endif
