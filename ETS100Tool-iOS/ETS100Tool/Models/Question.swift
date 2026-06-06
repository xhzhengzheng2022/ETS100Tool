import Foundation

/// 单题数据模型
/// 对照安卓 ETS100AnswerReader.kt 中的 Question data class
struct QuestionItem: Codable, Identifiable, Hashable {
    /// 全局题号（从 1 开始）
    let order: Int
    /// 分组内题号
    let sectionOrder: Int
    /// 所属分组标题
    let sectionCaption: String
    /// 题型名称
    let typeName: String
    /// 问题文本
    let questionText: String
    /// 答案列表
    let answers: [String]
    /// 原文（部分题型有，如模仿朗读、信息转述）
    let originalText: String?
    /// 题目类别
    let category: String
    /// 官方排序序号（从 JSON 中提取，用于保持原始顺序）
    let displayOrder: Int?

    var id: String { "\(order)_\(sectionCaption)_\(sectionOrder)" }

    /// 截断的题目文本（用于列表预览）
    var truncatedQuestionText: String {
        questionText.count > 50
            ? String(questionText.prefix(50)) + "..."
            : questionText
    }

    /// 答案文本（多个答案用换行拼接）
    var joinedAnswers: String {
        answers.joined(separator: "\n")
    }

    init(
        order: Int,
        sectionOrder: Int,
        sectionCaption: String,
        typeName: String,
        questionText: String,
        answers: [String],
        originalText: String? = nil,
        category: String,
        displayOrder: Int? = nil
    ) {
        self.order = order
        self.sectionOrder = sectionOrder
        self.sectionCaption = sectionCaption
        self.typeName = typeName
        self.questionText = questionText
        self.answers = answers
        self.originalText = originalText
        self.category = category
        self.displayOrder = displayOrder
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: QuestionItem, rhs: QuestionItem) -> Bool {
        lhs.id == rhs.id
    }
}
