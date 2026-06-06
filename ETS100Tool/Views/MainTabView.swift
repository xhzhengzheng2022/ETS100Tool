import SwiftUI

/// 主 TabBar 导航
/// 对照安卓 MainActivity.kt 中的底部导航
struct MainTabView: View {
    @StateObject private var loginVM = LoginViewModel()
    @State private var selectedTab: Tab = .homework

    enum Tab: String, CaseIterable {
        case homework = "作业"
        case settings = "设置"

        var icon: String {
            switch self {
            case .homework: return "list.bullet.clipboard"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        Group {
            if loginVM.isLoggedIn {
                TabView(selection: $selectedTab) {
                    HomeworkListView()
                        .tabItem {
                            Label(Tab.homework.rawValue, systemImage: Tab.homework.icon)
                        }
                        .tag(Tab.homework)

                    SettingsView()
                        .tabItem {
                            Label(Tab.settings.rawValue, systemImage: Tab.settings.icon)
                        }
                        .tag(Tab.settings)
                }
            } else {
                LoginView {
                    loginVM.isLoggedIn = true
                }
            }
        }
    }
}
