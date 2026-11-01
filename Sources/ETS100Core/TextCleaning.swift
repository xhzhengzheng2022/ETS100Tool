import Foundation

/// Text cleanup shared by every `structure_type` parser.
public enum ETS100Text {
    private static let prefixPattern = try! NSRegularExpression(
        pattern: "^(?:ets_[a-zA-Z0-9_]+)\\s*",
        options: [.caseInsensitive]
    )
    private static let paragraphPattern = try! NSRegularExpression(
        pattern: "</p>\\s*<p[^>]*>",
        options: [.caseInsensitive]
    )
    private static let lineBreakPattern = try! NSRegularExpression(
        pattern: "<br\\s*/?>|</br>|</p>|<p[^>]*>",
        options: [.caseInsensitive]
    )
    private static let tagPattern = try! NSRegularExpression(pattern: "<[^>]+>")

    /// Cleans a question stem or passage for display.
    public static func cleanDisplay(_ text: String, splitPipes: Bool = false) -> String {
        guard !text.isEmpty else { return "" }

        var value = text
        if splitPipes {
            value = value.replacingOccurrences(of: "|", with: "\n")
        }
        value = replace(paragraphPattern, in: value, with: "\n")
        value = replace(lineBreakPattern, in: value, with: "\n")
        value = replace(tagPattern, in: value, with: "")
        value = value.replacingOccurrences(of: "\u{200B}", with: "")
        value = decodeEntities(value)

        let lines = value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    /// Removes the internal `ets_th1` style numbering prefix.
    public static func stripInternalPrefix(_ text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return prefixPattern.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    public static func cleanQuestion(_ text: String) -> String {
        stripInternalPrefix(cleanDisplay(text))
    }

    public static func cleanAnswer(_ text: String) -> String {
        cleanDisplay(text, splitPipes: true)
    }

    public static func cleanPassage(_ text: String) -> String {
        cleanDisplay(text)
    }

    /// Returns `true` when the text contains any CJK ideograph.
    public static func containsChinese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private static func decodeEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}
