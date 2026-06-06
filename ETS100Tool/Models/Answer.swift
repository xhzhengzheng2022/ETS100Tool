import Foundation

/// 答案展示项的视图数据结构
/// 用于 SwiftUI 列表中展示，不用于持久化
struct AnswerDisplayItem: Identifiable, Hashable {
    let id: String
    let groupIndex: Int          // 题型分组索引
    let groupCaption: String     // 分组标题
    let category: String         // 类别
    let typeName: String         // 题型名称
    let categoryColorHex: String // 颜色
    let questionIndex: Int       // 题号
    let questionText: String     // 问题
    let answers: [String]        // 答案列表
    let originalText: String?    // 原文

    init(groupIndex: Int, group: QuestionGroup, question: QuestionItem) {
        self.id = "\(groupIndex)_\(question.order)"
        self.groupIndex = groupIndex
        self.groupCaption = group.caption
        self.category = group.category
        self.typeName = group.typeName
        self.categoryColorHex = group.categoryColorHex
        self.questionIndex = question.order
        self.questionText = question.questionText
        self.answers = question.answers
        self.originalText = question.originalText
    }
}

/// 答案汇总数据（用于详情页展示）
struct AnswerSummary {
    let paperTitle: String
    let groups: [QuestionGroup]
    let totalQuestions: Int
    let generatedAt: Date

    /// 将所有题目扁平化为展示列表
    var displayItems: [AnswerDisplayItem] {
        groups.enumerated().flatMap { (groupIndex, group) in
            group.questions.map { question in
                AnswerDisplayItem(
                    groupIndex: groupIndex,
                    group: group,
                    question: question
                )
            }
        }
    }

    /// 格式化为可复制的纯文本（对照安卓 formatPaperAsText）
    func toPlainText() -> String {
        var lines: [String] = []
        lines.append(paperTitle)
        lines.append(String(repeating: "=", count: 50))
        lines.append("生成时间: \(dateFormatter.string(from: generatedAt))")
        lines.append("")

        for group in groups {
            lines.append("【\(group.caption)】")
            lines.append("题型: \(group.typeName)")
            if let original = group.originalContent, !original.isEmpty {
                lines.append("原文: \(original)")
            }
            lines.append("")

            for question in group.questions {
                lines.append("第\(question.order)题: \(question.questionText)")
                for (i, answer) in question.answers.enumerated() {
                    if question.answers.count > 1 {
                        lines.append("  参考答案\(i + 1): \(answer)")
                    } else {
                        lines.append("  答案: \(answer)")
                    }
                }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }
}

private let dateFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
    fmt.locale = Locale(identifier: "zh_CN")
    return fmt
}()
