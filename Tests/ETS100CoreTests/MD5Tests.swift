import XCTest
@testable import ETS100Core

final class MD5Tests: XCTestCase {
    func testKnownVectors() {
        XCTAssertEqual(MD5.hash(""), "d41d8cd98f00b204e9800998ecf8427e")
        XCTAssertEqual(MD5.hash("abc"), "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(MD5.hash("The quick brown fox jumps over the lazy dog"), "9e107d9d372bb6826bd81d3542a419d6")
    }
}
