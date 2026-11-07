import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct LoginResult: Sendable {
    public var token: String
    public var recentAccountID: String?

    public init(token: String, recentAccountID: String? = nil) {
        self.token = token
        self.recentAccountID = recentAccountID
    }
}

public enum HomeworkStatus {
    public static let current = "1"
    public static let history = "2"
    public static let expired = "3"

    public static func title(_ status: String) -> String {
        switch status {
        case current: return "当前作业"
        case history: return "历史作业"
        case expired: return "已过期"
        default: return "作业"
        }
    }
}

/// HTTP client for the ETS100 gateway. Request construction mirrors the
/// Android client exactly so signatures remain byte-identical.
public final class ETS100APIClient: @unchecked Sendable {
    public enum Endpoint {
        public static let login = "/user/login"
        public static let loginZt = "/user/login-zt"
        public static let rebindCode = "/user/rebind-code"
        public static let sendUserExist = "/code/send-user-exist"
        public static let ecardList = "/m/ecard/list"
        public static let homeworkList = "/g/homework/list"
    }

    private let baseURL: URL
    private let session: URLSession

    public init(
        baseURL: URL = ETSConfig.apiBaseURL,
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = ETSConfig.requestTimeout
            configuration.timeoutIntervalForResource = ETSConfig.requestTimeout
            self.session = URLSession(configuration: configuration)
        }
    }

    // MARK: - Public API

    public func login(phone: String, password: String, deviceCode: String) async throws -> LoginResult {
        let params = JSONObject([
            ("sn", .string(ETSConfig.Device.sn)),
            ("phone", .string(phone)),
            ("password", .string(password)),
            ("device_code", .string(deviceCode)),
            ("device_name", .string(ETSConfig.Device.loginDeviceName)),
            ("version", .string(ETSConfig.Device.loginVersion)),
            ("local_ip", .string(ETSConfig.Device.localIP)),
            ("system", .string(ETSConfig.Device.system)),
            ("global_client_version", .string(ETSConfig.Device.clientVersion)),
            ("sign_response", .int(1)),
        ])
        let response = try await post(route: "user/login", params: params)
        let code = JSONReader.optionalInt(response["code"])
        if let code, code != 0 {
            switch code {
            case 30008: throw ETSError.smsRequired
            case 30014: throw ETSError.deviceBindRequired
            default: throw ETSError.server(code: code, message: JSONReader.string(response["msg"]))
            }
        }
        let body = try bodyObject(response)
        guard let token = JSONReader.optionalString(body["token"]) else {
            throw ETSError.missingToken
        }
        return LoginResult(
            token: token,
            recentAccountID: JSONReader.optionalString(body["recent_account_id"])
        )
    }

    public func bindDevice(
        phone: String,
        password: String,
        deviceCode: String,
        verificationCode: String = "0"
    ) async throws -> LoginResult {
        let params = JSONObject([
            ("sn", .string(ETSConfig.Device.sn)),
            ("phone", .string(phone)),
            ("email", .string("")),
            ("password", .string(password)),
            ("code", .string(verificationCode)),
            ("version", .string(ETSConfig.Device.rebindVersion)),
            ("device_name", .string(ETSConfig.Device.rebindDeviceName)),
            ("device_code", .string(deviceCode)),
            ("local_ip", .string(ETSConfig.Device.localIP)),
            ("system", .string(ETSConfig.Device.system)),
            ("global_client_version", .string(ETSConfig.Device.clientVersion)),
            ("sign_response", .int(1)),
        ])
        let response = try await post(route: "user/rebind-code", params: params)
        let code = JSONReader.optionalInt(response["code"])
        if let code, code != 0 {
            if code == 60001 { throw ETSError.smsCodeInvalid }
            throw ETSError.server(code: code, message: JSONReader.string(response["msg"]))
        }
        let body = try bodyObject(response)
        guard let token = JSONReader.optionalString(body["token"]) else {
            throw ETSError.missingToken
        }
        return LoginResult(token: token)
    }

    public func sendBindingCode(phone: String) async throws {
        let params = JSONObject([
            ("sn", .string(ETSConfig.Device.sn)),
            ("phone", .string(phone)),
            ("email", .string("")),
            ("class_id", .string("1")),
            ("use", .string("3")),
            ("system", .string(ETSConfig.Device.system)),
            ("global_client_version", .string("")),
            ("sign_response", .int(1)),
        ])
        let response = try await post(route: "code/send-user-exist", params: params)
        if let code = JSONReader.optionalInt(response["code"]), code != 0 {
            throw ETSError.server(code: code, message: JSONReader.string(response["msg"]))
        }
    }

    public func refreshToken(_ token: String) async throws -> String {
        let params = JSONObject([
            ("token", .string(token)),
            ("version", .string(ETSConfig.Device.rebindVersion)),
            ("system", .string(ETSConfig.Device.system)),
        ])
        let response = try await post(route: "user/rebind-code", params: params)
        let body = try bodyObject(response)
        guard let refreshed = JSONReader.optionalString(body["token"]) else {
            throw ETSError.server(code: 0, message: "Token 刷新失败")
        }
        return refreshed
    }

    public func ecardSelection(token: String, preferredAccountID: String? = nil) async throws -> EcardSelection {
        let params = JSONObject([
            ("sn", .string(ETSConfig.Device.sn)),
            ("token", .string(token)),
            ("version", .string(ETSConfig.Device.loginVersion)),
            ("system", .string(ETSConfig.Device.system)),
            ("global_client_version", .string(ETSConfig.Device.clientVersion)),
            ("sign_response", .int(1)),
        ])
        let response = try await post(route: "m/ecard/list", params: params)
        let body = try bodyObject(response)

        let accounts = body.keys
            .sorted { lhs, rhs in
                if let left = Int(lhs), let right = Int(rhs) { return left < right }
                return lhs < rhs
            }
            .compactMap { key -> EcardAccount? in
                guard let account = body[key] as? [String: Any] else { return nil }
                return Self.makeAccount(key: key, json: account)
            }

        guard let selected = Self.selectAccount(accounts, preferredAccountID: preferredAccountID) else {
            throw ETSError.missingAccount
        }
        guard !selected.parentID.isEmpty else { throw ETSError.missingAccount }
        return EcardSelection(
            parentAccountID: selected.parentID,
            selectedAccount: selected,
            validAccounts: accounts.filter { $0.isValid }
        )
    }

    public func homeworkList(
        token: String,
        parentAccountID: String,
        status: String = HomeworkStatus.current
    ) async throws -> HomeworkList {
        let params = JSONObject([
            ("sn", .string(ETSConfig.Device.sn)),
            ("token", .string(token)),
            ("parent_account_id", .string(parentAccountID)),
            ("limit", .string("0")),
            ("status", .string(status)),
            ("offset", .string("0")),
            ("max_end_time", .string("")),
            ("max_homework_id", .string("")),
            ("min_end_time", .string("")),
            ("min_homework_id", .string("")),
            ("get_to_do_count", .int(1)),
            ("show_old_homework", .int(1)),
            ("parent_homework_id", .string("")),
            ("get_all_count", .int(1)),
            ("check_pass", .int(1)),
            ("get_to_overtime_count", .int(1)),
            ("version", .string(ETSConfig.Device.loginVersion)),
            ("system", .string(ETSConfig.Device.system)),
            ("global_client_version", .string(ETSConfig.Device.clientVersion)),
            ("sign_response", .int(1)),
        ])
        let response = try await post(route: "g/homework/list", params: params)
        guard let body = try? bodyObject(response) else {
            throw ETSError.server(
                code: JSONReader.optionalInt(response["code"]) ?? 0,
                message: JSONReader.string(response["msg"]).ifEmpty("作业列表获取失败")
            )
        }

        let baseURL = JSONReader.optionalString(body["base_url"]) ?? ETSConfig.cdnBaseURL
        let rows = (body["data"] as? [[String: Any]]) ?? []
        let homeworks = rows.map { row -> HomeworkItem in
            let structObject = row["struct"] as? [String: Any]
            let contentRows = (structObject?["contents"] as? [[String: Any]]) ?? []
            let contents = contentRows.map { content in
                HomeworkContent(
                    groupName: JSONReader.string(content["group_name"]),
                    url: JSONReader.string(content["url"]),
                    realID: JSONReader.string(content["real_id"] ?? content["entity_id"])
                )
            }
            let point: Double? = {
                guard let raw = row["point"], !(raw is NSNull) else { return nil }
                return JSONReader.optionalDouble(raw)
            }()
            return HomeworkItem(
                id: JSONReader.string(row["id"]),
                name: JSONReader.string(row["name"]).ifEmpty("未知作业"),
                contents: contents,
                setType: JSONReader.int(row["set_type"]),
                pk: JSONReader.int(row["pk"]),
                resourceID: JSONReader.string(row["resource_id"])
                    .ifEmpty(JSONReader.string(row["res_id"]))
                    .ifEmpty(JSONReader.string(row["resId"])),
                totalScore: JSONReader.optionalDouble(row["total_score"] ?? row["score_total_point"]) ?? 0,
                point: point,
                useTime: JSONReader.int(row["use_time"] ?? structObject?["use_time"]),
                status: JSONReader.string(row["status"]).ifEmpty(status),
                setID: JSONReader.optionalString(structObject?["set_id"]),
                structTotalPoint: JSONReader.optionalDouble(structObject?["total_point"])
            )
        }
        return HomeworkList(baseURL: baseURL, homeworks: homeworks)
    }

    // MARK: - Request plumbing

    public static func sign(timestamp: Int, bodyBase64: String) -> String {
        MD5.hash(ETSConfig.pid + String(timestamp) + bodyBase64 + ETSConfig.secretKey)
    }

    /// Builds the signed envelope. Exposed for unit tests.
    public static func payload(route: String, params: JSONObject, timestamp: Int) -> String {
        let bodyData = JSONValue.array([
            .object(JSONObject([
                ("r", .string(route)),
                ("params", .object(params)),
            ])),
        ])
        let bodyJSON = bodyData.compactJSON
        let bodyBase64 = Data(bodyJSON.utf8).base64EncodedString()
        let signature = sign(timestamp: timestamp, bodyBase64: bodyBase64)
        let envelope = JSONValue.object(JSONObject([
            ("body", .string(bodyBase64)),
            ("head", .object(JSONObject([
                ("version", .string("1.0")),
                ("sign", .string(signature)),
                ("pid", .string(ETSConfig.pid)),
                ("time", .int(timestamp)),
            ]))),
        ]))
        return envelope.compactJSON
    }

    func post(route: String, params: JSONObject) async throws -> [String: Any] {
        guard let url = URL(string: ETSConfig.apiBaseURL.absoluteString + "/" + route) else {
            throw ETSError.invalidResponse
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let payload = Self.payload(route: route, params: params, timestamp: timestamp)
        guard let data = payload.data(using: .utf8) else { throw ETSError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.timeoutInterval = ETSConfig.requestTimeout
        request.setValue("api.ets100.com", forHTTPHeaderField: "Host")
        request.setValue("libcurl-agent/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.data(for: request)
        } catch {
            throw ETSError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ETSError.http(status: http.statusCode)
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: responseData, options: [])
        } catch {
            throw ETSError.invalidResponse
        }
        if let array = object as? [Any], let first = array.first as? [String: Any] {
            return first
        }
        if let dictionary = object as? [String: Any] {
            return dictionary
        }
        throw ETSError.invalidResponse
    }

    func bodyObject(_ response: [String: Any]) throws -> [String: Any] {
        if let body = response["body"] as? [String: Any] {
            return body
        }
        if let body = response["body"] as? String {
            if let data = Data(base64Encoded: body),
               let object = try? JSONSerialization.jsonObject(with: data),
               let dictionary = object as? [String: Any] {
                return dictionary
            }
            if let data = body.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data),
               let dictionary = object as? [String: Any] {
                return dictionary
            }
        }
        throw ETSError.invalidResponse
    }

    // MARK: - Mapping

    private static func makeAccount(key: String, json: [String: Any]) -> EcardAccount {
        EcardAccount(
            key: key,
            id: JSONReader.string(json["id"]),
            parentID: JSONReader.string(json["parent_id"]),
            userAccountID: JSONReader.string(json["user_account_id"]),
            name: JSONReader.string(json["name"]),
            grade: JSONReader.string(json["grade"]),
            status: JSONReader.string(json["status"]),
            mobileStatus: JSONReader.string(json["mobile_status"]),
            outOfDate: JSONReader.string(json["out_of_date"]),
            classID: JSONReader.string(json["class_id"]),
            className: JSONReader.string(json["class_name"]),
            machineCodeStatus: JSONReader.string(json["machine_code_status"])
        )
    }

    private static func selectAccount(
        _ accounts: [EcardAccount],
        preferredAccountID: String?
    ) -> EcardAccount? {
        if let preferredAccountID, !preferredAccountID.isEmpty,
           let account = accounts.first(where: { $0.id == preferredAccountID && $0.isValid }) {
            return account
        }
        if let account = accounts.first(where: \.isValid) {
            return account
        }
        return accounts.first
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
