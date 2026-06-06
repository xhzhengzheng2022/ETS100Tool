import SwiftUI

/// 登录状态管理
/// 对照安卓 CloudActivationScreen.kt 中的登录逻辑
@MainActor
final class LoginViewModel: ObservableObject {

    // MARK: - 表单状态

    @Published var phone: String = ""
    @Published var password: String = ""
    @Published var isLoading: Bool = false
    @Published var isPasswordVisible: Bool = false
    @Published var errorMessage: String?
    @Published var isLoggedIn: Bool = false

    // MARK: - 初始化

    init() {
        // 检查是否已登录
        isLoggedIn = ETS100AuthManager.isLoggedIn()
        if isLoggedIn {
            phone = ETS100AuthManager.getPhone() ?? ""
        }
    }

    // MARK: - 登录操作（对照安卓 handleLogin）

    func login() async {
        guard !phone.isEmpty, !password.isEmpty else {
            errorMessage = "请输入手机号和密码"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let deviceCode = ETS100AuthManager.getDeviceCode()

            // 第一步：登录
            let loginResponse = try await ETS100ApiClient.shared.login(
                phone: phone,
                password: password,
                deviceCode: deviceCode
            )

            // 第二步：获取父账户 ID
            guard let token = loginResponse.data?.token else {
                errorMessage = "登录响应中无 Token"
                isLoading = false
                return
            }

            let parentAccountId = try await ETS100ApiClient.shared.getEcardList(token: token)

            // 第三步：保存登录信息
            ETS100AuthManager.saveLoginInfo(
                phone: phone,
                token: token,
                parentAccountId: parentAccountId
            )
            ETS100AuthManager.saveLoginMethod(ETS100AuthManager.LOGIN_METHOD_PASSWORD)
            ETS100AuthManager.savePassword(password)

            isLoggedIn = true
            errorMessage = nil

        } catch ETS100ApiError.deviceBindRequired(let phone, let password, let deviceCode) {
            // 设备需要绑定，自动绑定
            await bindDeviceAndLogin(
                phone: phone,
                password: password,
                deviceCode: deviceCode
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// 设备绑定 + 登录（对照安卓 DeviceBindRequiredException 处理）
    private func bindDeviceAndLogin(
        phone: String,
        password: String,
        deviceCode: String
    ) async {
        do {
            let bindResponse = try await ETS100ApiClient.shared.bindDevice(
                phone: phone,
                password: password,
                deviceCode: deviceCode
            )

            guard let token = bindResponse.token else {
                errorMessage = "绑定成功但未获取到 Token"
                return
            }

            do {
                let parentAccountId = try await ETS100ApiClient.shared.getEcardList(token: token)

                ETS100AuthManager.saveLoginInfo(
                    phone: phone,
                    token: token,
                    parentAccountId: parentAccountId
                )
                ETS100AuthManager.saveLoginMethod(ETS100AuthManager.LOGIN_METHOD_PASSWORD)
                ETS100AuthManager.savePassword(password)

                isLoggedIn = true
                errorMessage = nil
            } catch {
                errorMessage = "绑定成功但获取账户信息失败: \(error.localizedDescription)"
            }
        } catch {
            errorMessage = "设备绑定失败: \(error.localizedDescription)"
        }
    }

    /// 登出
    func logout() {
        ETS100AuthManager.logout()
        isLoggedIn = false
        phone = ""
        password = ""
    }
}
