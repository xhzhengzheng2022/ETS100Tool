import Foundation
import ETS100Core

/// App-level metadata shared by the SwiftUI layer.
enum AppInfo {
    static let version = ETSConfig.appVersion
    static let build = "3"
    static let repositoryURL = URL(string: "https://github.com/xhzhengzheng2022/ETS100Tool")!
    static let bundleID = ETSConfig.bundleID
    static let displayName = "ETS 助手"
}
