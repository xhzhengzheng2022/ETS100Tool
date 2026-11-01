import Foundation
import XCTest
@testable import ETS100Core

final class PayloadTests: XCTestCase {
    func testCompactJSONMatchesByteStableEncoding() throws {
        let value = JSONValue.object(JSONObject([
            ("b", .int(2)),
            ("a", .string("http://example.com/a b")),
            ("c", .array([.bool(true), .null])),
        ]))
        XCTAssertEqual(value.compactJSON, #"{"b":2,"a":"http://example.com/a b","c":[true,null]}"#)
    }

    func testCompactJSONEscapesControlCharacters() {
        let value = JSONValue.string("line\nbreak\tand\u{0001}control")
        XCTAssertEqual(value.compactJSON, "\"line\\nbreak\\tand\\u0001control\"")
    }

    func testSignIsLowercaseMD5OfPidTimestampBodyAndSecret() {
        let timestamp = 1_700_000_000
        let bodyBase64 = "QUJD"
        let expected = MD5.hash(ETSConfig.pid + String(timestamp) + bodyBase64 + ETSConfig.secretKey)
        XCTAssertEqual(ETS100APIClient.sign(timestamp: timestamp, bodyBase64: bodyBase64), expected)
        XCTAssertEqual(expected.count, 32)
        XCTAssertTrue(expected.allSatisfy { $0.isHexDigit })
    }

    func testEnvelopeWrapsSignedBase64Body() throws {
        let params = JSONObject([
            ("sn", .string("test")),
            ("phone", .string("13800000000")),
        ])
        let timestamp = 1_700_000_000
        let payload = ETS100APIClient.payload(
            route: "user/login",
            params: params,
            timestamp: timestamp
        )
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
        )
        let head = try XCTUnwrap(object["head"] as? [String: Any])
        XCTAssertEqual(head["version"] as? String, "1.0")
        XCTAssertEqual(head["pid"] as? String, "grlx")
        XCTAssertEqual(head["time"] as? Int, timestamp)

        let bodyBase64 = try XCTUnwrap(object["body"] as? String)
        XCTAssertEqual(head["sign"] as? String, ETS100APIClient.sign(timestamp: timestamp, bodyBase64: bodyBase64))

        let bodyData = try XCTUnwrap(Data(base64Encoded: bodyBase64))
        let bodyArray = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: bodyData) as? [[String: Any]]
        )
        XCTAssertEqual(bodyArray.count, 1)
        XCTAssertEqual(bodyArray[0]["r"] as? String, "user/login")
        let decodedParams = try XCTUnwrap(bodyArray[0]["params"] as? [String: Any])
        XCTAssertEqual(decodedParams["sn"] as? String, "test")
        XCTAssertEqual(decodedParams["phone"] as? String, "13800000000")
    }

    func testEmptyEnvelopeHasNoWhitespace() {
        let payload = ETS100APIClient.payload(route: "user/login", params: JSONObject(), timestamp: 1)
        XCTAssertFalse(payload.contains(" "))
        XCTAssertFalse(payload.contains("\n"))
    }
}

final class AuthStoreTests: XCTestCase {
    private func makeStore() -> ETS100AuthStore {
        ETS100AuthStore(
            secrets: InMemoryCredentialBackend(),
            preferences: InMemoryCredentialBackend()
        )
    }

    func testDeviceCodeIsGeneratedOnceAndWellFormed() {
        let store = makeStore()
        let first = store.ensureDeviceCode()
        XCTAssertTrue(ETS100AuthStore.isValidDeviceCode(first))
        XCTAssertEqual(store.ensureDeviceCode(), first)
    }

    func testDeviceCodeUsesInjectedRandomSource() {
        let code = ETS100AuthStore.makeDeviceCode { length in
            String(repeating: "AB", count: length / 2)
        }
        XCTAssertTrue(ETS100AuthStore.isValidDeviceCode(code))
        XCTAssertEqual(code.split(separator: "|").count, 2)
    }

    func testSessionPersistsSecretsAndProfile() {
        let store = makeStore()
        let account = EcardAccount(
            key: "0",
            id: "42",
            parentID: "parent-1",
            userAccountID: "u",
            name: "张三",
            grade: "初二",
            status: "0",
            mobileStatus: "1",
            outOfDate: "0",
            classID: "c1",
            className: "二班",
            machineCodeStatus: "0"
        )
        store.saveSession(
            token: "token-1",
            phone: "13800000000",
            password: "secret",
            ecardID: account.id,
            selection: EcardSelection(
                parentAccountID: account.parentID,
                selectedAccount: account,
                validAccounts: [account]
            )
        )

        XCTAssertTrue(store.isLoggedIn)
        XCTAssertEqual(store.token, "token-1")
        XCTAssertEqual(store.password, "secret")
        XCTAssertEqual(store.preferredEcardID, "42")
        XCTAssertEqual(store.profile()?.maskedPhone, "138****0000")
        XCTAssertEqual(store.profile()?.className, "二班")
    }

    func testClearSessionKeepsDeviceCode() {
        let store = makeStore()
        let code = store.ensureDeviceCode()
        store.saveSession(
            token: "t",
            phone: "13800000000",
            password: nil,
            ecardID: "1",
            selection: EcardSelection(
                parentAccountID: "p",
                selectedAccount: EcardAccount(
                    key: "0", id: "1", parentID: "p", userAccountID: "u",
                    name: "", grade: "", status: "", mobileStatus: "",
                    outOfDate: "", classID: "", className: "", machineCodeStatus: ""
                ),
                validAccounts: []
            )
        )
        store.clearSession()

        XCTAssertFalse(store.isLoggedIn)
        XCTAssertNil(store.token)
        XCTAssertNil(store.phone)
        XCTAssertNil(store.preferredEcardID)
        XCTAssertEqual(store.ensureDeviceCode(), code)
    }

    func testPasswordIsNotPersistedWhenRememberDisabled() {
        let store = makeStore()
        store.saveSession(
            token: "t",
            phone: "13800000000",
            password: nil,
            ecardID: "1",
            selection: EcardSelection(
                parentAccountID: "p",
                selectedAccount: EcardAccount(
                    key: "0", id: "1", parentID: "p", userAccountID: "u",
                    name: "", grade: "", status: "", mobileStatus: "",
                    outOfDate: "", classID: "", className: "", machineCodeStatus: ""
                ),
                validAccounts: []
            )
        )
        XCTAssertEqual(store.token, "t")
        XCTAssertNil(store.password)
        XCTAssertTrue(store.isLoggedIn)
    }
}
