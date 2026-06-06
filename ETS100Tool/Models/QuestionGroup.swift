import Foundation

/// 题型分组数据模型
/// 对照安卓 ETS100AnswerReader.kt 中的 Section data class
struct QuestionGroup: Codable, Identifiable, Hashable {
    /// 分组标题（如"模仿朗读"、"信息转述"）
    let caption: String
    /// 题目类别（如 read_chapter, simple_expression_ufi, topic）
    let category: String
    /// 题型名称
    let typeName: String
    /// 该分组下的题目列表
    let questions: [QuestionItem]
    /// 原文内容（部分题型有）
    let originalContent: String?

    var id: String { "\(caption)_\(category)_\(typeName)" }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: QuestionGroup, rhs: QuestionGroup) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - 题型颜色映射（对照安卓 answerCategoryColors）

    var categoryColorHex: String {
        switch category {
        case "read_chapter":          return "6366F1"     // 紫色
        case "simple_expression_ufi": return "22C55E"     // 绿色
        case "simple_expression_ufk": return "F59E0B"     // 橙色
        case "topic":                 return "3B82F6"     // 蓝色
        case "simple_expression_ufj": return "EC4899"     // 粉色
        default:                      return "6B7280"     // 灰色
        }
    }
}
