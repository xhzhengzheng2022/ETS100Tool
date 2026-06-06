import Foundation

/// 试卷/作业完整信息（用于传递到详情页）
/// 对照安卓 ETS100AnswerReader.kt 中的 Paper data class
struct PaperInfo: Codable, Identifiable, Hashable {
    let paperId: Int
    let title: String
    let dataFileName: String?
    let fileSize: Int64?
    let groups: [QuestionGroup]
    let downloadTime: Date?
    let regionLabel: String
    let paperName: String?
    /// 云端作业 ID（云端模式使用）
    let homeworkId: String?

    var id: Int { paperId }

    /// 总题数
    var totalQuestions: Int {
        groups.reduce(0) { $0 + $1.questions.count }
    }

    /// 总分组数
    var totalGroups: Int { groups.count }

    init(
        paperId: Int,
        title: String,
        dataFileName: String? = nil,
        fileSize: Int64? = nil,
        groups: [QuestionGroup],
        downloadTime: Date? = nil,
        regionLabel: String = "云端",
        paperName: String? = nil,
        homeworkId: String? = nil
    ) {
        self.paperId = paperId
        self.title = title
        self.dataFileName = dataFileName
        self.fileSize = fileSize
        self.groups = groups
        self.downloadTime = downloadTime
        self.regionLabel = regionLabel
        self.paperName = paperName
        self.homeworkId = homeworkId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(paperId)
    }

    static func == (lhs: PaperInfo, rhs: PaperInfo) -> Bool {
        lhs.paperId == rhs.paperId
    }

    /// 转换为 AnswerSummary
    func toSummary() -> AnswerSummary {
        AnswerSummary(
            paperTitle: title,
            groups: groups,
            totalQuestions: totalQuestions,
            generatedAt: Date()
        )
    }
}
