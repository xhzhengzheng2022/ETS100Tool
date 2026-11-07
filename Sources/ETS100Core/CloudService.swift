import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// High-level cloud workflow: authenticate, list homework, download resource
/// packages, decrypt ZIPs, parse answers and cache the result.
public actor ETS100CloudService {
    private let api: ETS100APIClient
    private let auth: ETS100AuthStore
    private let session: URLSession
    private let fileManager: FileManager
    private let cacheRoot: URL
    private let papersRoot: URL

    public init(
        auth: ETS100AuthStore,
        api: ETS100APIClient = ETS100APIClient(),
        cacheRoot: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.auth = auth
        self.api = api
        self.fileManager = fileManager
        // CDN 证书实际签发给了 `default.chinanetcenter.com`，需要放宽主机名匹配。
        self.session = CDNTrustPolicy.makeSession()

        let base = cacheRoot ?? {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            return support.appendingPathComponent("ETS100Tool", isDirectory: true)
        }()
        self.cacheRoot = base.appendingPathComponent("cloud_homework", isDirectory: true)
        self.papersRoot = base.appendingPathComponent("papers", isDirectory: true)
    }

    // MARK: - Session

    public func currentProfile() -> AccountProfile? {
        auth.profile()
    }

    public var isLoggedIn: Bool {
        auth.isLoggedIn
    }

    public var deviceCode: String {
        auth.ensureDeviceCode()
    }

    public func sendSMS(phone: String) async throws {
        try await api.sendBindingCode(phone: phone)
    }

    /// Password login. Automatically binds the current device when the gateway
    /// answers with `code=30014`.
    public func signIn(
        phone: String,
        password: String,
        rememberPassword: Bool
    ) async throws -> AccountProfile {
        let deviceCode = auth.ensureDeviceCode()
        let token: String
        do {
            let result = try await api.login(phone: phone, password: password, deviceCode: deviceCode)
            token = result.token
        } catch let error as ETSError {
            if case .deviceBindRequired = error {
                let result = try await api.bindDevice(
                    phone: phone,
                    password: password,
                    deviceCode: deviceCode
                )
                token = result.token
            } else {
                throw error
            }
        }
        return try await finishSignIn(
            token: token,
            phone: phone,
            password: rememberPassword ? password : nil
        )
    }

    /// SMS-authorized device binding. Call after `sendSMS(phone:)`.
    public func signInWithSMSCode(
        phone: String,
        password: String,
        code: String,
        rememberPassword: Bool
    ) async throws -> AccountProfile {
        let deviceCode = auth.ensureDeviceCode()
        let result = try await api.bindDevice(
            phone: phone,
            password: password,
            deviceCode: deviceCode,
            verificationCode: code
        )
        return try await finishSignIn(
            token: result.token,
            phone: phone,
            password: rememberPassword ? password : nil
        )
    }

    private func finishSignIn(token: String, phone: String, password: String?) async throws -> AccountProfile {
        let selection = try await api.ecardSelection(
            token: token,
            preferredAccountID: auth.preferredEcardID
        )
        auth.saveSession(
            token: token,
            phone: phone,
            password: password,
            ecardID: selection.selectedAccount.id,
            selection: selection
        )
        return AccountProfile(
            phone: phone,
            accountName: selection.selectedAccount.name,
            grade: selection.selectedAccount.grade,
            className: selection.selectedAccount.className,
            parentAccountID: selection.parentAccountID
        )
    }

    public func logout() {
        auth.clearSession()
    }

    // MARK: - Homework

    public func loadHomeworks(status: String = HomeworkStatus.current) async throws -> HomeworkList {
        let token = try await freshToken()
        guard let parentAccountID = auth.parentAccountID else {
            throw ETSError.notLoggedIn
        }
        do {
            return try await api.homeworkList(
                token: token,
                parentAccountID: parentAccountID,
                status: status
            )
        } catch let error as ETSError {
            // Expired tokens are common after the official client signs in elsewhere.
            if case .server(let code, _) = error, code != 0 {
                let refreshed = try await refreshSession()
                return try await api.homeworkList(
                    token: refreshed,
                    parentAccountID: auth.parentAccountID ?? parentAccountID,
                    status: status
                )
            }
            throw error
        }
    }

    private func freshToken() async throws -> String {
        if let phone = auth.phone, let password = auth.password {
            do {
                return try await loginAgain(phone: phone, password: password)
            } catch {
                // Fall back to the persisted token; the caller surfaces API errors.
            }
        }
        guard let token = auth.token else { throw ETSError.notLoggedIn }
        return token
    }

    private func loginAgain(phone: String, password: String) async throws -> String {
        let deviceCode = auth.ensureDeviceCode()
        do {
            let result = try await api.login(phone: phone, password: password, deviceCode: deviceCode)
            auth.updateToken(result.token)
            return result.token
        } catch let error as ETSError {
            if case .deviceBindRequired = error {
                let result = try await api.bindDevice(
                    phone: phone,
                    password: password,
                    deviceCode: deviceCode
                )
                auth.updateToken(result.token)
                return result.token
            }
            throw error
        }
    }

    private func refreshSession() async throws -> String {
        if let phone = auth.phone, let password = auth.password {
            return try await loginAgain(phone: phone, password: password)
        }
        guard let token = auth.token else { throw ETSError.notLoggedIn }
        let refreshed = try await api.refreshToken(token)
        auth.updateToken(refreshed)
        return refreshed
    }

    // MARK: - Papers

    public func cachedPaper(for homeworkID: String) -> Paper? {
        let url = paperFileURL(homeworkID: homeworkID)
        guard let data = try? Data(contentsOf: url),
              let paper = try? JSONDecoder().decode(Paper.self, from: data),
              !paper.sections.isEmpty else {
            return nil
        }
        return paper
    }

    public func loadPaper(
        for homework: HomeworkItem,
        baseURL: String,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> Paper {
        if let cached = cachedPaper(for: homework.id) {
            return cached
        }
        guard !homework.needsOnlineFetch else {
            throw ETSError.archiveUnsupported("在线作业（词汇 / PK）暂不支持云端解析")
        }
        guard !homework.contents.isEmpty else {
            throw ETSError.parsingFailed("作业没有可下载的资源包")
        }

        let directory = homeworkCacheDirectory(homeworkID: homework.id)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var sections: [PaperSection] = []
        var questionIndex = 0
        var lastError: Error?

        for (index, content) in homework.contents.enumerated() {
            guard let url = Self.zipURL(contentURL: content.url, baseURL: baseURL) else {
                lastError = ETSError.archiveUnsupported("资源地址无效：\(content.url)")
                continue
            }
            let fileName = content.zipFileName
            guard !fileName.isEmpty else {
                lastError = ETSError.archiveUnsupported("无法从地址提取文件名")
                continue
            }

            onProgress(
                DownloadProgress(
                    currentFileName: fileName,
                    index: index + 1,
                    total: homework.contents.count
                )
            )

            do {
                let zipURL = directory.appendingPathComponent(Self.safeFileName(fileName))
                let data: Data
                if let cached = try? Data(contentsOf: zipURL), ZipArchive.isValidMagic(cached) {
                    data = cached
                } else {
                    data = try await download(url: url)
                    guard ZipArchive.isValidMagic(data) else {
                        throw ETSError.archiveUnsupported("下载内容不是 ZIP")
                    }
                    try data.write(to: zipURL, options: .atomic)
                }

                let password = try ZipPasswordGenerator.password(from: data)
                let archive = try ZipArchive(data: data)
                let contentData = try archive.contentJSON(password: password)
                let parsed = try ContentParser.parse(
                    data: contentData,
                    groupName: content.groupName,
                    startIndex: questionIndex
                )
                sections.append(parsed.section)
                questionIndex += parsed.section.questions.count
            } catch {
                lastError = error
            }
        }

        guard !sections.isEmpty else {
            throw lastError ?? ETSError.parsingFailed("未能解析到任何题目")
        }

        let paper = Paper(
            id: homework.id,
            title: homework.name,
            regionLabel: "云端",
            totalScore: homework.totalScore > 0 ? homework.totalScore : nil,
            sections: sections
        )
        persist(paper)
        return paper
    }

    public func clearCache() {
        for url in [cacheRoot, papersRoot] {
            try? fileManager.removeItem(at: url)
        }
    }

    // MARK: - Auto complete

    /// Runs the local auto-complete pipeline for a parsed homework.
    public func autoComplete(
        homework: HomeworkItem,
        paper: Paper,
        options: AutoCompleteOptions,
        onProgress: @escaping @Sendable (AutoCompleteProgress) -> Void
    ) async throws -> AutoCompleteResult {
        let token = try await freshToken()
        guard let parentAccountID = auth.parentAccountID else {
            throw ETSError.notLoggedIn
        }
        let engine = AutoCompleteEngine(
            api: api,
            token: token,
            parentAccountID: parentAccountID,
            relogin: { try await self.refreshSession() }
        )
        return try await engine.run(
            homework: homework,
            paper: paper,
            options: options,
            onProgress: onProgress
        )
    }

    // MARK: - Cache helpers

    private func homeworkCacheDirectory(homeworkID: String) -> URL {
        cacheRoot.appendingPathComponent(Self.safeFileName(homeworkID), isDirectory: true)
    }

    private func paperFileURL(homeworkID: String) -> URL {
        papersRoot.appendingPathComponent(Self.safeFileName(homeworkID) + ".json")
    }

    private func persist(_ paper: Paper) {
        do {
            try fileManager.createDirectory(at: papersRoot, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(paper)
            try data.write(to: paperFileURL(homeworkID: paper.id), options: .atomic)
        } catch {
            // Cache failures must not fail the user-facing parse.
        }
    }

    // MARK: - Networking

    static func isCertificateError(_ error: URLError) -> Bool {
        switch error.code {
        case .secureConnectionFailed,
             .serverCertificateUntrusted,
             .serverCertificateHasBadDate,
             .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot,
             .clientCertificateRejected:
            return true
        default:
            return false
        }
    }

    private func download(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = ETSConfig.requestTimeout
        request.setValue(url.host ?? "cdn.subject.ets100.com", forHTTPHeaderField: "Host")
        request.setValue("libcurl-agent/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where Self.isCertificateError(error) {
            throw ETSError.network("CDN 安全连接失败（v\(ETSConfig.appVersion) · \(url.host ?? "未知")）")
        } catch {
            throw ETSError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ETSError.http(status: http.statusCode)
        }
        return data
    }

    static func zipURL(contentURL: String, baseURL: String) -> URL? {
        let trimmed = contentURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            let secure = trimmed.replacingOccurrences(of: "http://", with: "https://")
            return URL(string: secure)
        }
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.lowercased().hasPrefix("http://") {
            base = base.replacingOccurrences(of: "http://", with: "https://")
        }
        while base.hasSuffix("/") { base.removeLast() }
        let path = trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
        return URL(string: base + path)
    }

    static func safeFileName(_ name: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let sanitized = name.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }
        return sanitized.isEmpty ? "resource" : sanitized.joined()
    }
}
