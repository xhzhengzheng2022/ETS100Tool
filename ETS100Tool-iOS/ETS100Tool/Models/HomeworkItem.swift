import Foundation

/// 作业列表项数据模型
/// 对照安卓 ETS100ApiClient.kt 中的 HomeworkInfo data class
struct HomeworkItem: Codable, Identifiable, Hashable {
    let homeworkId: String
    let name: String
    let subject: String?
    let grade: String?
    let status: String?
    let createTime: String?
    let endTime: String?
    let questionTypes: [QuestionTypeInfo]?
    let paperInfo: PaperBriefInfo?

    var id: String { homeworkId }

    /// 作业状态描述
    var statusDescription: String {
        switch status {
        case "1": return "进行中"
        case "2": return "已完成"
        case "3": return "已过期"
        default: return "未知"
        }
    }

    var isExpired: Bool { status == "3" }
    var isCurrent: Bool { status == "1" }

    enum CodingKeys: String, CodingKey {
        case homeworkId = "homework_id"
        case name
        case subject
        case grade
        case status
        case createTime = "create_time"
        case endTime = "end_time"
        case questionTypes = "question_types"
        case paperInfo = "paper_info"
    }

    /// 题型信息（对照安卓 question_types 字段）
    struct QuestionTypeInfo: Codable, Hashable {
        let typeId: String?
        let typeName: String?
        let resourceUrl: String?
        let structureType: String?

        enum CodingKeys: String, CodingKey {
            case typeId = "type_id"
            case typeName = "type_name"
            case resourceUrl = "resource_url"
            case structureType = "structure_type"
        }
    }

    /// 试卷简要信息
    struct PaperBriefInfo: Codable, Hashable {
        let paperId: String?
        let paperName: String?

        enum CodingKeys: String, CodingKey {
            case paperId = "paper_id"
            case paperName = "paper_name"
        }
    }
}
