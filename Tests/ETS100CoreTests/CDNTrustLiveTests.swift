#if canImport(Security)
import XCTest
@testable import ETS100Core

/// 在真实网络上验证 CDN 证书能被下载会话接受（仅 Apple 平台执行）。
/// 网络不可达时跳过，不算失败；证书被拒绝时直接失败。
final class CDNTrustLiveTests: XCTestCase {
    func testCDNCertificateIsAccepted() async throws {
        let session = CDNTrustPolicy.makeSession()
        guard let url = URL(string: "https://cdn.subject.ets100.com/") else {
            return XCTFail("无法构造 CDN 地址")
        }

        do {
            let (_, response) = try await session.data(from: url)
            XCTAssertNotNil(response as? HTTPURLResponse, "应收到 HTTP 响应")
        } catch let error as URLError where ETS100CloudService.isCertificateError(error) {
            XCTFail("CDN 证书仍被拒绝：\(error)")
        } catch {
            throw XCTSkip("CDN 不可达：\(error.localizedDescription)")
        }
    }
}
#endif
