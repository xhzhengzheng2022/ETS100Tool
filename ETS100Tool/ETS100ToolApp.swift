import SwiftUI

/// ETS100 助手 iOS 版 — App 入口
/// @main 入口，WindowGroup，管理全局状态
@main
struct ETS100ToolApp: App {
    @StateObject private var authManager = AuthStateManager()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(.none)
        }
    }
}

/// 全局认证状态管理器（跨视图共享）
final class AuthStateManager: ObservableObject {
    @Published var isLoggedIn: Bool

    init() {
        isLoggedIn = ETS100AuthManager.isLoggedIn()
    }

    func refresh() {
        isLoggedIn = ETS100AuthManager.isLoggedIn()
    }
}
