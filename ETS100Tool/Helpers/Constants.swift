import Foundation

/// 全局常量定义，严格对照安卓项目 Constants
enum Constants {

    // MARK: - API 端点（对照 ETS100ApiClient.kt Config）

    /// API 基础地址
    static let API_BASE_URL = "https://api.ets100.com"

    /// CDN 基础地址（用于下载作业 ZIP 包）
    static let CDN_BASE_URL = "https://cdn.subject.ets100.com"

    // MARK: - 秘密密钥

    /// MD5 签名用的 SecretKey（对照安卓 SECRET_KEY）
    static let SECRET_KEY = "555ffbe95ccf4e9535a110170b445ab8"

    // MARK: - 应用信息

    static let APP_PID = "1000"
    static let APP_VERSION = "1.3.7"
    static let BUNDLE_ID = "com.nanshanqilin.ets"

    // MARK: - Keychain / UserDefaults 键名

    static let KEY_DEVICE_CODE = "ets_device_code"
    static let KEY_TOKEN = "ets_token"
    static let KEY_PARENT_ACCOUNT_ID = "ets_parent_account_id"
    static let KEY_PHONE = "ets_phone"
    static let KEY_PASSWORD = "ets_password"
    static let KEY_LOGIN_METHOD = "ets_login_method"

    // MARK: - 作业状态

    static let STATUS_CURRENT = "1"
    static let STATUS_HISTORY = "2"
    static let STATUS_EXPIRED = "3"
}
