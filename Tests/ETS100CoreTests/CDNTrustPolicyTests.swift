import XCTest
@testable import ETS100Core

final class CDNTrustPolicyTests: XCTestCase {
    func testTrustedHosts() {
        XCTAssertTrue(CDNTrustPolicy.isTrustedHost("cdn.subject.ets100.com"))
        XCTAssertTrue(CDNTrustPolicy.isTrustedHost("CDN.SUBJECT.ETS100.COM"))
        XCTAssertFalse(CDNTrustPolicy.isTrustedHost("api.ets100.com"))
        XCTAssertFalse(CDNTrustPolicy.isTrustedHost("evil.example.com"))
    }

    func testAllowedCertificateNames() {
        XCTAssertTrue(CDNTrustPolicy.matchesAllowedName("default.chinanetcenter.com"))
        XCTAssertTrue(CDNTrustPolicy.matchesAllowedName("cdn.subject.ets100.com"))
        XCTAssertTrue(CDNTrustPolicy.matchesAllowedName("ets100.com"))
        XCTAssertTrue(CDNTrustPolicy.matchesAllowedName(" Default.ChinanetCenter.COM "))
    }

    func testRejectsUnknownCertificateNames() {
        XCTAssertFalse(CDNTrustPolicy.matchesAllowedName(""))
        XCTAssertFalse(CDNTrustPolicy.matchesAllowedName("evil-chinanetcenter.com"))
        XCTAssertFalse(CDNTrustPolicy.matchesAllowedName("chinanetcenter.com.evil.example"))
        XCTAssertFalse(CDNTrustPolicy.matchesAllowedName("chinanetcenterXcom"))
    }

    func testSessionsUseRequestTimeout() {
        let configuration = CDNTrustPolicy.configuration()
        XCTAssertEqual(configuration.timeoutIntervalForRequest, ETSConfig.requestTimeout)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 300)
    }

    func testServerTrustDecision() {
        XCTAssertTrue(CDNTrustPolicy.shouldAcceptServerTrust(chainValid: true, recognized: true))
        XCTAssertTrue(CDNTrustPolicy.shouldAcceptServerTrust(chainValid: true, recognized: false))
        XCTAssertTrue(CDNTrustPolicy.shouldAcceptServerTrust(chainValid: false, recognized: true))
        XCTAssertFalse(CDNTrustPolicy.shouldAcceptServerTrust(chainValid: false, recognized: false))
    }

    func testCertificateErrorClassification() {
        XCTAssertTrue(ETS100CloudService.isCertificateError(URLError(.secureConnectionFailed)))
        XCTAssertTrue(ETS100CloudService.isCertificateError(URLError(.serverCertificateUntrusted)))
        XCTAssertFalse(ETS100CloudService.isCertificateError(URLError(.timedOut)))
    }
}
