import SwiftUI

/// 作业列表管理
/// 对照安卓 CloudHomeworkState + ReadScreen.kt 云端模式逻辑
@MainActor
final class HomeworkListViewModel: ObservableObject {

    // MARK: - 状态（对照安卓 CloudHomeworkState）

    @Published var selectedStatus: String = Constants.STATUS_CURRENT
    @Published var homeworkList: [HomeworkItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var searchText: String = ""

    // 下载状态
    @Published var downloadingHomeworks: Set<String> = []
    @Published var downloadProgress: [String: DownloadProgress] = [:]
    @Published var failedHomeworks: Set<String> = []

    // 已下载的试卷
    @Published var downloadedPapers: [String: PaperInfo] = [:]

    // 所有状态的作业缓存（对照安卓 homeworkListsByStatus）
    private var homeworkListsByStatus: [String: [HomeworkItem]] = [:]

    // MARK: - 作业状态标签

    let statusTabs: [(label: String, value: String)] = [
        ("进行中", Constants.STATUS_CURRENT),
        ("已完成", Constants.STATUS_HISTORY),
        ("已过期", Constants.STATUS_EXPIRED),
    ]

    /// 筛选后的作业列表
    var filteredHomeworkList: [HomeworkItem] {
        guard !searchText.isEmpty else { return homeworkList }
        return homeworkList.filter { item in
            item.name.localizedCaseInsensitiveContains(searchText) ||
            (item.subject ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - 加载作业列表（对照安卓 loadHomeworkList）

    func loadHomeworkList() async {
        guard let token = ETS100AuthManager.getToken(),
              let parentAccountId = ETS100AuthManager.getParentAccountId() else {
            errorMessage = "未登录"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let list = try await ETS100ApiClient.shared.getHomeworkList(
                token: token,
                parentAccountId: parentAccountId,
                status: selectedStatus
            )
            homeworkListsByStatus[selectedStatus] = list
            homeworkList = list
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// 切换状态标签（对照安卓 onStatusChanged）
    func switchStatus(to status: String) {
        selectedStatus = status
        if let cached = homeworkListsByStatus[status] {
            homeworkList = cached
        } else {
            homeworkList = []
            Task { await loadHomeworkList() }
        }
    }

    // MARK: - 下载作业 ZIP 并解析（对照安卓 downloadAndParseHomework）

    func downloadHomework(_ homework: HomeworkItem) async {
        guard let token = ETS100AuthManager.getToken() else { return }

        downloadingHomeworks.insert(homework.homeworkId)

        do {
            // 获取作业详情
            let detail = try await ETS100ApiClient.shared.getHomeworkDetail(
                token: token,
                homeworkId: homework.homeworkId
            )

            let typeInfos = ETS100AnswerReader.extractQuestionTypes(from: detail)

            var zipDataList: [(fileName: String, data: Data)] = []
            var passwords: [String: String] = [:]

            // 逐题型下载 ZIP
            for info in typeInfos {
                let fileName = URL(fileURLWithPath: info.resourceUrl).lastPathComponent

                let zipData = try await ETS100ApiClient.shared.downloadZip(
                    resourceUrl: info.resourceUrl
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress[homework.homeworkId] = progress
                    }
                }

                // 生成解压密码
                do {
                    let password = try ZipPasswordGenerator.generate(from: zipData)
                    passwords[info.resourceUrl] = password
                    zipDataList.append((fileName: fileName, data: zipData))
                } catch {
                    failedHomeworks.insert(homework.homeworkId)
                }
            }

            // 解析所有 content.json
            if !zipDataList.isEmpty {
                let paper = try ETS100AnswerReader.parseAllFromZips(
                    zipDataList: zipDataList,
                    passwords: passwords,
                    typeInfos: typeInfos
                )
                downloadedPapers[homework.homeworkId] = paper
            }

            downloadingHomeworks.remove(homework.homeworkId)

        } catch {
            failedHomeworks.insert(homework.homeworkId)
            downloadingHomeworks.remove(homework.homeworkId)
        }
    }

    /// 判断作业是否已下载
    func isHomeworkDownloaded(_ homeworkId: String) -> Bool {
        downloadedPapers[homeworkId] != nil
    }

    /// 获取已下载的 PaperInfo
    func getDownloadedPaper(for homeworkId: String) -> PaperInfo? {
        downloadedPapers[homeworkId]
    }

    /// 刷新列表
    func refresh() async {
        homeworkListsByStatus.removeValue(forKey: selectedStatus)
        await loadHomeworkList()
    }

    /// 登出清理
    func clear() {
        homeworkList = []
        homeworkListsByStatus = [:]
        downloadedPapers = [:]
        downloadProgress = [:]
        downloadingHomeworks = []
        failedHomeworks = []
        searchText = ""
    }
}
