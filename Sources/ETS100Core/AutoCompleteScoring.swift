import Foundation

/// ISE dimension scores. The pipeline always reports near-full dimensions so
/// that the converted score lands on the requested target band.
public struct ScoreProfile: Sendable, Hashable {
    public var total: Double
    public var accuracy: Double
    public var fluency: Double
    public var integrity: Double
    public var stress: Double

    public init(total: Double, accuracy: Double, fluency: Double, integrity: Double, stress: Double) {
        self.total = total
        self.accuracy = accuracy
        self.fluency = fluency
        self.integrity = integrity
        self.stress = stress
    }

    public static func target(ratio: Double) -> ScoreProfile {
        let value = min(1, max(0, ratio))
        return ScoreProfile(
            total: 5.0 * value,
            accuracy: 4.95 * value,
            fluency: 4.95 * value,
            integrity: 4.95 * value,
            stress: 4.90 * value
        )
    }

    public func clamped() -> ScoreProfile {
        ScoreProfile(
            total: Self.clamp(total),
            accuracy: Self.clamp(accuracy),
            fluency: Self.clamp(fluency),
            integrity: Self.clamp(integrity),
            stress: Self.clamp(stress)
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(5.0, max(0.0, value))
    }
}

/// Port of the reference `scoring.py` / `official_payload.py` helpers.
public enum AutoCompleteScoring {
    // MARK: - Numeric helpers

    /// JavaScript `Math.round` compatible rounding for the two-decimal score formatter.
    public static func roundPoints(_ value: Double) -> Double {
        (value * 100.0).rounded(.toNearestOrAwayFromZero) / 100.0
    }

