import Foundation

/// Global constants shared by the iOS app and the protocol layer.
///
/// The values mirror the Android client so that both platforms produce
/// byte-identical requests and archive passwords.
public enum ETSConfig {
    public static let apiBaseURL = URL(string: "https://api.ets100.com")!
    public static let cdnBaseURL = "https://cdn.subject.ets100.com"

    public static let pid = "grlx"
    public static let secretKey = "555ffbe95ccf4e9535a110170b445ab8"

    public static let requestTimeout: TimeInterval = 30
    public static let archiveFooterSize = 336

    public static let appVersion = "2.0.2"
    public static let bundleID = "com.nanshanqilin.ets"

    public static let statusCurrent = "1"
    public static let statusHistory = "2"
    public static let statusExpired = "3"

    /// Fixed request parameters required by the ETS100 gateway.
    public enum Device {
        public static let sn = "test"
        public static let system = "4"
        public static let localIP = "127.0.0.1"
        public static let clientVersion = "5.4.5"
        public static let loginVersion = "3"
        public static let rebindVersion = "2"
        public static let loginDeviceName = "DESKTOP"
        public static let rebindDeviceName = "1337"
    }
}

/// API routes used by the cloud reader.
public enum ETSRoute {
    public static let login = "user/login"
    public static let loginZt = "user/login-zt"
    public static let rebindCode = "user/rebind-code"
    public static let ecardList = "m/ecard/list"
    public static let homeworkList = "g/homework/list"
}
