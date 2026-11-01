#if canImport(SwiftUI)
import SwiftUI
import ETS100Core

struct HomeworkListView: View {
    @EnvironmentObject private var model: AppModel

    private var statusBinding: Binding<String> {
        Binding(
            get: { model.selectedStatus },
            set: { model.select(status: $0) }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusPicker
                content
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("云端作业")
            .navigationDestination(item: $model.route) { route in
                AnswerView(route: route)
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await model.load(status: model.selectedStatus, force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isLoadingCurrentList)
                }
            }
        }
        .task {
            await model.load(status: model.selectedStatus)
        }
    }

    private var statusPicker: some View {
        Picker("作业状态", selection: statusBinding) {
            Text(HomeworkStatus.title(HomeworkStatus.current)).tag(HomeworkStatus.current)
            Text(HomeworkStatus.title(HomeworkStatus.history)).tag(HomeworkStatus.history)
            Text(HomeworkStatus.title(HomeworkStatus.expired)).tag(HomeworkStatus.expired)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoadingCurrentList && model.currentHomeworks.isEmpty {
            loadingState
        } else if let error = model.listError, model.currentHomeworks.isEmpty {
            errorState(error)
        } else if model.currentHomeworks.isEmpty {
            emptyState
        } else {
            List {
                if let error = model.listError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    ForEach(model.currentHomeworks) { homework in
                        homeworkRow(homework)
                    }
                } footer: {
                    Text("共 \(model.currentHomeworks.count) 份作业 · 下拉可刷新列表")
                        .font(.caption)
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await model.load(status: model.selectedStatus, force: true)
            }
        }
    }

    private func homeworkRow(_ homework: HomeworkItem) -> some View {
        Button {
            model.open(homework, status: model.selectedStatus)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: homework.needsOnlineFetch ? "waveform" : "doc.zipper")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 4) {
                    Text(homework.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(homework.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在获取作业列表…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("加载失败", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("重试") {
                Task { await model.load(status: model.selectedStatus, force: true) }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("暂无作业", systemImage: "tray")
        } description: {
            Text("当前分类下没有可读取的作业，试试切换分类或下拉刷新。")
        }
    }
}
#endif
