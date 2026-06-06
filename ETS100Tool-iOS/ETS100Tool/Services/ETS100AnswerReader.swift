import Foundation

// MARK: - 结构类型枚举（对照安卓 StructureType）

private enum StructureType: String {
    case collectorRole = "collector.role"
    case collectorPicture = "collector.picture"
    case collectorRead = "collector.read"
    case collector3Q5A = "collector.3q5a"
    case collectorChoose = "collector.choose"
    case collectorFill = "collector.fill"
    case collectorDialogue = "collector.dialogue"
}

// MARK: - Category 到 StructureType 的映射（对照安卓 categoryToStructureType）

private let categoryToStructureType: [String: StructureType] = [
    "read_chapter":            .collectorRead,
    "simple_expression_ufi":   .collectorRole,
    "simple_expression_ufk":   .collectorRole,
    "topic":                   .collectorPicture,
    "simple_expression_ufj":   .collectorRole,
    "3q5a":                    .collector3Q5A,
    "choose":                  .collectorChoose,
    "fill":                    .collectorFill,
    "dialogue":                .collectorDialogue,
]

/// 答案解析引擎
/// 严格对照安卓 ETS100AnswerReader.kt，完成 content.json 解析、按题型组织、格式化输出
enum ETS100AnswerReader {

    // MARK: - HTML 标签清理正则

    private static let htmlTagPattern = try! NSRegularExpression(pattern: "<[^>]*>", options: [])

    /// 清理文本：移除 HTML 标签、零宽空格、多余换行
    /// 对照安卓 cleanText()
    static func cleanText(_ text: String) -> String {
        var result = text
        // 移除 HTML 标签
        result = htmlTagPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(location: 0, length: result.utf16.count),
            withTemplate: ""
        )
        // 移除零宽空格
        result = result.replacingOccurrences(of: "\u{200B}", with: "")
        result = result.replacingOccurrences(of: "\u{200C}", with: "")
        result = result.replacingOccurrences(of: "\u{200D}", with: "")
        result = result.replacingOccurrences(of: "\u{FEFF}", with: "")
        // 移除 </br>
        result = result.replacingOccurrences(of: "</br>", with: "")
        // 清理多余空白
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    /// 解析作业详情中的题型列表，提取下载信息
    /// - Parameter detail: 作业详情
    /// - Returns: [(resourceUrl, typeName, structureType)]
    static func extractQuestionTypes(from detail: HomeworkDetail) -> [(resourceUrl: String, typeName: String, structureType: String)] {
        guard let types = detail.data?.questionTypes else { return [] }
        return types.compactMap { type in
            guard let url = type.resourceUrl, !url.isEmpty else { return nil }
            return (
                resourceUrl: url,
                typeName: type.typeName ?? "未知题型",
                structureType: type.structureType ?? ""
            )
        }
    }

    /// 根据 structure_type 获取 category
    /// 对照安卓 getCategoryFromStructureType
    private static func getCategory(from structureType: String) -> String {
        switch structureType {
        case "collector.read":    return "read_chapter"
        case "collector.picture": return "topic"
        case "collector.3q5a":    return "3q5a"
        case "collector.choose":  return "choose"
        case "collector.fill":    return "fill"
        case "collector.dialogue": return "dialogue"
        default:                  return "simple_expression_ufi"
        }
    }

    // MARK: - 解析 content.json（对照安卓 parseContentJson）

