#if canImport(SwiftUI)
import SwiftUI

@main
struct ETS100ToolApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
    }
}
#endif