    public static func formatted(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), arguments: [value])
    }

    /// `ceil((score * maximum / 5) / 0.125) * 0.125`, optionally capped at `maximum`.
    public static func convertScore(
        _ score: Double,
        maximum: Double,
        graduation: Double = 0.125,
        cap: Bool = true
    ) -> Double {
        guard maximum > 0, graduation > 0 else { return 0 }
        let raw = score * maximum / 5.0
        var converted = ceil(raw / graduation) * graduation
        converted = roundPoints(converted)
        if cap {
            converted = min(maximum, converted)
        }
        return max(0, converted)
    }

    // MARK: - score_detail

    /// Builds the mobile `score_detail` JSON. Keys mirror the captured payload:
    /// total / fluency / accuracy / integrity / standard / category / rate_scale,
    /// plus optional `choose` / `choose_id`.
    public static func scoreDetail(
        profile: ScoreProfile,
        category: String,
        choose: String = "",
        chooseID: String = "",
        clamp: Bool = true
    ) -> String {
        let value = clamp ? profile.clamped() : profile
        var pairs: [(String, JSONValue)] = [
            ("total_score", .string(formatted(value.total))),
            ("fluency_score", .string(formatted(value.fluency))),
            ("accuracy_score", .string(formatted(value.accuracy))),
            ("integrity_score", .string(formatted(value.integrity))),
            ("standard_score", .string(formatted(value.stress))),
            ("category", .string(category)),
            ("rate_scale", .int(1)),
        ]
        if !choose.isEmpty {
            pairs.append(("choose", .string(choose)))
        }
        if !chooseID.isEmpty {
            pairs.append(("choose_id", .string(chooseID)))
        }
        return JSONValue.object(JSONObject(pairs)).compactJSON
    }

    // MARK: - ISE XML

    /// Generates the per-question ISE XML accepted by `/m/audio/sync-v2`.
    public static func scoreXML(
        text: String,
        profile: ScoreProfile,
        category: String = "read_sentence",
        seed: Int = 0,
        clamp: Bool = true
    ) -> String {
        let value = clamp ? profile.clamped() : profile
        var randomizer = SeededRandom(seed: UInt64(bitPattern: Int64(seed)))

        let allowed: Set<String> = ["read_sentence", "read_chapter", "talk_recite", "talk_free"]
        let categoryName = allowed.contains(category) ? category : "read_chapter"

        let standard = bounded(value.total + randomizer.uniform(-0.1, 0.1), clamp: clamp)
        let content = xmlAttribute(text)

        var xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        xml += "<xml_result><\(categoryName)>"
        xml += "<rec_paper"
        xml += " total_score=\"\(formatted(value.total))\""
        xml += " accuracy_score=\"\(formatted(value.accuracy))\""
        xml += " fluency_score=\"\(formatted(value.fluency))\""
        xml += " integrity_score=\"\(formatted(value.integrity))\""
        xml += " standard_score=\"\(formatted(standard))\""
        xml += " stress_score=\"\(formatted(value.stress))\""
        xml += " is_rejected=\"false\""
        xml += " except_info=\"\""
        xml += " content=\"\(content)\">"

        let sentences = splitSentences(text).isEmpty ? [text] : splitSentences(text)
        for sentenceText in sentences {
            let sentenceScore = bounded(value.total + randomizer.uniform(-0.15, 0.15), clamp: clamp)
            xml += "<sentence content=\"\(xmlAttribute(sentenceText))\" total_score=\"\(formatted(sentenceScore))\">"
            for word in splitWords(sentenceText) {
                let wordScore = bounded(sentenceScore + randomizer.uniform(-0.3, 0.3), clamp: clamp)
                xml += "<word content=\"\(xmlAttribute(word))\" total_score=\"\(formatted(wordScore))\" dp_message=\"0\">"
                for symbol in phonemes(word) {
                    let score = bounded(wordScore + randomizer.uniform(-0.2, 0.2), clamp: clamp)
                    xml += "<syll content=\"\(xmlAttribute(symbol))\" score=\"\(formatted(score))\" />"
                }
                xml += "</word>"
            }
            xml += "</sentence>"
        }
        xml += "</rec_paper></\(categoryName)></xml_result>"
        return xml
    }

    /// Deterministic pseudo syllable split, mirroring the reference `_phonemes`.
    public static func phonemes(_ word: String) -> [String] {
        let letters = String(word.lowercased().unicodeScalars.filter { scalar in
            (scalar.value >= 97 && scalar.value <= 122)
        }.map(Character.init))
        guard !letters.isEmpty else { return ["*"] }
        let pairs: [String: String] = [
            "th": "θ", "sh": "ʃ", "ch": "tʃ", "wh": "w", "ph": "f", "ck": "k",
            "ng": "ŋ", "oo": "uː", "ee": "iː", "ea": "iː", "ou": "aʊ",
            "ow": "aʊ", "ai": "eɪ", "ay": "eɪ", "oi": "ɔɪ", "oy": "ɔɪ",
        ]
        let characters = Array(letters)
        var result: [String] = []
        var index = 0
        while index < characters.count {
            if index + 1 < characters.count {
                let pair = String(characters[index...index + 1])
                if let mapped = pairs[pair] {
                    result.append(mapped)
                    index += 2
                    continue
                }
            }
            result.append(String(characters[index]))
            index += 1
        }
        return result
    }

    // MARK: - Official units

    public static func toRealScore(_ point: Double) -> String {
        String(Int((point * 10_000).rounded()))
    }

    public static func toScoreRate(_ point: Double, total: Double) -> String {
        guard total > 0 else { return "0" }
        let rate = (point / total * 1_000_000).rounded()
        return String(min(1_000_000, max(0, Int(rate))))
    }

    public static func buildDetailKey(
        resourceID: String,
        setID: String,
        combination: String,
        entityID: String
    ) -> String {
        [resourceID, setID, combination, entityID].joined(separator: ":")
    }

    public static func contentType(questionType: String, typeName: String) -> String {
        let hint = "\(questionType) \(typeName)".lowercased()
        let tokens = ["read", "role", "picture", "repeat", "dialogue", "oral", "phonics", "3q5a", "sentence"]
        if tokens.contains(where: { hint.contains($0) }) {
            return "phonics"
        }
        return "read_and_write_on"
    }

    // MARK: - Private

    private static func bounded(_ value: Double, clamp: Bool) -> Double {
        clamp ? min(5.0, max(0.0, value)) : max(0.0, value)
    }

    private static func splitSentences(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func splitWords(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func xmlAttribute(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "\n": result += "&#10;"
            case "\r": result += "&#13;"
            case "\t": result += "&#9;"
            default: result.append(character)
            }
        }
        return result
    }
}

/// Small deterministic SplitMix64 generator, used to reproduce the reference
/// implementation's seeded score jitter across platforms.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func nextUnit() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value >> 11) / Double(UInt64(1) << 53)
    }

    mutating func uniform(_ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * nextUnit()
    }
}