    /// 解析单个 content.json，返回题目分组
    /// 对照安卓 ETS100AnswerReader.parseContentJson()
    ///
    /// 支持的 structure_type：
    /// - collector.role: 问答题（听说/问答）
    /// - collector.picture: 信息转述
    /// - collector.read: 模仿朗读
    /// - collector.3q5a: 广东 3问5答
    /// - collector.choose: 北京听后选择
    /// - collector.fill: 北京听后记录
    /// - collector.dialogue: 北京回答问题
    static func parseContentJSON(
        _ jsonData: Data,
        typeName: String,
        sectionCaption: String,
        structureType: String? = nil
    ) throws -> [QuestionGroup] {

        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        guard let info = json?["info"] as? [String: Any] else {
            return []
        }

        // 确定 structure_type（优先显式传入，否则从 category 映射）
        let structTypeStr = structureType ?? ""
        let structType = StructureType(rawValue: structTypeStr) ?? .collectorRole

        // 提取原文 info.value
        let infoValue = (info["value"] as? String) ?? ""
        let originalContent = cleanText(infoValue).nilIfEmpty

        var groups: [QuestionGroup] = []
        var questions: [QuestionItem] = []
        var globalIndex = 0

        switch structType {

        // MARK: collector.read — 模仿朗读（无答案）
        case .collectorRead:
            questions.append(QuestionItem(
                order: 1, sectionOrder: 1,
                sectionCaption: sectionCaption, typeName: typeName,
                questionText: "模仿朗读原文",
                answers: [],
                originalText: originalContent,
                category: "read_chapter"
            ))

        // MARK: collector.picture — 信息转述
        case .collectorPicture:
            let answers = extractStdAnswers(from: info)
            let topicTitle = (info["topic"] as? String) ?? "信息转述"
            let displayOrder = extractQuestionNumber(from: info, keys: ["topic", "value"])

            questions.append(QuestionItem(
                order: 1, sectionOrder: 1,
                sectionCaption: sectionCaption, typeName: typeName,
                questionText: topicTitle,
                answers: answers,
                originalText: originalContent,
                category: "topic",
                displayOrder: displayOrder
            ))

        // MARK: collector.role — 问答题
        case .collectorRole:
            let questionsArray = (info["question"] as? [[String: Any]]) ?? (info["questions"] as? [[String: Any]]) ?? []
            if !questionsArray.isEmpty {
                for (i, q) in questionsArray.enumerated() {
                    let askText = cleanText((q["ask"] as? String) ?? "")
                    let qText = askText.nilIfEmpty ?? (q["question"] as? String) ?? (q["text"] as? String) ?? ""
                    let displayOrder = extractQuestionNumber(from: q, keys: ["ask", "question", "text"])
                    let answers = extractStdAnswers(from: q)

                    questions.append(QuestionItem(
                        order: globalIndex + i + 1, sectionOrder: i + 1,
                        sectionCaption: sectionCaption, typeName: typeName,
                        questionText: qText,
                        answers: answers,
                        originalText: originalContent,
                        category: "simple_expression_ufi",
                        displayOrder: displayOrder
                    ))
                }
            } else if let orig = originalContent {
                questions.append(QuestionItem(
                    order: 1, sectionOrder: 1,
                    sectionCaption: sectionCaption, typeName: typeName,
                    questionText: "阅读理解原文",
                    answers: [orig],
                    originalText: orig,
                    category: "simple_expression_ufi"
                ))
            }

        // MARK: collector.3q5a — 广东 3问5答
        case .collector3Q5A:
            let questionsArray = (info["question"] as? [[String: Any]]) ?? (info["questions"] as? [[String: Any]]) ?? []
            for (i, q) in questionsArray.enumerated() {
                let askText = cleanText((q["ask"] as? String) ?? "")
                let qText = askText.nilIfEmpty ?? (q["question"] as? String) ?? (q["text"] as? String) ?? ""
                let displayOrder = extractQuestionNumber(from: q, keys: ["ask", "question", "text"])
                let answers = extractStdAnswers(from: q)

                questions.append(QuestionItem(
                    order: globalIndex + i + 1, sectionOrder: i + 1,
                    sectionCaption: sectionCaption, typeName: typeName,
                    questionText: qText,
                    answers: answers,
                    originalText: originalContent,
                    category: "3q5a",
                    displayOrder: displayOrder
                ))
            }

        // MARK: collector.choose — 北京听后选择
        case .collectorChoose:
            let xtlist = info["xtlist"] as? [[String: Any]] ?? []
            for (i, item) in xtlist.enumerated() {
                let qText = cleanText((item["xt_nr"] as? String) ?? "")
                let answer = item["answer"] as? String ?? ""
                let xxlist = item["xxlist"] as? [[String: Any]] ?? []

                let options = xxlist.map { opt in
                    let mc = opt["xx_mc"] as? String ?? ""
                    let nr = cleanText((opt["xx_nr"] as? String) ?? "")
                    return "\(mc). \(nr)"
                }

                let answerText: String
                if options.isEmpty {
                    answerText = "正确答案: \(answer)"
                } else {
                    answerText = options.joined(separator: "\n") + "\n正确答案: \(answer)"
                }

                questions.append(QuestionItem(
                    order: globalIndex + i + 1, sectionOrder: i + 1,
                    sectionCaption: sectionCaption, typeName: typeName,
                    questionText: qText,
                    answers: [answerText],
                    originalText: originalContent,
                    category: "choose",
                    displayOrder: extractChooseQuestionNumber(from: item)
                ))
            }

        // MARK: collector.fill — 北京听后记录
        case .collectorFill:
            let stdArray = info["std"] as? [[String: Any]] ?? []
            for (i, item) in stdArray.enumerated() {
                let number = item["xth"] as? String ?? ""
                let answer = cleanText((item["value"] as? String) ?? "")

                questions.append(QuestionItem(
                    order: globalIndex + i + 1, sectionOrder: i + 1,
                    sectionCaption: sectionCaption, typeName: typeName,
                    questionText: "第\(number)题",
                    answers: [answer],
                    originalText: nil,
                    category: "fill",
                    displayOrder: extractQuestionNumber(from: item, keys: ["xth", "value"])
                ))
            }

        // MARK: collector.dialogue — 北京回答问题
        case .collectorDialogue:
            let questionsArray = (info["question"] as? [[String: Any]]) ?? (info["questions"] as? [[String: Any]]) ?? []
            for (i, q) in questionsArray.enumerated() {
                let askText = cleanText((q["ask"] as? String) ?? "")
                let qText = askText.nilIfEmpty ?? (q["question"] as? String) ?? (q["text"] as? String) ?? ""
                let displayOrder = extractQuestionNumber(from: q, keys: ["ask", "question", "text"])
                let answers = extractStdAnswers(from: q)

                questions.append(QuestionItem(
                    order: globalIndex + i + 1, sectionOrder: i + 1,
                    sectionCaption: sectionCaption, typeName: typeName,
                    questionText: qText,
                    answers: answers,
                    originalText: originalContent,
                    category: "dialogue",
                    displayOrder: displayOrder
                ))
            }
        }

        // 按 displayOrder 排序（对照安卓 sortQuestionsByOfficialOrder）
        let sorted = questions.sorted { a, b in
            let orderA = a.displayOrder ?? a.sectionOrder
            let orderB = b.displayOrder ?? b.sectionOrder
            return orderA < orderB
        }

        if !sorted.isEmpty {
            let category = getCategory(from: structTypeStr)
            let group = QuestionGroup(
                caption: sectionCaption,
                category: category,
                typeName: typeName,
                questions: sorted,
                originalContent: originalContent
            )
            groups.append(group)
        }

        return groups
    }

