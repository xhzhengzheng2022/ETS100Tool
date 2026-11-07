import XCTest
@testable import ETS100Core

final class CDNTrustPolicyTests: XCTestCase {
    func testSessionsUseRequestTimeout() {
        let configuration = CDNTrustPolicy.configuration()
        XCTAssertEqual(configuration.timeoutIntervalForRequest, ETSConfig.requestTimeout)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 300)
    }

    func testCertificateErrorClassification() {
        XCTAssertTrue(ETS100CloudService.isCertificateError(URLError(.secureConnectionFailed)))
        XCTAssertTrue(ETS100CloudService.isCertificateError(URLError(.serverCertificateUntrusted)))
        XCTAssertTrue(ETS100CloudService.isCertificateError(URLError(.serverCertificateHasBadDate)))
        XCTAssertFalse(ETS100CloudService.isCertificateError(URLError(.timedOut)))
    }
}
