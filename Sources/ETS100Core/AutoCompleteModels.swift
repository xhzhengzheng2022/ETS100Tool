import Foundation

/// Options for the local "auto complete" pipeline.
///
/// The pipeline never talks to any third-party service: every request goes to
/// the official ETS100 gateway with the already-authenticated token, and the
/// uploaded audio is a deliberately silent placeholder.
public struct AutoCompleteOptions: Sendable, Equatable {
    /// Ratio of full marks to aim for, clamped to `0.05 ... 1.0`.
    public var targetRatio: Double
    /// Total answering time in seconds. `nil` lets the engine estimate it.
    public var useTime: Int?
    /// Clear a previous result before re-submitting (safe for normal attempts).
    public var allowResubmit: Bool

    public init(targetRatio: Double = 1.0, useTime: Int? = nil, allowResubmit: Bool = true) {
        self.targetRatio = min(1.0, max(0.05, targetRatio))
        self.useTime = useTime
        self.allowResubmit = allowResubmit
    }
}

public enum AutoCompleteStage: String, Sendable {
    case preparing
    case checking
    case structuring
    case uploading
    case submitting
    case verifying
    case finished

    public var title: String {
        switch self {
        case .preparing: return "准备中"
        case .checking: return "检查作业状态"
        case .structuring: return "读取题目结构"
        case .uploading: return "逐题上传"
        case .submitting: return "提交成绩"
        case .verifying: return "核对入库"
        case .finished: return "已完成"
        }
    }
}

public struct AutoCompleteProgress: Sendable, Equatable {
    public var stage: AutoCompleteStage
    public var message: String
    public var completed: Int
    public var total: Int
    public var fraction: Double

    public init(
        stage: AutoCompleteStage,
        message: String,
        completed: Int = 0,
        total: Int = 0,
        fraction: Double = 0
    ) {
        self.stage = stage
        self.message = message
        self.completed = completed
        self.total = total
        self.fraction = min(1, max(0, fraction))
    }
}

public struct AutoCompleteQuestionOutcome: Sendable, Identifiable, Equatable {
    public var id: String { "\(entityID)#\(order)" }
    public var index: Int
    public var entityID: String
    public var order: Int
    public var sectionCaption: String
    public var typeName: String
    public var isObjective: Bool
    public var point: Double
    public var awarded: Double
    public var uploadedAudio: Bool
    public var uploadedXML: Bool
    public var note: String

    public init(
        index: Int,
        entityID: String,
        order: Int,
        sectionCaption: String,
        typeName: String,
        isObjective: Bool,
        point: Double,
        awarded: Double,
        uploadedAudio: Bool,
        uploadedXML: Bool,
        note: String
    ) {
        self.index = index
        self.entityID = entityID
        self.order = order
        self.sectionCaption = sectionCaption
        self.typeName = typeName
        self.isObjective = isObjective
        self.point = point
        self.awarded = awarded
        self.uploadedAudio = uploadedAudio
        self.uploadedXML = uploadedXML
        self.note = note
    }
}

public struct AutoCompleteResult: Sendable, Equatable {
    public var homeworkID: String
    public var reportedScore: Double
    public var paperTotal: Double
    public var scoreRate: Int
    public var useTime: Int
    public var officialPoint: Double?
    public var verified: Bool
    public var message: String
    public var outcomes: [AutoCompleteQuestionOutcome]

    public init(
        homeworkID: String,
        reportedScore: Double,
        paperTotal: Double,
        scoreRate: Int,
        useTime: Int,
        officialPoint: Double?,
        verified: Bool,
        message: String,
        outcomes: [AutoCompleteQuestionOutcome]
    ) {
        self.homeworkID = homeworkID
        self.reportedScore = reportedScore
        self.paperTotal = paperTotal
        self.scoreRate = scoreRate
        self.useTime = useTime
        self.officialPoint = officialPoint
        self.verified = verified
        self.message = message
        self.outcomes = outcomes
    }

    public var scoreText: String {
        Self.formatScore(reportedScore) + " / " + Self.formatScore(paperTotal)
    }

    public var officialPointText: String {
        guard let officialPoint else { return "未回读到官方分数" }
        return Self.formatScore(officialPoint)
    }

    private static func formatScore(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }
}