    // MARK: - 批量解析 ZIP 数据（用于云端模式）

    /// 从 ZIP 数据中解析所有 content.json
    /// - Parameters:
    ///   - zipData: 每个 ZIP 的原始数据
    ///   - passwords: ZIP 文件名 -> 解压密码
    ///   - typeInfo: 题型信息
    /// - Returns: 所有题目分组
    static func parseAllFromZips(
        zipDataList: [(fileName: String, data: Data)],
        passwords: [String: String],
        typeInfos: [(resourceUrl: String, typeName: String, structureType: String)]
    ) throws -> PaperInfo {
        var allGroups: [QuestionGroup] = []
        let paperId = Int(Date().timeIntervalSince1970)

        for (fileName, zipData) in zipDataList {
            // 确定密码
            guard let password = passwords[fileName] else {
                continue
            }

            // 解压 ZIP（使用 libcompression 或 ZIPFoundation）
            // 这里返回模拟结构 — 实际需要 ZIPFoundation 库
            // 在 iOS 中建议使用 ZIPFoundation 库
            let resourceDirName = fileName.replacingOccurrences(of: ".zip", with: "")

            // 查找该 fileName 对应的 typeInfo
            let matchingType = typeInfos.first { info in
                let name = fileName.replacingOccurrences(of: ".zip", with: "")
                return info.resourceUrl.contains(name)
            }

            let typeName = matchingType?.typeName ?? "未知题型"
            let structureType = matchingType?.structureType ?? ""

            // content.json 路径：{resourceDirName}/content.json
            let contentJSON = extractContentJSON(from: zipData, password: password)

            if let jsonData = contentJSON {
                let groups = try parseContentJSON(
                    jsonData,
                    typeName: typeName,
                    sectionCaption: typeName,
                    structureType: structureType
                )
                allGroups.append(contentsOf: groups)
            }
        }

        return PaperInfo(
            paperId: paperId,
            title: "云端作业",
            groups: allGroups,
            downloadTime: Date(),
            regionLabel: "云端"
        )
    }

