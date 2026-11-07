import Foundation

// MARK: - Account

/// A single E-card account returned by `m/ecard/list`.
public struct EcardAccount: Codable, Hashable, Sendable {
    public var key: String
    public var id: String
    public var parentID: String
    public var userAccountID: String
    public var name: String
    public var grade: String
    public var status: String
    public var mobileStatus: String
    public var outOfDate: String
    public var classID: String
    public var className: String
    public var machineCodeStatus: String

    public init(
        key: String,
        id: String,
        parentID: String,
        userAccountID: String,
        name: String,
        grade: String,
        status: String,
        mobileStatus: String,
        outOfDate: String,
        classID: String,
        className: String,
        machineCodeStatus: String
    ) {
        self.key = key
        self.id = id
        self.parentID = parentID
        self.userAccountID = userAccountID
        self.name = name
        self.grade = grade
        self.status = status
        self.mobileStatus = mobileStatus
        self.outOfDate = outOfDate
        self.classID = classID
        self.className = className
        self.machineCodeStatus = machineCodeStatus
    }

    /// Mirrors the Android `isValid` rule: active class, not expired, mobile enabled.
    public var isValid: Bool {
        status == "0"
            && outOfDate == "0"
            && !classID.trimmingCharacters(in: .whitespaces).isEmpty
            && mobileStatus == "1"
    }
}

public struct EcardSelection: Codable, Hashable, Sendable {
    public var parentAccountID: String
    public var selectedAccount: EcardAccount
    public var validAccounts: [EcardAccount]

    public init(parentAccountID: String, selectedAccount: EcardAccount, validAccounts: [EcardAccount]) {
        self.parentAccountID = parentAccountID
        self.selectedAccount = selectedAccount
        self.validAccounts = validAccounts
    }
}

/// Locally persisted session (secrets live in the injected secret store).
public struct AccountProfile: Codable, Hashable, Sendable {
    public var phone: String
    public var accountName: String
    public var grade: String
    public var className: String
    public var parentAccountID: String
    public var loginMethod: String

    public init(
        phone: String,
        accountName: String,
        grade: String,
        className: String,
        parentAccountID: String,
        loginMethod: String = "password"
    ) {
        self.phone = phone
        self.accountName = accountName
        self.grade = grade
        self.className = className
        self.parentAccountID = parentAccountID
        self.loginMethod = loginMethod
    }

    public var maskedPhone: String {
        guard phone.count > 7 else { return phone }
        return phone.prefix(3) + "****" + phone.suffix(4)
    }
}

// MARK: - Homework

public struct HomeworkContent: Codable, Hashable, Sendable {
    public var groupName: String
    public var url: String
    public var realID: String

    public init(groupName: String, url: String, realID: String = "") {
        self.groupName = groupName
        self.url = url
        self.realID = realID
    }

    /// File name extracted from the URL, query string removed.
    public var zipFileName: String {
        guard let last = url.split(separator: "/", omittingEmptySubsequences: true).last else { return "" }
        return String(last.split(separator: "?").first ?? last)
    }
}

public struct HomeworkItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var contents: [HomeworkContent]
    public var setType: Int
    public var pk: Int
    public var resourceID: String
    public var totalScore: Double
    public var point: Double?
    public var useTime: Int
    public var status: String
    /// Official `struct.set_id`, used by the auto-complete report payload.
    public var setID: String?
    /// Official `struct.total_point` when the server provides it.
    public var structTotalPoint: Double?

    public init(
        id: String,
        name: String,
        contents: [HomeworkContent],
        setType: Int = 0,
        pk: Int = 0,
        resourceID: String = "",
        totalScore: Double = 0,
        point: Double? = nil,
        useTime: Int = 0,
        status: String = "",
        setID: String? = nil,
        structTotalPoint: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.contents = contents
        self.setType = setType
        self.pk = pk
        self.resourceID = resourceID
        self.totalScore = totalScore
        self.point = point
        self.useTime = useTime
        self.status = status
        self.setID = setID
        self.structTotalPoint = structTotalPoint
    }

    /// Online PK / vocabulary homework has no ZIP packages.
    public var needsOnlineFetch: Bool {
        contents.isEmpty || pk == 1 || setType == 6
    }

    public var subtitle: String {
        var parts: [String] = []
        if totalScore > 0 {
            if let point {
                parts.append("得分 \(Self.scoreText(point)) / \(Self.scoreText(totalScore))")
            } else {
                parts.append("总分 \(Self.scoreText(totalScore))")
            }
        }
        if useTime > 0 {
            parts.append("用时 \(Self.durationText(useTime))")
        }
        if needsOnlineFetch {
            parts.append("在线作业")
        } else {
            parts.append("\(contents.count) 个资源包")
        }
        return parts.joined(separator: " · ")
    }

    private static func scoreText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func durationText(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes) 分钟" : "\(minutes) 分 \(remainder) 秒"
    }
}

