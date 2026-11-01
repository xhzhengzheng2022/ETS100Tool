import Foundation

/// Storage abstraction so the core layer stays platform-agnostic.
public protocol CredentialBackend: Sendable {
    func string(for key: String) -> String?
    func set(_ value: String?, for key: String)
}

/// Simple in-memory backend used by unit tests and previews.
public final class InMemoryCredentialBackend: CredentialBackend, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func string(for key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public func set(_ value: String?, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = value
    }
}

/// `UserDefaults` backend for non-secret values (phone, account name, device code).
public final class UserDefaultsCredentialBackend: CredentialBackend, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(suiteName: String? = nil) {
        if let suiteName, let defaults = UserDefaults(suiteName: suiteName) {
            self.defaults = defaults
        } else {
            self.defaults = .standard
        }
    }

    public func string(for key: String) -> String? {
        defaults.string(forKey: key)
    }

    public func set(_ value: String?, for key: String) {
        defaults.set(value, forKey: key)
    }
}

/// Session persistence. Tokens and passwords go to the secret backend
/// (Keychain on iOS); non-secret account metadata goes to preferences.
public final class ETS100AuthStore: @unchecked Sendable {
    public enum Key {
        public static let token = "ets100.token"
        public static let password = "ets100.password"
        public static let deviceCode = "ets100.device_code"
        public static let phone = "ets100.phone"
        public static let parentAccountID = "ets100.parent_account_id"
        public static let selectedEcardID = "ets100.selected_ecard_id"
        public static let accountName = "ets100.account_name"
        public static let grade = "ets100.grade"
        public static let className = "ets100.class_name"
        public static let loginMethod = "ets100.login_method"
    }

    private let secrets: any CredentialBackend
    private let preferences: any CredentialBackend
    private let lock = NSLock()

    public init(secrets: any CredentialBackend, preferences: any CredentialBackend) {
        self.secrets = secrets
        self.preferences = preferences
    }

    // MARK: - Device code

    /// Returns the persisted device code, generating and storing one on first use.
    public func ensureDeviceCode() -> String {
        lock.lock()
        defer { lock.unlock() }

        if let existing = preferences.string(for: Key.deviceCode),
           Self.isValidDeviceCode(existing) {
            return existing
        }
        let generated = Self.makeDeviceCode()
        preferences.set(generated, for: Key.deviceCode)
        return generated
    }

    public var deviceCode: String {
        ensureDeviceCode()
    }

    public static func makeDeviceCode() -> String {
        makeDeviceCode(randomHex: randomHex)
    }

    public static func makeDeviceCode(randomHex: (Int) -> String) -> String {
        let dataHash = MD5.hash(randomHex(16))
        let macHash = MD5.hash(randomHex(16))
        let first = String(dataHash.dropFirst(8).prefix(16))
        let second = String(macHash.dropFirst(8).prefix(16))
        return "\(first)|\(second)"
    }

    public static func isValidDeviceCode(_ code: String) -> Bool {
        code.range(of: "^[0-9a-f]{16}\\|[0-9a-f]{16}$", options: .regularExpression) != nil
    }

    private static func randomHex(_ length: Int) -> String {
        let alphabet = Array("0123456789ABCDEF")
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }

    // MARK: - Session

    public var token: String? {
        secrets.string(for: Key.token).flatMap { $0.isEmpty ? nil : $0 }
    }

    public var phone: String? {
        preferences.string(for: Key.phone)
    }

    /// Stored only when the user opts in to automatic re-login.
    public var password: String? {
        secrets.string(for: Key.password).flatMap { $0.isEmpty ? nil : $0 }
    }

    public var parentAccountID: String? {
        preferences.string(for: Key.parentAccountID)
    }

    public var preferredEcardID: String? {
        preferences.string(for: Key.selectedEcardID)
    }

    public var isLoggedIn: Bool {
        token != nil && parentAccountID != nil
    }

    public func profile() -> AccountProfile? {
        guard let phone = phone, let parent = parentAccountID else { return nil }
        return AccountProfile(
            phone: phone,
            accountName: preferences.string(for: Key.accountName) ?? "",
            grade: preferences.string(for: Key.grade) ?? "",
            className: preferences.string(for: Key.className) ?? "",
            parentAccountID: parent,
            loginMethod: preferences.string(for: Key.loginMethod) ?? "password"
        )
    }

    public func saveSession(
        token: String,
        phone: String,
        password: String?,
        ecardID: String,
        selection: EcardSelection
    ) {
        lock.lock()
        defer { lock.unlock() }

        secrets.set(token, for: Key.token)
        secrets.set(password, for: Key.password)
        preferences.set(phone, for: Key.phone)
        preferences.set(selection.parentAccountID, for: Key.parentAccountID)
        preferences.set(ecardID, for: Key.selectedEcardID)
        preferences.set(selection.selectedAccount.name, for: Key.accountName)
        preferences.set(selection.selectedAccount.grade, for: Key.grade)
        preferences.set(selection.selectedAccount.className, for: Key.className)
        preferences.set("password", for: Key.loginMethod)
    }

    public func updateToken(_ token: String) {
        lock.lock()
        defer { lock.unlock() }
        secrets.set(token, for: Key.token)
    }

    public func updateParentAccountID(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        preferences.set(value, for: Key.parentAccountID)
    }

    /// Clears credentials but keeps the device code so the device stays bound.
    public func clearSession() {
        lock.lock()
        defer { lock.unlock() }

        secrets.set(nil, for: Key.token)
        secrets.set(nil, for: Key.password)
        for key in [
            Key.phone, Key.parentAccountID, Key.selectedEcardID, Key.accountName,
            Key.grade, Key.className, Key.loginMethod,
        ] {
            preferences.set(nil, for: key)
        }
    }
}
