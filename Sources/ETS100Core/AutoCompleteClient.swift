import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Thin wrapper around the official routes required by the auto-complete
/// pipeline. Every request is signed with the same envelope as the read-only
/// client, so no new protocol surface is introduced.
public final class AutoCompleteClient: @unchecked Sendable {
    private let api: ETS100APIClient
    private let ossSession: URLSession

    public init(api: ETS100APIClient) {
        self.api = api
        self.ossSession = CDNTrustPolicy.makeSession()
    }

    // MARK: - Official endpoints

    public func checkStart(homeworkID: String, token: String) async throws -> [String: Any] {
        var params = common(token: token)
        params["homework_id"] = .int(Int(homeworkID) ?? 0)
        return try await call("g/homework/checkstart", params)
    }

    public func pprResources(batch: [JSONObject], token: String) async throws -> [String: Any] {
        var params = common(token: token)
        params["batch"] = .array(batch.map { .object($0) })
        return try await call("g/set/ppr-res", params)
    }

    public func preUpload(token: String) async throws -> [String: Any] {
        try await call("m/file/pre-upload", common(token: token))
    }

    public func ossConfig(type: String, id: String, token: String) async throws -> [String: Any] {
        var params = common(token: token)
        params["type"] = .string(type)
        params["id"] = .string(id)
        return try await call("system/oss-config", params)
    }

    public func syncQuestion(_ parameters: JSONObject, token: String) async throws -> [String: Any] {
        var params = common(token: token)
        params.merge(parameters)
        params["parent_account_id"] = nil
        return try await call("m/audio/sync-v2", params)
    }

    public func setUseTime(_ parameters: JSONObject, token: String) async throws -> [String: Any] {
        var params = common(token: token)
        params.merge(parameters)
        params["parent_account_id"] = nil
        return try await call("m/homework/set-use-time", params)
    }

    public func reportScore(
        _ parameters: JSONObject,
        parentAccountID: String,
        token: String
    ) async throws -> [String: Any] {
        var params = common(token: token)
        params.merge(parameters)
        if params["parent_account_id"] == nil, !parentAccountID.isEmpty {
            params["parent_account_id"] = .string(parentAccountID)
        }
        return try await call("g/homework/report-score", params)
    }

    public func submitHomework(_ parameters: JSONObject, token: String) async throws -> [String: Any] {
        var params = common(token: token)
        params.merge(parameters)
        return try await call("m/homework/submit", params)
    }

    public func scoreDrop(homeworkID: String, token: String) async throws -> [String: Any] {
        var params = common(token: token)
        params["homework_id"] = JSONValue.intOrString(homeworkID)
        params["resource_id"] = .string("")
        params["seq_id"] = .string("")
        return try await call("g/homework/score-drop", params)
    }

    public func homeworkInfo(
        homeworkID: String,
        resourceID: String,
        parentAccountID: String,
        token: String
    ) async throws -> [String: Any] {
        var params = common(token: token)
        params["homework_id"] = .string(homeworkID)
        params["resource_id"] = .string(resourceID)
        params["version"] = .string("2")
        if !parentAccountID.isEmpty {
            params["parent_account_id"] = .string(parentAccountID)
        }
        return try await call("m/homework/info", params)
    }

    // MARK: - OSS upload

    /// Uploads a single file through the multipart form returned by `/system/oss-config`.
    /// Returns the public URL of the uploaded object.
    public func uploadOSSForm(
        host: String,
        dirName: String,
        fileName: String,
        accessID: String,
        policy: String,
        signature: String,
        callback: String,
        content: Data
    ) async throws -> String {
        let base = host.hasSuffix("/") ? host : host + "/"
        guard let url = URL(string: base) else { throw ETSError.invalidResponse }

        var lastError: Error = ETSError.invalidResponse
        for attempt in 1...3 {
            let boundary = "------------------------" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            var body = Data()
            func append(_ value: String) {
                body.append(Data(value.utf8))
            }

            let fields: [(String, String)] = [
                ("name", fileName),
                ("key", dirName + fileName),
                ("OSSAccessKeyId", accessID),
                ("policy", policy),
                ("signature", signature),
                ("callback", callback),
            ]
            for (name, value) in fields {
                append("--\(boundary)\r\n")
                append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
                append(value)
                append("\r\n")
            }
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
            append("Content-Type: application/octet-stream\r\n\r\n")
            body.append(content)
            append("\r\n--\(boundary)--\r\n")

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = body
            request.timeoutInterval = 60
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            do {
                let (_, response) = try await ossSession.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw ETSError.invalidResponse
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw ETSError.http(status: http.statusCode)
                }
                return base + dirName + fileName
            } catch {
                lastError = error
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }
        throw lastError
    }

    // MARK: - Request plumbing

    private func common(token: String) -> JSONObject {
        JSONObject([
            ("sn", .string(ETSConfig.Device.sn)),
            ("token", .string(token)),
            ("version", .string(ETSConfig.Device.loginVersion)),
            ("system", .string(ETSConfig.Device.system)),
            ("global_client_version", .string(ETSConfig.Device.clientVersion)),
            ("sign_response", .int(1)),
        ])
    }

    private func call(_ route: String, _ params: JSONObject) async throws -> [String: Any] {
        let response = try await api.post(route: route, params: params)
        let code = JSONReader.optionalInt(response["code"]) ?? 0
        if code != 0 {
            throw ETSError.server(code: code, message: JSONReader.string(response["msg"]))
        }
        return (try? api.bodyObject(response)) ?? [:]
    }
}

// MARK: - Untyped JSON bridging

extension JSONObject {
    mutating func merge(_ other: JSONObject) {
        for pair in other.pairs {
            self[pair.key] = pair.value
        }
    }
}

extension JSONValue {
    static func from(_ value: Any) -> JSONValue {
        switch value {
        case let value as String: return .string(value)
        case let value as Int: return .int(value)
        case let value as Double: return .double(value)
        case let value as Bool: return .bool(value)
        case let value as [Any]: return .array(value.map(JSONValue.from))
        case let value as [String: Any]:
            let pairs = value.keys.sorted().map { key in (key, JSONValue.from(value[key]!)) }
            return .object(JSONObject(pairs))
        case let value as NSNumber:
            let type = String(cString: value.objCType)
            if type == "c" || type == "B" { return .bool(value.boolValue) }
            if type == "f" || type == "d" { return .double(value.doubleValue) }
            return .int(value.intValue)
        default: return .null
        }
    }

    static func from(_ value: Any, into object: inout JSONObject) {
        guard let dictionary = value as? [String: Any] else { return }
        for key in dictionary.keys.sorted() {
            object[key] = JSONValue.from(dictionary[key]!)
        }
    }

    static func intOrString(_ value: String) -> JSONValue {
        if let number = Int(value) { return .int(number) }
        return .string(value)
    }
}
