import Foundation

/// A minimal JSON value type with deterministic, order-preserving, compact
/// serialization. The ETS100 signature is computed over the exact bytes of the
/// encoded body, so Foundation's `JSONSerialization` (which may reorder keys and
/// add whitespace) cannot be used for outgoing payloads.
public enum JSONValue: Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object(JSONObject)
}

public struct JSONObject: Sendable {
    public var pairs: [(key: String, value: JSONValue)]

    public init(_ pairs: [(String, JSONValue)] = []) {
        self.pairs = pairs
    }

    public init(anyValues: [String: Any]) {
        var object = JSONObject()
        for key in anyValues.keys.sorted() {
            object[key] = JSONValue.from(anyValues[key]!)
        }
        self = object
    }

    public subscript(key: String) -> JSONValue? {
        get { pairs.first { $0.key == key }?.value }
        set {
            if let index = pairs.firstIndex(where: { $0.key == key }) {
                if let newValue {
                    pairs[index].value = newValue
                } else {
                    pairs.remove(at: index)
                }
            } else if let newValue {
                pairs.append((key, newValue))
            }
        }
    }
}

extension JSONValue {
    /// Compact JSON encoding (no whitespace, UTF-8, forward slashes unescaped).
    public var compactJSON: String {
        switch self {
        case .string(let value):
            return Self.escape(value)
        case .int(let value):
            return String(value)
        case .double(let value):
            return value.rounded() == value ? String(Int(value)) : String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return "null"
        case .array(let values):
            return "[" + values.map(\.compactJSON).joined(separator: ",") + "]"
        case .object(let object):
            let body = object.pairs
                .map { Self.escape($0.key) + ":" + $0.value.compactJSON }
                .joined(separator: ",")
            return "{" + body + "}"
        }
    }

    private static func escape(_ value: String) -> String {
        var result = "\""
        result.reserveCapacity(value.count + 2)
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{08}": result += "\\b"
            case "\u{0C}": result += "\\f"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        result += "\""
        return result
    }
}

/// Small helpers for reading untyped JSON responses.
public enum JSONReader {
    public static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    public static func array(_ value: Any?) -> [[String: Any]] {
        value as? [[String: Any]] ?? []
    }

    public static func string(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    public static func optionalString(_ value: Any?) -> String? {
        let string = string(value)
        return string.isEmpty ? nil : string
    }

    public static func int(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) ?? 0 }
        return 0
    }

    public static func optionalInt(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    public static func double(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) ?? 0 }
        return 0
    }

    public static func optionalDouble(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
}
