import SwiftUI

/// 作业列表主页
/// 对照安卓 ReadScreen.kt 云端模式核心功能
struct HomeworkListView: View {
    @StateObject private var viewModel = HomeworkListViewModel()
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                // 搜索栏
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索作业名称或科目", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                    if !viewModel.searchText.isEmpty {
                        Button {
                            viewModel.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.top, 8)

                // 状态标签
                Picker("状态", selection: $viewModel.selectedStatus) {
                    ForEach(viewModel.statusTabs, id: \.value) { tab in
                        Text(tab.label).tag(tab.value)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .onChange(of: viewModel.selectedStatus) { newStatus in
                    viewModel.switchStatus(to: newStatus)
                }

                // 作业列表
                if viewModel.isLoading && viewModel.filteredHomeworkList.isEmpty {
                    Spacer()
                    ProgressView("加载中...")
                    Spacer()
                } else if viewModel.filteredHomeworkList.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("暂无作业")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(viewModel.filteredHomeworkList) { homework in
                            HomeworkRow(
                                homework: homework,
                                isDownloaded: viewModel.isHomeworkDownloaded(homework.homeworkId),
                                isDownloading: viewModel.downloadingHomeworks.contains(homework.homeworkId),
                                progress: viewModel.downloadProgress[homework.homeworkId],
                                onTap: {
                                    if let paper = viewModel.getDownloadedPaper(for: homework.homeworkId) {
                                        navigationPath.append(paper)
                                    } else {
                                        Task { await viewModel.downloadHomework(homework) }
                                    }
                                }
                            )
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await viewModel.refresh()
                    }
                }
            }
            .navigationTitle("作业列表")
            .navigationDestination(for: PaperInfo.self) { paper in
                AnswerView(paper: paper)
            }
            .task {
                if viewModel.homeworkList.isEmpty {
                    await viewModel.loadHomeworkList()
                }
            }
        }
    }
}

// MARK: - 作业行视图

struct HomeworkRow: View {
    let homework: HomeworkItem
    let isDownloaded: Bool
    let isDownloading: Bool
    let progress: DownloadProgress?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 状态图标
                Image(systemName: isDownloaded ? "checkmark.circle.fill" : "doc.text")
                    .font(.title2)
                    .foregroundColor(isDownloaded ? .green : homework.isExpired ? .gray : .blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(homework.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .foregroundColor(.primary)

                    HStack(spacing: 8) {
                        if let subject = homework.subject, !subject.isEmpty {
                            Label(subject, systemImage: "book")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let grade = homework.grade, !grade.isEmpty {
                            Text(grade)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.systemGray5))
                                .cornerRadius(4)
                        }
                    }

                    HStack {
                        Text(homework.statusDescription)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(statusColor.opacity(0.15))
                            .foregroundColor(statusColor)
                            .cornerRadius(4)

                        if isDownloaded {
                            Text("已下载")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }

                Spacer()

                // 下载进度
                if isDownloading, let progress = progress {
                    VStack(spacing: 4) {
                        ProgressView(value: progress.fraction ?? 0)
                            .frame(width: 40)
                        Text(progress.fraction.map { String(format: "%.0f%%", $0 * 100) } ?? "...")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var statusColor: Color {
        switch homework.status {
        case "1": return .blue
        case "2": return .green
        case "3": return .gray
        default: return .secondary
        }
    }
}
