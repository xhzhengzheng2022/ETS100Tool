import SwiftUI

/// 答案展示管理
/// 对照安卓 AnswerActivity.kt + formatPaperAsText
@MainActor
final class AnswerViewModel: ObservableObject {

    @Published var paperTitle: String = ""
    @Published var groups: [QuestionGroup] = []
    @Published var totalQuestions: Int = 0
    @Published var showRawJSON: Bool = false

    /// 复制到剪贴板（对照安卓 formatPaperAsText + ClipboardManager）
    func copyToClipboard() {
        let summary = AnswerSummary(
            paperTitle: paperTitle,
            groups: groups,
            totalQuestions: totalQuestions,
            generatedAt: Date()
        )
        let text = summary.toPlainText()
        UIPasteboard.general.string = text
    }

    /// 从 PaperInfo 加载数据
    func load(from paper: PaperInfo) {
        paperTitle = paper.title
        groups = paper.groups
        totalQuestions = paper.totalQuestions
    }

    /// 获取展示项列表
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

    /// 颜色 hex 字符串转 Color（用于 SwiftUI 视图不使用 Model 扩展的备用方案）
    func colorForCategory(_ category: String) -> Color {
        let group = QuestionGroup(
            caption: "", category: category, typeName: "",
            questions: [], originalContent: nil
        )
        return Color(hex: group.categoryColorHex)
    }
}

// MARK: - Color hex 初始化

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }
}
