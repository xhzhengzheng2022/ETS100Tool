import Foundation

/// The `structure_type` values used by ETS100 resource packages.
public enum StructureType {
    public static let role = "collector.role"
    public static let picture = "collector.picture"
    public static let read = "collector.read"
    public static let threeQuestionsFiveAnswers = "collector.3q5a"
    public static let choose = "collector.choose"
    public static let fill = "collector.fill"
    public static let dialogue = "collector.dialogue"
    public static let repeatEssay = "collector.repeat_essay"
}

public struct ParsedContent: Sendable {
    public var structureType: String
    public var section: PaperSection

    public init(structureType: String, section: PaperSection) {
        self.structureType = structureType
        self.section = section
    }
}

/// Parses a decrypted `content.json` into the shared paper model.
///
/// The Android build delegates this step to a native resolver; the iOS build
/// implements the same rules directly from `ets100答案解析方法.md`.
public enum ContentParser {
    public static func parse(data: Data, groupName: String, startIndex: Int = 0) throws -> ParsedContent {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw ETSError.parsingFailed("content.json 不是合法 JSON")
        }
        guard let json = object as? [String: Any] else {
            throw ETSError.parsingFailed("content.json 顶层不是对象")
        }
        return try parse(json: json, groupName: groupName, startIndex: startIndex)
    }

    public static func parse(json: [String: Any], groupName: String, startIndex: Int = 0) throws -> ParsedContent {
        let structureType = string(json["structure_type"]).lowercased()
        let info = json["info"] as? [String: Any] ?? [:]
        let original = optionalClean(info["value"])

        let questions: [Question]
        switch structureType {
        case StructureType.choose:
            questions = parseChoose(info: info, original: original, startIndex: startIndex)
        case StructureType.fill:
            questions = parseFill(info: info, startIndex: startIndex)
        case StructureType.picture:
            questions = parsePicture(info: info, original: original, startIndex: startIndex)
        case StructureType.read, StructureType.repeatEssay:
            questions = parseRead(info: info, original: original, startIndex: startIndex)
        case StructureType.role, StructureType.threeQuestionsFiveAnswers, StructureType.dialogue:
            questions = parseQuestionGroup(info: info, original: original, startIndex: startIndex)
        default:
            questions = parseGeneric(info: info, original: original, startIndex: startIndex)
        }

        guard !questions.isEmpty else {
            throw ETSError.parsingFailed("未解析到题目（structure_type=\(structureType.isEmpty ? "空" : structureType)）")
        }

        let section = PaperSection(
            caption: groupName.isEmpty ? displayName(for: structureType) : groupName,
            category: structureType,
            typeName: groupName.isEmpty ? displayName(for: structureType) : groupName,
            originalContent: original,
            questions: sortByOfficialOrder(questions)
        )
        return ParsedContent(structureType: structureType, section: section)
    }

    // MARK: - Structure types

    private static func parseQuestionGroup(
        info: [String: Any],
        original: String?,
        startIndex: Int
    ) -> [Question] {
        let items = info["question"] as? [[String: Any]] ?? []
        return items.enumerated().map { offset, item in
            let displayOrder = positiveInt(item["xh"])
            let ask = ETS100Text.cleanQuestion(string(item["ask"]))
            let answers = (item["std"] as? [[String: Any]] ?? [])
                .compactMap { optionalClean($0["value"]) }
            let fallbackAnswer = optionalClean(item["answer"])

            let order = startIndex + offset + 1
            return Question(
                order: order,
                sectionOrder: offset + 1,
                questionText: ask.isEmpty ? "第\(displayOrder ?? order)题" : ask,
                answers: answers.isEmpty ? [fallbackAnswer].compactMap { $0 } : answers,
                originalText: nil,
                category: "",
                typeName: "",
                displayOrder: displayOrder
            )
        }
    }

    private static func parseChoose(
        info: [String: Any],
        original: String?,
        startIndex: Int
    ) -> [Question] {
        let items = info["xtlist"] as? [[String: Any]] ?? []
        return items.enumerated().map { offset, item in
            let displayOrder = positiveInt(item["xt_xh"]) ?? positiveInt(item["xh"])
            let questionText = ETS100Text.cleanQuestion(string(item["xt_nr"]))
            let options = (item["xxlist"] as? [[String: Any]] ?? []).compactMap { option -> String? in
                let label = string(option["xx_mc"]).trimmingCharacters(in: .whitespaces)
                let text = ETS100Text.cleanQuestion(string(option["xx_nr"]))
                guard !text.isEmpty else { return nil }
                return label.isEmpty ? text : "\(label). \(text)"
            }
            let letter = string(item["answer"]).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let matched = options.first {
                guard let first = $0.first else { return false }
                return String(first).uppercased() == letter || letter.isEmpty
            }
            let answer = letter.isEmpty ? nil : (matched ?? letter)

            let order = startIndex + offset + 1
            return Question(
                order: order,
                sectionOrder: offset + 1,
                questionText: questionText.isEmpty ? "第\(displayOrder ?? order)题" : questionText,
                answers: [answer].compactMap { $0 },
                options: options,
                correctAnswer: letter.isEmpty ? nil : letter,
                originalText: original,
                category: "",
                typeName: "",
                displayOrder: displayOrder
            )
        }
    }

    private static func parseFill(info: [String: Any], startIndex: Int) -> [Question] {
        let items = info["std"] as? [[String: Any]] ?? []
        return items.enumerated().compactMap { offset, item in
            guard let value = optionalClean(item["value"]) else { return nil }
            let displayOrder = positiveInt(item["xth"])
            let order = startIndex + offset + 1
            return Question(
                order: order,
                sectionOrder: offset + 1,
                questionText: "第\(displayOrder ?? order)题",
                answers: [value],
                originalText: nil,
                category: "",
                typeName: "",
                displayOrder: displayOrder
            )
        }
    }

    private static func parsePicture(
        info: [String: Any],
        original: String?,
        startIndex: Int
    ) -> [Question] {
        let items = info["std"] as? [[String: Any]] ?? []
        let topic = optionalClean(info["topic"]) ?? "信息转述"
        let answers = items.compactMap { optionalClean($0["value"]) }
        if answers.isEmpty {
            return [
                Question(
                    order: startIndex + 1,
                    sectionOrder: 1,
                    questionText: topic,
                    answers: [],
                    originalText: original,
                    category: "",
                    typeName: "",
                    displayOrder: nil
                ),
            ]
        }
        return answers.enumerated().map { offset, value in
            let order = startIndex + offset + 1
            let text = answers.count > 1 ? "\(topic)（第 \(offset + 1) 段）" : topic
            return Question(
                order: order,
                sectionOrder: offset + 1,
                questionText: text,
                answers: [value],
                originalText: nil,
                category: "",
                typeName: "",
                displayOrder: nil
            )
        }
    }

    private static func parseRead(
        info: [String: Any],
        original: String?,
        startIndex: Int
    ) -> [Question] {
        [
            Question(
                order: startIndex + 1,
                sectionOrder: 1,
                questionText: "模仿朗读原文",
                answers: [],
                originalText: original,
                category: "",
                typeName: "",
                displayOrder: nil
            ),
        ]
    }

    private static func parseGeneric(
        info: [String: Any],
        original: String?,
        startIndex: Int
    ) -> [Question] {
        if let list = info["xtlist"] as? [[String: Any]], !list.isEmpty {
            return parseChoose(info: info, original: original, startIndex: startIndex)
        }
        if let list = info["question"] as? [[String: Any]], !list.isEmpty {
            return parseQuestionGroup(info: info, original: original, startIndex: startIndex)
        }
        if let list = info["std"] as? [[String: Any]], !list.isEmpty {
            if list.contains(where: { $0["xth"] != nil }) {
                return parseFill(info: info, startIndex: startIndex)
            }
            return parsePicture(info: info, original: original, startIndex: startIndex)
        }
        if original != nil {
            return parseRead(info: info, original: original, startIndex: startIndex)
        }
        return []
    }

    private static func sortByOfficialOrder(_ questions: [Question]) -> [Question] {
        questions.sorted { lhs, rhs in
            let l = lhs.displayOrder ?? lhs.order
            let r = rhs.displayOrder ?? rhs.order
            if l != r { return l < r }
            return lhs.order < rhs.order
        }
    }

    private static func displayName(for structureType: String) -> String {
        switch structureType {
        case StructureType.role: return "听说问答"
        case StructureType.threeQuestionsFiveAnswers: return "3问5答"
        case StructureType.choose: return "听后选择"
        case StructureType.fill: return "听后记录"
        case StructureType.picture: return "信息转述"
        case StructureType.dialogue: return "回答问题"
        case StructureType.read, StructureType.repeatEssay: return "短文朗读"
        default: return "练习题"
        }
    }

    // MARK: - JSON helpers

    private static func string(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    private static func optionalClean(_ value: Any?) -> String? {
        let cleaned = ETS100Text.cleanAnswer(string(value))
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        let number: Int?
        if let value = value as? Int {
            number = value
        } else if let value = value as? NSNumber {
            number = value.intValue
        } else if let value = value as? String {
            number = Int(value.trimmingCharacters(in: .whitespaces))
        } else {
            number = nil
        }
        guard let number, number > 0 else { return nil }
        return number
    }
}
