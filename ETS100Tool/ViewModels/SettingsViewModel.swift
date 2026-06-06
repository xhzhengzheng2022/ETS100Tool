import SwiftUI

/// 设置管理
/// 对照安卓 SettingsScreen.kt + SettingsManager.kt（简化版）
@MainActor
final class SettingsViewModel: ObservableObject {

    // MARK: - 发布属性

    @Published var isLoggedIn: Bool = false
    @Published var phone: String = ""
    @Published var appVersion: String = Constants.APP_VERSION
    @Published var deviceCode: String = ""

    // MARK: - 初始化

    init() {
        refreshLoginState()
    }

    func refreshLoginState() {
        isLoggedIn = ETS100AuthManager.isLoggedIn()
        phone = ETS100AuthManager.getPhone() ?? ""
        deviceCode = ETS100AuthManager.getDeviceCode()
    }

    /// 登出
    func logout() {
        ETS100AuthManager.logout()
        refreshLoginState()
    }
}