public struct HomeworkList: Codable, Sendable {
    public var baseURL: String
    public var homeworks: [HomeworkItem]

    public init(baseURL: String, homeworks: [HomeworkItem]) {
        self.baseURL = baseURL
        self.homeworks = homeworks
    }
}

// MARK: - Parsed paper

public struct Paper: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var regionLabel: String
    public var totalScore: Double?
    public var sections: [PaperSection]
    public var parsedAt: Date

    public init(
        id: String,
        title: String,
        regionLabel: String = "云端",
        totalScore: Double? = nil,
        sections: [PaperSection],
        parsedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.regionLabel = regionLabel
        self.totalScore = totalScore
        self.sections = sections
        self.parsedAt = parsedAt
    }

    public var questionCount: Int {
        sections.reduce(0) { $0 + $1.questions.count }
    }
}

public struct PaperSection: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var caption: String
    public var category: String
    public var typeName: String
    public var originalContent: String?
    public var questions: [Question]

    public init(
        id: String = UUID().uuidString,
        caption: String,
        category: String = "",
        typeName: String,
        originalContent: String? = nil,
        questions: [Question]
    ) {
        self.id = id
        self.caption = caption
        self.category = category
        self.typeName = typeName
        self.originalContent = originalContent
        self.questions = questions
    }
}

public struct Question: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    /// Global question number inside the paper (1-based).
    public var order: Int
    /// Question number inside its section (1-based).
    public var sectionOrder: Int
    public var questionText: String
    public var answers: [String]
    public var options: [String]
    public var correctAnswer: String?
    public var originalText: String?
    public var category: String
    public var typeName: String
    /// Official question number when the resource provides one (`xh` / `xth`).
    public var displayOrder: Int?

    public init(
        id: String = UUID().uuidString,
        order: Int,
        sectionOrder: Int,
        questionText: String,
        answers: [String],
        options: [String] = [],
        correctAnswer: String? = nil,
        originalText: String? = nil,
        category: String = "",
        typeName: String = "",
        displayOrder: Int? = nil
    ) {
        self.id = id
        self.order = order
        self.sectionOrder = sectionOrder
        self.questionText = questionText
        self.answers = answers
        self.options = options
        self.correctAnswer = correctAnswer
        self.originalText = originalText
        self.category = category
        self.typeName = typeName
        self.displayOrder = displayOrder
    }

    public var hasAnswers: Bool {
        !answers.isEmpty
    }

    public var numberedText: String {
        "\(displayOrder ?? order). \(questionText)"
    }

    /// Plain-text rendering used by copy / share actions.
    public var shareText: String {
        var lines = [numberedText]
        if !options.isEmpty {
            lines.append(contentsOf: options)
        }
        if !answers.isEmpty {
            lines.append("答案：")
            lines.append(contentsOf: answers)
        } else if let originalText, !originalText.isEmpty {
            lines.append("原文：")
            lines.append(originalText)
        }
        return lines.joined(separator: "\n")
    }
}

/// Per-content download progress reported to the UI.
public struct DownloadProgress: Hashable, Sendable {
    public var currentFileName: String
    public var index: Int
    public var total: Int
    public var downloadedBytes: Int64
    public var totalBytes: Int64

    public init(
        currentFileName: String,
        index: Int,
        total: Int,
        downloadedBytes: Int64 = 0,
        totalBytes: Int64 = 0
    ) {
        self.currentFileName = currentFileName
        self.index = index
        self.total = total
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
    }

    public var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(downloadedBytes) / Double(totalBytes))
    }
}
