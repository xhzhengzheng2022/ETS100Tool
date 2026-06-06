import Foundation

// MARK: - API 错误类型（对照安卓异常类）

enum ETS100ApiError: Error, LocalizedError {
    case invalidURL(String)
    case networkError(Error)
    case httpError(Int, String?)
    case decodingError(Error)
    case loginFailed(String)
    case deviceBindRequired(phone: String, password: String, deviceCode: String)
    case noData
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):           return "无效的 URL: \(url)"
        case .networkError(let e):           return "网络错误: \(e.localizedDescription)"
        case .httpError(let code, let msg):  return "HTTP \(code): \(msg ?? "未知错误")"
        case .decodingError(let e):          return "解析错误: \(e.localizedDescription)"
        case .loginFailed(let msg):          return "登录失败: \(msg)"
        case .deviceBindRequired:            return "设备需要绑定"
        case .noData:                        return "无数据返回"
        case .invalidResponse:               return "响应格式无效"
        }
    }
}

// MARK: - 下载进度数据（对照安卓 CloudHomeworkState.DownloadProgress）

struct DownloadProgress {
    let downloadedBytes: Int64
    let totalBytes: Int64
    let currentFileName: String

    var fraction: Double? {
        totalBytes > 0
            ? Double(downloadedBytes) / Double(totalBytes)
            : nil
    }
}

// MARK: - API 客户端

