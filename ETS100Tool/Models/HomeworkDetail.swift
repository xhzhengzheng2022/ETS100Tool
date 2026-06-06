import Foundation

/// 作业详情数据模型
/// 对照安卓 ETS100ApiClient.kt 中的 getHomeworkDetail() 返回结构
struct HomeworkDetail: Codable {
    let code: Int
    let msg: String?
    let data: HomeworkDetailData?

    struct HomeworkDetailData: Codable {
        let homeworkId: String?
        let name: String?
        let subject: String?
        let grade: String?
        let status: String?
        let questionTypes: [QuestionTypeDetail]?
        let paperInfo: PaperDetailInfo?

        enum CodingKeys: String, CodingKey {
            case homeworkId = "homework_id"
            case name
            case subject
            case grade
            case status
            case questionTypes = "question_types"
            case paperInfo = "paper_info"
        }
    }

    /// 题型详情（包含下载 URL 和结构类型）
    struct QuestionTypeDetail: Codable {
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

    /// 试卷详情
    struct PaperDetailInfo: Codable {
        let paperId: String?
        let paperName: String?
        let regionCode: String?
        let paperType: String?

        enum CodingKeys: String, CodingKey {
            case paperId = "paper_id"
            case paperName = "paper_name"
            case regionCode = "region_code"
            case paperType = "paper_type"
        }
    }
}
