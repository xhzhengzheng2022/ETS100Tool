import Foundation
import XCTest
@testable import ETS100Core

final class ZipPasswordGeneratorTests: XCTestCase {
    func testRejectsArchiveWithoutFooterSeed() {
        let short = Data(repeating: 0, count: 64)
        XCTAssertThrowsError(try ZipPasswordGenerator.password(from: short)) { error in
            XCTAssertEqual(error as? ETSError, .archiveTooSmall)
        }
    }

    func testRejectsUnknownFooterSignature() {
        var footer = [UInt8](repeating: 0, count: ZipPasswordGenerator.footerSize)
        footer[0] = 0xFF
        XCTAssertFalse(ZipPasswordGenerator.hasValidSignature(footer))
        XCTAssertThrowsError(try ZipPasswordGenerator.password(fromFooter: footer)) { error in
            XCTAssertEqual(error as? ETSError, .invalidArchiveSignature)
        }
    }

    func testAcceptsBothKnownSignatures() throws {
        var footer = [UInt8](repeating: 0, count: ZipPasswordGenerator.footerSize)
        footer.replaceSubrange(0..<8, with: Array("MSTCHINA".utf8))
        XCTAssertTrue(ZipPasswordGenerator.hasValidSignature(footer))
        XCTAssertEqual(try ZipPasswordGenerator.password(fromFooter: footer).count, 64)

        var eplatFooter = [UInt8](repeating: 0, count: ZipPasswordGenerator.footerSize)
        eplatFooter.replaceSubrange(144..<149, with: Array("EPLAT".utf8))
        XCTAssertTrue(ZipPasswordGenerator.hasValidSignature(eplatFooter))
    }

    func testPasswordIsDeterministicForFixture() throws {
        let data = try fixture("encrypted", "zip")
        let password = try ZipPasswordGenerator.password(from: data)
        XCTAssertEqual(
            password,
            "087B965E51E4B1200EBFD13E9761CAA5CE64CA2AC5C0F4EA126177BF4A0F8D22"
        )
    }
}

final class ZipArchiveTests: XCTestCase {
    func testDecryptsZipCryptoEntryAndExtractsContentJSON() throws {
        let data = try fixture("encrypted", "zip")
        XCTAssertTrue(ZipArchive.isValidMagic(data))

        let password = try ZipPasswordGenerator.password(from: data)
        let archive = try ZipArchive(data: data)
        XCTAssertEqual(archive.entries.count, 1)
        XCTAssertEqual(archive.entries.first?.name, "content.json")
        XCTAssertTrue(archive.entries.first?.isEncrypted == true)

        let expected = try fixture("choose", "json")
        let decrypted = try archive.contentJSON(password: password)
        XCTAssertEqual(decrypted, expected)
    }

    func testWrongPasswordFailsChecksum() throws {
        let archive = try ZipArchive(data: try fixture("encrypted", "zip"))
        XCTAssertThrowsError(try archive.contentJSON(password: String(repeating: "0", count: 64))) { error in
            XCTAssertEqual(error as? ETSError, .archiveCorrupt)
        }
    }

    func testMissingContentJSONReportsNoContent() throws {
        let empty = Data([0x50, 0x4B, 0x05, 0x06])
        XCTAssertThrowsError(try ZipArchive(data: empty))
    }

    func testInvalidMagicRejectsRandomData() {
        XCTAssertFalse(ZipArchive.isValidMagic(Data("not a zip".utf8)))
        XCTAssertFalse(ZipArchive.isValidMagic(Data()))
    }
}

private func fixture(_ name: String, _ ext: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") else {
        throw ETSError.parsingFailed("缺少测试夹具 \(name).\(ext)")
    }
    return try Data(contentsOf: url)
}
