#if canImport(SwiftUI)
import Foundation
import ETS100Core

/// Wires the platform credential backends into the shared cloud service.
@MainActor
enum SessionEnvironment {
    static let auth: ETS100AuthStore = {
        let preferences = UserDefaultsCredentialBackend()
        #if canImport(Security)
        return ETS100AuthStore(secrets: KeychainCredentialBackend(), preferences: preferences)
        #else
        return ETS100AuthStore(secrets: InMemoryCredentialBackend(), preferences: preferences)
        #endif
    }()

    static let service = ETS100CloudService(auth: auth)
}
#endif
