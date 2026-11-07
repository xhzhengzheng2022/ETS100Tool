import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Orchestrates the local auto-complete pipeline:
/// checkstart → ppr-res → per-question (silent audio + ISE XML) → sync-v2 →
/// set-use-time → report-score → submit → info read-back.
///
/// All answers are submitted with a silent MP3 placeholder; no TTS or
/// third-party service is involved.
public actor AutoCompleteEngine {
    private let client: AutoCompleteClient
    private var token: String
    private let parentAccountID: String
    private let relogin: @Sendable () async throws -> String

    public init(
        api: ETS100APIClient,
        token: String,
        parentAccountID: String,
        relogin: @escaping @Sendable () async throws -> String
    ) {
        self.client = AutoCompleteClient(api: api)
        self.token = token
        self.parentAccountID = parentAccountID
        self.relogin = relogin
    }

    // MARK: - Entry point

    public func run(
        homework: HomeworkItem,
        paper: Paper,
        options: AutoCompleteOptions,
        onProgress: @escaping @Sendable (AutoCompleteProgress) -> Void
    ) async throws -> AutoCompleteResult {
        guard !homework.needsOnlineFetch else {
            throw ETSError.server(code: -1, message: "在线作业（词汇 PK / 在线题）暂不支持一键完成")
        }
        guard !paper.sections.isEmpty else {
            throw ETSError.parsingFailed("作业内容尚未加载")
        }
        guard paper.sections.count == homework.contents.count else {
            throw ETSError.parsingFailed(
                "作业内容不完整（\(paper.sections.count)/\(homework.contents.count)），请移除缓存后重新加载"
            )
        }

        let homeworkID = homework.id
        let setID = homework.setID.flatMap { $0.isEmpty ? nil : $0 } ?? homeworkID
        var resourceID = homework.resourceID

        onProgress(AutoCompleteProgress(stage: .preparing, message: "正在准备作答数据", fraction: 0.04))

        // 1. Mark the homework as started and pick up the official resource id.
        do {
            let body = try await perform { [client] token in
                try await client.checkStart(homeworkID: homeworkID, token: token)
            }
            let started = JSONReader.string(body["resource_id"]).ifEmpty(JSONReader.string(body["id"]))
            if !started.isEmpty && started != "0" {
                resourceID = started
            }
        } catch let error as ETSError {
            if Self.isTokenExpired(error) { throw error }
            // A stale checkstart must not block submission; the official flow
            // treats it as best-effort in the reference implementation.
        }
        if resourceID.isEmpty || resourceID == "0" { resourceID = "58" }

        // 2. Clear any previous score so a re-submission can overwrite it.
        if options.allowResubmit {
            _ = try? await perform { [client] token in
                try await client.scoreDrop(homeworkID: homeworkID, token: token)
            }
        }

        // 3. Local question seeds (paper section order matches content package order).
        let seeds = Self.makeSeeds(paper: paper, contents: homework.contents)
        guard !seeds.isEmpty else {
            throw ETSError.parsingFailed("未解析到可提交题目")
        }
        guard seeds.allSatisfy({ !$0.entityID.isEmpty }) else {
            throw ETSError.parsingFailed("作业资源编号缺失，无法安全提交")
        }

        // 4. Initialize official question resources and read their orders / points.
        onProgress(AutoCompleteProgress(stage: .structuring, message: "正在读取题目结构", fraction: 0.10))
        let batch = seeds.enumerated().map { index, seed in
            JSONObject(anyValues: ["entity_id": seed.entityID, "order": index])
        }
        var pprGroups: [String: [PPRItem]] = [:]
        do {
            let body = try await perform { [client] token in
                try await client.pprResources(batch: batch, token: token)
            }
            pprGroups = Self.parsePPR(body)
        } catch let error as ETSError {
            if Self.isTokenExpired(error) { throw error }
            pprGroups = [:]
        }

        var plan = Self.buildPlan(seeds: seeds, pprGroups: pprGroups)
        guard !plan.isEmpty else { throw ETSError.parsingFailed("题目结构为空") }

        // 5. Reconcile per-question points with the paper total when needed.
        Self.scalePoints(&plan, homework: homework, paper: paper, usePaperTotal: pprGroups.isEmpty)
        let paperTotal = max(0.01, plan.reduce(0) { $0 + $1.point })

        // 6. Answering time.
        let totalQuestions = plan.count
        let useTime = options.useTime ?? plan.reduce(0) { $0 + ($1.isObjective ? 10 : 15) }
        let perQuestionTimes = Self.distribute(total: useTime, count: totalQuestions)
        var cumulativeUseTime = 0

        let profile = ScoreProfile.target(ratio: options.targetRatio)
        var outcomes: [AutoCompleteQuestionOutcome] = []
        var accumulatedScore = 0.0
        let startedAt = Date()
        let seqID = Self.makeSeqID()

        // 7. Per-question upload + sync.
        onProgress(AutoCompleteProgress(
            stage: .uploading,
            message: "第 1 / \(totalQuestions) 题",
            completed: 0,
            total: totalQuestions,
            fraction: 0.15
        ))

        for (index, entry) in plan.enumerated() {
            let awarded = AutoCompleteScoring.convertScore(profile.total, maximum: entry.point)
            accumulatedScore += awarded

            let questionTime = perQuestionTimes[index]
            cumulativeUseTime += questionTime
            let clientTime = Self.clientTime(
                index: index,
                total: totalQuestions,
                totalUseTime: useTime,
                startedAt: startedAt
            )

            let isObjective = entry.isObjective

            var uploadFileID = ""
            var audioURL = ""
            var detailFileID = ""
            var xmlURL = ""
            var audioUploaded = false
            var xmlUploaded = false
            var note = ""

            let xmlText = AutoCompleteScoring.scoreXML(
                text: isObjective ? (entry.questionText.isEmpty ? (entry.choose.isEmpty ? "A" : entry.choose) : entry.questionText) : entry.spokenText,
                profile: profile,
                category: isObjective ? "read_chapter" : entry.category,
                seed: index
            )

            if isObjective {
                // The official client still allocates an upload id for the
                // answer file, but never uploads audio for choose questions.
                if let pre = try? await perform({ [client] token in
                    try await client.preUpload(token: token)
                }) {
                    uploadFileID = JSONReader.string(pre["id"])
                }
            } else {
                if let upload = try? await upload(content: Self.silentMP3, fileExtension: "mp3", type: "audio") {
                    uploadFileID = upload.id
                    audioURL = upload.url
                    audioUploaded = true
                } else {
                    note = "音频上传失败"
                }
            }

            if let upload = try? await upload(content: Data(xmlText.utf8), fileExtension: "xml", type: "xml") {
                detailFileID = upload.id
                xmlURL = upload.url
                xmlUploaded = true
            } else {
                note = note.isEmpty ? "评分文件上传失败" : note + "，评分文件上传失败"
            }

            let scoreDetail = AutoCompleteScoring.scoreDetail(
                profile: profile,
                category: isObjective ? "choose" : entry.category,
                choose: isObjective ? entry.choose : "",
                chooseID: isObjective ? entry.chooseID : ""
            )

            let homeworkValue: Any = Int(homeworkID) ?? homeworkID
            let parameters: [String: Any] = [
                "homework_id": homeworkValue,
                "resource_id": resourceID,
                "set_id": setID,
                "entity_id": entry.entityID,
                "order": String(entry.order),
                "score": AutoCompleteScoring.formatted(profile.total),
                "correct": 1,
                "auto_submit": 1,
                "use_time": cumulativeUseTime,
                "graduation": 0.125,
                "upload_file_id": uploadFileID,
                "upload_file_url": audioURL,
                "detail_file_id": detailFileID,
                "detail_file_url": xmlURL,
                "score_detail": scoreDetail,
                "serial_id": "0",
                "mistake_id": "",
                "client_time": clientTime,
                "version": "2",
                "mark_service": 1,
                "seq_id": seqID,
                "spx_file_url": "",
                "mark_trace_id": "{\"engine\":\"cloud\"}",
            ]

            do {
                let syncParameters = JSONObject(anyValues: parameters)
                _ = try await perform { [client] token in
                    try await client.syncQuestion(syncParameters, token: token)
                }
            } catch let error as ETSError {
                throw ETSError.server(
                    code: Self.errorCode(error),
                    message: "第 \(index + 1) 题云端作答同步失败：\(error.localizedDescription)"
                )
            }

            outcomes.append(AutoCompleteQuestionOutcome(
                index: index + 1,
                entityID: entry.entityID,
                order: entry.order,
                sectionCaption: entry.sectionCaption,
                typeName: entry.typeName,
                isObjective: isObjective,
                point: entry.point,
                awarded: awarded,
                uploadedAudio: audioUploaded,
                uploadedXML: xmlUploaded,
                note: note
            ))

            let fraction = 0.15 + 0.60 * Double(index + 1) / Double(totalQuestions)
            onProgress(AutoCompleteProgress(
                stage: .uploading,
                message: "第 \(index + 1) / \(totalQuestions) 题",
                completed: index + 1,
                total: totalQuestions,
                fraction: fraction
            ))
        }

        // 8. Persist the use time, report the score, then notify submission.
        onProgress(AutoCompleteProgress(stage: .submitting, message: "正在提交成绩", completed: totalQuestions, total: totalQuestions, fraction: 0.85))

        let homeworkValue: Any = Int(homeworkID) ?? homeworkID
        let timeParameters: [String: Any] = [
            "homework_id": homeworkValue,
            "resource_id": resourceID,
            "use_time": cumulativeUseTime,
            "reset": 0,
            "end": 1,
            "correct": 0,
            "version": 2,
        ]
        let timeObject = JSONObject(anyValues: timeParameters)
        _ = try? await perform { [client] token in
            try await client.setUseTime(timeObject, token: token)
        }

        let reportedScore = min(paperTotal, AutoCompleteScoring.roundPoints(accumulatedScore))
        let scoreRate = min(1_000_000, max(0, Int((reportedScore / paperTotal * 1_000_000).rounded())))
        let reportParameters: [String: Any] = [
            "homework_id": homeworkValue,
            "homework_score_rate": scoreRate,
            "homework_complete_rate": 1_000_000,
            "homework_use_time": cumulativeUseTime,
            "seq_id": "",
            "is_confirm_commit": 1,
            "resource_id": resourceID,
        ]
        let reportObject = JSONObject(anyValues: reportParameters)
        _ = try await perform { [client] token in
            try await client.reportScore(reportObject, parentAccountID: parentAccountID, token: token)
        }

        let submitObject = JSONObject(anyValues: [
            "homework_id": homeworkValue,
            "resource_id": resourceID,
            "seq_id": "",
            "use_time": cumulativeUseTime,
        ])
        _ = try? await perform { [client] token in
            try await client.submitHomework(submitObject, token: token)
        }

        // 9. Read back the official score.
        onProgress(AutoCompleteProgress(stage: .verifying, message: "正在核对成绩", fraction: 0.95))
        try? await Task.sleep(nanoseconds: 500_000_000)
        var officialPoint: Double?
        var verified = false
        if let info = try? await perform({ [client, parentAccountID] token in
            try await client.homeworkInfo(
                homeworkID: homeworkID,
                resourceID: resourceID,
                parentAccountID: parentAccountID,
                token: token
            )
        }) {
            officialPoint = JSONReader.optionalDouble(info["point"])
            if let point = officialPoint {
                let absolute = Self.absoluteScore(point, paperTotal: paperTotal)
                verified = abs(absolute - reportedScore) <= max(0.1, paperTotal * 0.01)
            }
        }

        let message: String
        if verified {
            message = "提交完成，官方分数已核对一致"
        } else if officialPoint == nil {
            message = "提交完成，暂未回读到官方分数（可在作业列表刷新查看）"
        } else {
            message = "提交完成，但官方回读分数与上报分数不一致，请稍后刷新确认"
        }

        onProgress(AutoCompleteProgress(stage: .finished, message: message, completed: totalQuestions, total: totalQuestions, fraction: 1.0))

        return AutoCompleteResult(
            homeworkID: homeworkID,
            reportedScore: reportedScore,
            paperTotal: paperTotal,
            scoreRate: scoreRate,
            useTime: cumulativeUseTime,
            officialPoint: officialPoint,
            verified: verified,
            message: message,
            outcomes: outcomes
        )
    }

    // MARK: - Plan building

    private struct Seed {
        var entityID: String
        var sectionIndex: Int
        var sectionCaption: String
        var typeName: String
        var category: String
        var questionText: String
        var answers: [String]
        var options: [String]
        var correctAnswer: String?
        var localOrder: Int
    }

    private struct PPRItem {
        var order: Int
        var score: Double
    }

    private struct PlanEntry {
        var entityID: String
        var order: Int
        var point: Double
        var sectionCaption: String
        var typeName: String
        var category: String
        var questionText: String
        var answerText: String
        var spokenText: String
        var choose: String
        var chooseID: String
        var isObjective: Bool
    }

    private static func makeSeeds(paper: Paper, contents: [HomeworkContent]) -> [Seed] {
        var seeds: [Seed] = []
        for (sectionIndex, section) in paper.sections.enumerated() {
            let entityID = sectionIndex < contents.count ? contents[sectionIndex].realID : ""
            for (questionIndex, question) in section.questions.enumerated() {
                seeds.append(Seed(
                    entityID: entityID,
                    sectionIndex: sectionIndex,
                    sectionCaption: section.caption,
                    typeName: section.typeName,
                    category: section.category,
                    questionText: question.questionText,
                    answers: question.answers,
                    options: question.options,
                    correctAnswer: question.correctAnswer,
                    localOrder: questionIndex + 1
                ))
            }
        }
        return seeds
    }

    private static func parsePPR(_ body: [String: Any]) -> [String: [PPRItem]] {
        var groups: [String: [PPRItem]] = [:]
        let sections = body["sectionData"] as? [[String: Any]] ?? []
        for section in sections {
            let items = section["sectionItemData"] as? [[String: Any]] ?? []
            for item in items {
                let order = JSONReader.int(item["order"])
                let score = JSONReader.double(item["maxScore"] ?? item["max_score"])
                let entityID = JSONReader.string(item["entityId"] ?? item["entity_id"])
                guard order >= 1, score > 0, !entityID.isEmpty else { continue }
                groups[entityID, default: []].append(PPRItem(order: order, score: score))
            }
        }
        for key in groups.keys {
            groups[key]?.sort { $0.order < $1.order }
        }
        return groups
    }

    private static func buildPlan(seeds: [Seed], pprGroups: [String: [PPRItem]]) -> [PlanEntry] {
        var plan: [PlanEntry] = []
        var consumedOrder: [String: Int] = [:]

        for seed in seeds {
            let group = pprGroups[seed.entityID] ?? []
            let consumed = consumedOrder[seed.entityID] ?? 0
            let item = consumed < group.count ? group[consumed] : nil
            consumedOrder[seed.entityID] = consumed + 1

            let order = item?.order ?? seed.localOrder
            let point = item?.score ?? 1.0

            let structure = seed.category.lowercased()
            let isObjective = structure.contains("choose")
                || structure.contains("fill")
                || !seed.options.isEmpty

            let choose = isObjective ? Self.chooseValue(seed) : ""
            let spoken = isObjective ? "" : Self.spokenText(seed)

            plan.append(PlanEntry(
                entityID: seed.entityID,
                order: order,
                point: point,
                sectionCaption: seed.sectionCaption,
                typeName: seed.typeName,
                category: seed.category,
                questionText: seed.questionText,
                answerText: isObjective ? choose : spoken,
                spokenText: spoken,
                choose: choose,
                chooseID: isObjective ? Self.chooseID(seed, choose: choose) : "",
                isObjective: isObjective
            ))
        }

        // Include official questions that our parser could not represent, so
        // their points still count toward the paper total.
        for (entityID, group) in pprGroups.sorted(by: { $0.key < $1.key }) {
            let consumed = consumedOrder[entityID] ?? 0
            guard consumed < group.count else { continue }
            let caption = seeds.first { $0.entityID == entityID }?.sectionCaption ?? "题目"
            let typeName = seeds.first { $0.entityID == entityID }?.typeName ?? "题目"
            for item in group[consumed...] {
                plan.append(PlanEntry(
                    entityID: entityID,
                    order: item.order,
                    point: item.score,
                    sectionCaption: caption,
                    typeName: typeName,
                    category: "",
                    questionText: caption,
                    answerText: "Yes, that is correct.",
                    spokenText: "Yes, that is correct.",
                    choose: "",
                    chooseID: "",
                    isObjective: false
                ))
            }
        }
        return plan
    }

    private static func chooseValue(_ seed: Seed) -> String {
        if let correct = seed.correctAnswer, !correct.isEmpty {
            return String(correct.prefix(1)).uppercased()
        }
        if let first = seed.answers.first {
            let value = first.trimmingCharacters(in: .whitespacesAndNewlines)
            if let letter = value.first, letter.isLetter {
                return String(letter).uppercased()
            }
        }
        return "A"
    }

    private static func chooseID(_ seed: Seed, choose: String) -> String {
        if let index = seed.options.firstIndex(where: { $0.hasPrefix(choose + ".") || $0.hasPrefix(choose + "、") }) {
            return String(index + 1)
        }
        return ""
    }

    private static func spokenText(_ seed: Seed) -> String {
        var target = ""
        for answer in seed.answers {
            if answer.contains(where: { $0.isASCII && $0.isLetter }) {
                target = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        if target.isEmpty, let first = seed.answers.first {
            target = first.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let question = seed.questionText
        let text: String
        if !target.isEmpty,
           target.contains(where: { $0.isASCII && $0.isLetter }) || !question.contains(where: { $0.isASCII && $0.isLetter }) {
            text = target
        } else if question.contains(where: { $0.isASCII && $0.isLetter }) {
            text = question
        } else {
            text = target.isEmpty ? (question.isEmpty ? "Yes, that is correct." : question) : target
        }
        return text.count > 350 ? String(text.prefix(350)) : text
    }

    private static func scalePoints(
        _ plan: inout [PlanEntry],
        homework: HomeworkItem,
        paper: Paper,
        usePaperTotal: Bool
    ) {
        let rawTotal = plan.reduce(0) { $0 + $1.point }
        let targetTotal: Double
        if let structTotal = homework.structTotalPoint, structTotal > 0 {
            targetTotal = structTotal
        } else if homework.totalScore > 0 {
            targetTotal = homework.totalScore
        } else if usePaperTotal, let paperTotal = paper.totalScore, paperTotal > 0 {
            targetTotal = paperTotal
        } else {
            targetTotal = 0
        }
        guard rawTotal > 0, targetTotal > 0, abs(rawTotal - targetTotal) > 0.01 else { return }

        var allocated = 0.0
        for index in plan.indices {
            if index == plan.count - 1 {
                plan[index].point = max(0, AutoCompleteScoring.roundPoints(targetTotal - allocated))
            } else {
                let scaled = AutoCompleteScoring.roundPoints(plan[index].point / rawTotal * targetTotal)
                plan[index].point = max(0, scaled)
                allocated += plan[index].point
            }
        }
    }

    // MARK: - Upload helpers

    private struct UploadResult {
        var id: String
        var url: String
    }

    private static let silentMP3 = Data([0xFF, 0xFB, 0x90, 0x00] as [UInt8]) + Data(repeating: 0, count: 32)

    private func upload(content: Data, fileExtension: String, type: String) async throws -> UploadResult {
        let pre = try await perform { [client] token in
            try await client.preUpload(token: token)
        }
        let fileID = JSONReader.string(pre["id"])
        guard !fileID.isEmpty else {
            throw ETSError.server(code: -1, message: "预上传未返回文件 ID")
        }

        let config = try await perform { [client] token in
            try await client.ossConfig(type: type, id: fileID, token: token)
        }
        let host = JSONReader.string(config["host"])
        let dir = JSONReader.string(config["dir"])
        guard !host.isEmpty, !dir.isEmpty else {
            throw ETSError.server(code: -1, message: "OSS 配置不完整")
        }

        let url = try await client.uploadOSSForm(
            host: host,
            dirName: dir,
            fileName: "\(fileID).\(fileExtension)",
            accessID: JSONReader.string(config["accessid"]),
            policy: JSONReader.string(config["policy"]),
            signature: JSONReader.string(config["signature"]),
            callback: JSONReader.string(config["callback"]),
            content: content
        )
        return UploadResult(id: fileID, url: url)
    }

    // MARK: - Session helpers

    private func perform<T>(_ operation: (String) async throws -> T) async throws -> T {
        do {
            return try await operation(token)
        } catch let error as ETSError where Self.isTokenExpired(error) {
            token = try await relogin()
            return try await operation(token)
        }
    }

    private static func isTokenExpired(_ error: ETSError) -> Bool {
        guard case .server(let code, _) = error else { return false }
        let tokenCodes: Set<Int> = [401, 30004, 30005, 30014, 40001, 40002, 40003, 40004, 10001, 10002]
        return tokenCodes.contains(code)
    }

    private static func errorCode(_ error: ETSError) -> Int {
        if case .server(let code, _) = error { return code }
        return -1
    }

    // MARK: - Time helpers

    private static func distribute(total: Int, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let total = max(count, total)
        let base = total / count
        let remainder = total % count
        return (0..<count).map { $0 < remainder ? base + 1 : base }
    }

    private static func clientTime(index: Int, total: Int, totalUseTime: Int, startedAt: Date) -> String {
        guard total > 1, totalUseTime > 0 else { return timestamp(startedAt) }
        let fraction = Double(index) / Double(total - 1)
        let offset = -Double(totalUseTime) * (1.0 - fraction)
        return timestamp(startedAt.addingTimeInterval(offset))
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func makeSeqID() -> String {
        let milliseconds = Int(Date().timeIntervalSince1970 * 1000)
        let suffix = Int.random(in: 0...9999)
        return "\(milliseconds)\(String(format: "%04d", suffix))"
    }

    private static func absoluteScore(_ point: Double, paperTotal: Double) -> Double {
        if paperTotal > 100, point <= 100 {
            return point / 100.0 * paperTotal
        }
        return point
    }
}

// MARK: - Small helpers

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
