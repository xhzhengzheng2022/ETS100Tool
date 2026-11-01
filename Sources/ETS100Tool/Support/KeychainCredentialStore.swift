#if canImport(Security)
import Foundation
import Security
import ETS100Core

/// Keychain-backed secret storage for the login token and saved password.
///
/// The core layer only knows about the `CredentialBackend` protocol, which keeps
/// it portable (Linux unit tests use `InMemoryCredentialBackend` instead).
public final class KeychainCredentialBackend: CredentialBackend, @unchecked Sendable {
    private let service: String

    public init(service: String = "com.nanshanqilin.ets.credentials") {
        self.service = service
    }

    public func string(for key: String) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ value: String?, for key: String) {
        let query = baseQuery(for: key)
        SecItemDelete(query as CFDictionary)

        guard let value, let data = value.data(using: .utf8) else { return }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
#endif