    // MARK: - ZIP 解压辅助

    /// 从 ZIP 数据中提取 resourceDirName/content.json
    /// 实际实现需要使用 ZIPFoundation 库，这里提供框架代码
    static func extractContentJSON(from zipData: Data, password: String) -> Data? {
        // 使用 libcompression + minizip 或 ZIPFoundation
        // 框架代码：实际运行时需替换为 ZIPFoundation API
        // let archive = try Archive(data: zipData, accessMode: .read)
        // guard let entry = archive["content.json"] else { return nil }
        // var data = Data()
        // _ = try archive.extract(entry) { data.append($0) }
        // return data

        // 由于当前环境无 ZIPFoundation，返回 nil
        // 实际项目中应添加 SPM 依赖: https://github.com/weichsel/ZIPFoundation.git
        return nil
    }

    // MARK: - 辅助方法

    /// 提取 std[].value 答案
    private static func extractStdAnswers(from dict: [String: Any]) -> [String] {
        guard let stdArray = dict["std"] as? [[String: Any]], !stdArray.isEmpty else {
            return ["暂无标准答案"]
        }
        return stdArray.compactMap { item in
            let value = (item["value"] as? String) ?? ""
            let cleaned = cleanText(value)
            return cleaned.nilIfEmpty
        }
    }

    /// 从字典中提取题号（对照安卓 extractQuestionNumber）
    private static func extractQuestionNumber(from dict: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = dict[key] as? String {
                let cleaned = cleanText(value)
                if let num = Int(cleaned) {
                    return num
                }
                // 尝试从文本开头提取数字
                let scanner = Scanner(string: cleaned)
                var intVal: Int = 0
                if scanner.scanInt(&intVal) {
                    return intVal
                }
            }
        }
        return nil
    }

    /// 从选择题 xtlist 项中提取题号
    private static func extractChooseQuestionNumber(from item: [String: Any]) -> Int? {
        // 尝试 xt_mc 如 "1." 或 xt_xuhao
        for key in ["xt_mc", "xt_xuhao", "xt_nr"] {
            if let value = item[key] as? String {
                let cleaned = cleanText(value)
                    .replacingOccurrences(of: ".", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if let num = Int(cleaned) {
                    return num
                }
            }
        }
        return nil
    }
}

// MARK: - String 扩展

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
