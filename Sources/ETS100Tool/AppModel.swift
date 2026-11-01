#if canImport(SwiftUI)
import Foundation
import ETS100Core

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Identifies a homework row while keeping the status it was listed under
/// (the CDN base URL differs per list).
struct HomeworkRoute: Hashable, Identifiable {
    let homework: HomeworkItem
    let status: String

    var id: String { "\(status):\(homework.id)" }
}

/// Single source of truth for the SwiftUI layer.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var isSignedIn: Bool
    @Published private(set) var profile: AccountProfile?

    @Published var selectedStatus = HomeworkStatus.current
    @Published private(set) var homeworks: [String: [HomeworkItem]] = [:]
    private var baseURLs: [String: String] = [:]
    @Published private(set) var listLoadingStatus: String?
    @Published var listError: String?

    @Published var route: HomeworkRoute?
    @Published private(set) var papers: [String: Paper] = [:]
    @Published private(set) var paperLoadingID: String?
    @Published private(set) var progress: DownloadProgress?
    @Published var paperError: String?

    @Published var alert: AppAlert?
    @Published var isAuthenticating = false
    @Published var requiresSMS = false
    @Published var smsSent = false

    private let auth: ETS100AuthStore
    private let service: ETS100CloudService

    init(
        auth: ETS100AuthStore = SessionEnvironment.auth,
        service: ETS100CloudService = SessionEnvironment.service
    ) {
        self.auth = auth
        self.service = service
        self.isSignedIn = auth.isLoggedIn
        self.profile = auth.profile()
    }

    // MARK: - Session

    func bootstrap() {
        isSignedIn = auth.isLoggedIn
        profile = auth.profile()
    }

    func signIn(phone: String, password: String, rememberPassword: Bool) async {
        let phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard phone.count >= 6, !password.isEmpty else {
            alert = AppAlert(title: "信息不完整", message: "请输入正确的手机号与密码。")
            return
        }
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let signedIn = try await service.signIn(
                phone: phone,
                password: password,
                rememberPassword: rememberPassword
            )
            finishSignIn(signedIn)
        } catch {
            handleSignInError(error)
        }
    }

    func sendSMS(phone: String) async {
        let phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard phone.count >= 6 else {
            alert = AppAlert(title: "手机号无效", message: "请输入正确的手机号。")
            return
        }
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            try await service.sendSMS(phone: phone)
            requiresSMS = true
            smsSent = true
        } catch {
            alert = AppAlert(title: "验证码发送失败", message: message(for: error))
        }
    }

    func signInWithSMS(
        phone: String,
        password: String,
        code: String,
        rememberPassword: Bool
    ) async {
        let phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !password.isEmpty, !code.isEmpty else {
            alert = AppAlert(title: "信息不完整", message: "请输入密码与短信验证码。")
            return
        }
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let signedIn = try await service.signInWithSMSCode(
                phone: phone,
                password: password,
                code: code,
                rememberPassword: rememberPassword
            )
            finishSignIn(signedIn)
        } catch {
            handleSignInError(error)
        }
    }

    func signOut() async {
        await service.logout()
        homeworks.removeAll()
        papers.removeAll()
        baseURLs.removeAll()
        route = nil
        progress = nil
        paperError = nil
        listError = nil
        profile = nil
        requiresSMS = false
        smsSent = false
        isSignedIn = false
    }

    private func finishSignIn(_ result: AccountProfile) {
        profile = result
        isSignedIn = true
        requiresSMS = false
        smsSent = false
        homeworks.removeAll()
        baseURLs.removeAll()
        papers.removeAll()
        route = nil
        Task { await load(status: selectedStatus, force: true) }
    }

    private func handleSignInError(_ error: Error) {
        if let ets = error as? ETSError {
            switch ets {
            case .smsRequired, .smsCodeInvalid, .deviceBindRequired:
                requiresSMS = true
                alert = AppAlert(
                    title: "需要短信验证",
                    message: "该设备尚未绑定，请先获取短信验证码并完成绑定。"
                )
                return
            default:
                break
            }
            alert = AppAlert(title: "登录失败", message: ets.errorDescription ?? "未知错误")
        } else {
            alert = AppAlert(title: "登录失败", message: error.localizedDescription)
        }
    }

    // MARK: - Homework list

    var currentHomeworks: [HomeworkItem] {
        homeworks[selectedStatus] ?? []
    }

    var isLoadingCurrentList: Bool {
        listLoadingStatus == selectedStatus
    }

    func select(status: String) {
        guard status != selectedStatus else { return }
        selectedStatus = status
        listError = nil
        if homeworks[status] == nil {
            Task { await load(status: status) }
        }
    }

    func load(status: String? = nil, force: Bool = false) async {
        let target = status ?? selectedStatus
        guard listLoadingStatus == nil else { return }
        if !force, let cached = homeworks[target], !cached.isEmpty { return }

        listLoadingStatus = target
        listError = nil
        defer {
            if listLoadingStatus == target { listLoadingStatus = nil }
        }

        do {
            let list = try await service.loadHomeworks(status: target)
            homeworks[target] = list.homeworks
            baseURLs[target] = list.baseURL
        } catch {
            listError = message(for: error)
        }
    }

    // MARK: - Papers

    func open(_ homework: HomeworkItem, status: String) {
        route = HomeworkRoute(homework: homework, status: status)
    }

    func paper(for homeworkID: String) -> Paper? {
        papers[homeworkID]
    }

    func loadPaper(for route: HomeworkRoute) async {
        let homework = route.homework
        guard papers[homework.id] == nil, paperLoadingID == nil else { return }

        paperLoadingID = homework.id
        paperError = nil
        progress = nil
        defer {
            paperLoadingID = nil
            progress = nil
        }

        do {
            let baseURL = baseURLs[route.status] ?? ETSConfig.cdnBaseURL
            let paper = try await service.loadPaper(
                for: homework,
                baseURL: baseURL
            ) { [weak self] update in
                Task { @MainActor in
                    self?.progress = update
                }
            }
            papers[homework.id] = paper
        } catch {
            paperError = message(for: error)
        }
    }

    func reloadPaper(_ route: HomeworkRoute) async {
        papers[route.homework.id] = nil
        paperError = nil
        await loadPaper(for: route)
    }

    // MARK: - Cache

    func clearCache() async {
        await service.clearCache()
        papers.removeAll()
        alert = AppAlert(title: "已清除缓存", message: "本地下载的资源包与解析结果已删除。")
    }

    // MARK: - Helpers

    func dismissAlert() {
        alert = nil
    }

    private func message(for error: Error) -> String {
        if let ets = error as? ETSError {
            return ets.errorDescription ?? "未知错误"
        }
        return error.localizedDescription
    }
}
#endif