/// 云端 API 客户端
/// 严格对照安卓 ETS100ApiClient.kt，实现所有 API 端点、签名算法、请求头
actor ETS100ApiClient {

    // MARK: - 单例

    static let shared = ETS100ApiClient()

    private let session: URLSession
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
        self.jsonEncoder = JSONEncoder()
        self.jsonDecoder = JSONDecoder()
    }

    // MARK: - MD5 签名生成（对照安卓 generateSign）

    /// 生成 MD5 签名
    /// 公式：MD5(PID + timestamp + base64Body + SECRET_KEY)
    private func generateSign(timestamp: String, bodyBase64: String) -> String {
        let raw = Constants.APP_PID + timestamp + bodyBase64 + Constants.SECRET_KEY
        return MD5Helper.md5(raw)
    }

    /// 将请求体编码为 Base64（对照安卓 bodyBase64）
    private func bodyToBase64(_ body: Data) -> String {
        body.base64EncodedString()
    }

    // MARK: - 通用请求构建

    /// 构建带签名的 URLRequest
    private func buildRequest(
        url: URL,
        method: String = "POST",
        body: Data? = nil,
        token: String? = nil
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("ETS100Tool-iOS/\(Constants.APP_VERSION)", forHTTPHeaderField: "User-Agent")

        let timestamp = String(Int(Date().timeIntervalSince1970))
        request.setValue(Constants.APP_PID, forHTTPHeaderField: "PID")
        request.setValue(timestamp, forHTTPHeaderField: "Timestamp")

        if let body = body {
            request.httpBody = body
            let bodyB64 = bodyToBase64(body)
            let sign = generateSign(timestamp: timestamp, bodyBase64: bodyB64)
            request.setValue(sign, forHTTPHeaderField: "Sign")
        }

        if let token = token {
            request.setValue(token, forHTTPHeaderField: "Token")
        }

        return request
    }

    // MARK: - 通用请求执行

    /// 执行请求并返回原始 Data
    private func execute(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ETS100ApiError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8)
            throw ETS100ApiError.httpError(httpResponse.statusCode, bodyStr)
        }

        return data
    }

    /// 执行请求并 JSON 解码为指定类型
    private func execute<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let data = try await execute(request)
        do {
            return try jsonDecoder.decode(type, from: data)
        } catch {
            throw ETS100ApiError.decodingError(error)
        }
    }

    // MARK: - 登录（对照安卓 login）

    /// 账号密码登录
    /// 对照安卓：fun login(phone, password, deviceCode): Result<LoginResponse>
    func login(
        phone: String,
        password: String,
        deviceCode: String
    ) async throws -> LoginResponse {
        let urlString = "\(Constants.API_BASE_URL)/api/login"
        guard let url = URL(string: urlString) else {
            throw ETS100ApiError.invalidURL(urlString)
        }

        let body: [String: String] = [
            "phone": phone,
            "password": password,
            "device_code": deviceCode
        ]
        let bodyData = try jsonEncoder.encode(body)
        let request = buildRequest(url: url, body: bodyData)

        let response: LoginResponse = try await execute(request, as: LoginResponse.self)

        // 检查是否需要设备绑定
        if response.code == 1001 || response.msg?.contains("设备") == true {
            throw ETS100ApiError.deviceBindRequired(
                phone: phone,
                password: password,
                deviceCode: deviceCode
            )
        }

        guard response.code == 0 || response.code == 200 else {
            throw ETS100ApiError.loginFailed(response.msg ?? "未知错误")
        }

        return response
    }

    // MARK: - 设备绑定（对照安卓 bindDevice）

    /// 绑定设备
    /// 对照安卓：fun bindDevice(phone, password, deviceCode): Result<BindResponse>
    func bindDevice(
        phone: String,
        password: String,
        deviceCode: String
    ) async throws -> BindDeviceResponse {
        let urlString = "\(Constants.API_BASE_URL)/api/device/bind"
        guard let url = URL(string: urlString) else {
            throw ETS100ApiError.invalidURL(urlString)
        }

        let body: [String: String] = [
            "phone": phone,
            "password": password,
            "device_code": deviceCode
        ]
        let bodyData = try jsonEncoder.encode(body)
        let request = buildRequest(url: url, body: bodyData)

        let response: BindDeviceResponse = try await execute(request, as: BindDeviceResponse.self)

        guard response.code == 0 || response.code == 200 else {
            throw ETS100ApiError.loginFailed(response.msg ?? "绑定失败")
        }

        return response
    }

    // MARK: - 获取 E 卡列表 / 父账户 ID（对照安卓 getEcardList）

    /// 获取 E 卡列表，返回 parent_account_id
    /// 对照安卓：fun getEcardList(token): Result<String>
    func getEcardList(token: String) async throws -> String {
        let urlString = "\(Constants.API_BASE_URL)/api/ecard/list"
        guard let url = URL(string: urlString) else {
            throw ETS100ApiError.invalidURL(urlString)
        }

        let request = buildRequest(url: url, method: "GET", token: token)

        let response: EcardListResponse = try await execute(request, as: EcardListResponse.self)

        guard response.code == 0 || response.code == 200,
              let parentId = response.data?.parentAccountId else {
            throw ETS100ApiError.noData
        }

        return parentId
    }

    // MARK: - 作业列表（对照安卓 getHomeworkList）

    /// 获取作业列表
    /// 对照安卓：fun getHomeworkList(token, parentAccountId, status): Result<List<HomeworkInfo>>
    func getHomeworkList(
        token: String,
        parentAccountId: String,
        status: String
    ) async throws -> [HomeworkItem] {
        let urlString = "\(Constants.API_BASE_URL)/api/homework/list"
        guard var components = URLComponents(string: urlString) else {
            throw ETS100ApiError.invalidURL(urlString)
        }

        components.queryItems = [
            URLQueryItem(name: "parent_account_id", value: parentAccountId),
            URLQueryItem(name: "status", value: status),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "page_size", value: "100")
        ]

        guard let url = components.url else {
            throw ETS100ApiError.invalidURL(urlString)
        }

        let request = buildRequest(url: url, method: "GET", token: token)

        // 作业列表 API 返回结构：{ code, msg, data: { list: [...] } }
        struct HomeworkListWrapper: Decodable {
            let code: Int
            let msg: String?
            let data: HomeworkListData?
            struct HomeworkListData: Decodable {
                let list: [HomeworkItem]?
            }
        }

        let wrapper: HomeworkListWrapper = try await execute(request, as: HomeworkListWrapper.self)

        guard wrapper.code == 0 || wrapper.code == 200 else {
            throw ETS100ApiError.httpError(wrapper.code, wrapper.msg)
        }

        return wrapper.data?.list ?? []
    }

    // MARK: - 作业详情（对照安卓 getHomeworkDetail）

    /// 获取作业详情
    func getHomeworkDetail(
        token: String,
        homeworkId: String
    ) async throws -> HomeworkDetail {
        let urlString = "\(Constants.API_BASE_URL)/api/homework/detail"
        guard var components = URLComponents(string: urlString) else {
            throw ETS100ApiError.invalidURL(urlString)
        }

        components.queryItems = [
            URLQueryItem(name: "homework_id", value: homeworkId)
        ]

        guard let url = components.url else {
            throw ETS100ApiError.invalidURL(urlString)
        }

        let request = buildRequest(url: url, method: "GET", token: token)

        return try await execute(request, as: HomeworkDetail.self)
    }

    // MARK: - 下载 ZIP 资源包（对照安卓 downloadZip）

    /// 下载资源 ZIP 包
    /// 对照安卓：从 CDN_BASE_URL 下载资源文件
    /// - Parameters:
    ///   - resourceUrl: 资源相对路径（如 "abc123.zip"）
    ///   - progressHandler: 下载进度回调
    /// - Returns: ZIP 文件的 Data
    func downloadZip(
        resourceUrl: String,
        progressHandler: (@Sendable (DownloadProgress) -> Void)? = nil
    ) async throws -> Data {
        let urlString = "\(Constants.CDN_BASE_URL)/\(resourceUrl)"
        guard let url = URL(string: urlString) else {
            throw ETS100ApiError.invalidURL(urlString)
        }

        let (bytes, response) = try await session.bytes(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ETS100ApiError.httpError(
                (response as? HTTPURLResponse)?.statusCode ?? 0,
                "下载失败"
            )
        }

        let totalBytes = Int64(httpResponse.expectedContentLength)
        var downloadedData = Data()
        var downloadedBytes: Int64 = 0

        for try await byte in bytes {
            downloadedData.append(byte)
            downloadedBytes += 1

            if let handler = progressHandler, downloadedBytes % 65536 == 0 {
                await handler(DownloadProgress(
                    downloadedBytes: downloadedBytes,
                    totalBytes: totalBytes,
                    currentFileName: resourceUrl
                ))
            }
        }

        // 最终回调
        if let handler = progressHandler {
            await handler(DownloadProgress(
                downloadedBytes: downloadedBytes,
                totalBytes: totalBytes,
                currentFileName: resourceUrl
            ))
        }

        return downloadedData
    }

    // MARK: - 检查 Token 有效性

    /// 验证 Token 是否仍然有效
    func validateToken(_ token: String) async -> Bool {
        do {
            let urlString = "\(Constants.API_BASE_URL)/api/homework/list"
            guard var components = URLComponents(string: urlString) else { return false }
            components.queryItems = [
                URLQueryItem(name: "parent_account_id", value: "0"),
                URLQueryItem(name: "status", value: "1"),
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "page_size", value: "1")
            ]
            guard let url = components.url else { return false }
            let request = buildRequest(url: url, method: "GET", token: token)
            _ = try await execute(request)
            return true
        } catch {
            return false
        }
    }
}
