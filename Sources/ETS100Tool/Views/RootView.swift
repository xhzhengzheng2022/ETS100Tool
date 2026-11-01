#if canImport(SwiftUI)
import SwiftUI
import ETS100Core

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.isSignedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.isSignedIn)
        .alert(
            model.alert?.title ?? "提示",
            isPresented: Binding(
                get: { model.alert != nil },
                set: { if !$0 { model.dismissAlert() } }
            ),
            presenting: model.alert
        ) { _ in
            Button("好", role: .cancel) {
                model.dismissAlert()
            }
        } message: { alert in
            Text(alert.message)
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            HomeworkListView()
                .tabItem {
                    Label("作业", systemImage: "doc.text.magnifyingglass")
                }

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
        .task {
            model.bootstrap()
        }
    }
}
#endif
