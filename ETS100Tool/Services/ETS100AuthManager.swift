import Foundation
import Security

/// Token 认证管理器（Keychain 存储）
/// 严格对照安卓 ETS100AuthManager.kt 的 SharedPreferences 操作
///
/// 使用 iOS Keychain 替代 SharedPreferences 存储敏感数据（token、密码）
/// 使用 UserDefaults 存储非敏感数据（phone、login_method）
@MainActor
final class ETS100AuthManager {

    // MARK: - 登录方法常量（对照安卓）

    static let LOGIN_METHOD_PASSWORD = "password"
    static let LOGIN_METHOD_CHANGYAN = "changyan"

    // MARK: - Keychain 服务标识

    private static let keychainService = "com.nanshanqilin.ets"

    // MARK: - 机器码（对照安卓 getDeviceCode）

    /// 获取或生成设备唯一机器码（33 字符 hex）
    /// 对照安卓：随机生成 33 位十六进制字符串，存储在 SharedPreferences 中
    static func getDeviceCode() -> String {
        if let existing = UserDefaults.standard.string(forKey: Constants.KEY_DEVICE_CODE),
           existing.count == 33 {
            return existing
        }
        let deviceCode = (0..<33).map { _ in
            String(format: "%x", Int.random(in: 0..<16))
        }.joined()
        UserDefaults.standard.set(deviceCode, forKey: Constants.KEY_DEVICE_CODE)
        return deviceCode
    }

    // MARK: - 登录状态判定

    /// 是否已登录（对照安卓 isLoggedIn）
    static func isLoggedIn() -> Bool {
        let token = getToken()
        let parentAccountId = getParentAccountId()
        return token != nil && parentAccountId != nil
    }

    // MARK: - Token 管理

    /// 获取存储的 Token
    static func getToken() -> String? {
        keychainRead(key: Constants.KEY_TOKEN)
    }

    /// 获取父账户 ID
    static func getParentAccountId() -> String? {
        keychainRead(key: Constants.KEY_PARENT_ACCOUNT_ID)
    }

    /// 获取手机号
    static func getPhone() -> String? {
        UserDefaults.standard.string(forKey: Constants.KEY_PHONE)
    }

    /// 获取密码（Keychain）
    static func getPassword() -> String? {
        keychainRead(key: Constants.KEY_PASSWORD)
    }

    /// 获取登录方式
    static func getLoginMethod() -> String? {
        UserDefaults.standard.string(forKey: Constants.KEY_LOGIN_METHOD)
    }

    // MARK: - 保存登录信息（对照安卓 saveLoginInfo）

    /// 保存登录信息
    /// 对照安卓 saveLoginInfo(context, phone, token, parentAccountId)
    static func saveLoginInfo(
        phone: String,
        token: String,
        parentAccountId: String
    ) {
        UserDefaults.standard.set(phone, forKey: Constants.KEY_PHONE)
        keychainWrite(value: token, key: Constants.KEY_TOKEN)
        keychainWrite(value: parentAccountId, key: Constants.KEY_PARENT_ACCOUNT_ID)
    }

    /// 保存密码（对照安卓 savePassword）
    static func savePassword(_ password: String) {
        keychainWrite(value: password, key: Constants.KEY_PASSWORD)
    }

    /// 保存登录方式（对照安卓 saveLoginMethod）
    static func saveLoginMethod(_ method: String) {
        UserDefaults.standard.set(method, forKey: Constants.KEY_LOGIN_METHOD)
    }

    // MARK: - 登出（对照安卓 logout，保留机器码）

    /// 登出，清除认证信息但保留机器码
    /// 对照安卓：clear SharedPreferences 但保留 device_code
    static func logout() {
        keychainDelete(key: Constants.KEY_TOKEN)
        keychainDelete(key: Constants.KEY_PARENT_ACCOUNT_ID)
        keychainDelete(key: Constants.KEY_PASSWORD)
        UserDefaults.standard.removeObject(forKey: Constants.KEY_PHONE)
        UserDefaults.standard.removeObject(forKey: Constants.KEY_LOGIN_METHOD)
        // 注意：不删除 device_code（对照安卓行为）
    }

    // MARK: - Keychain 底层操作

    private static func keychainWrite(value: String, key: String) {
        guard let data = value.data(using: .utf8) else { return }
        keychainDelete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func keychainRead(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainDelete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
