#if canImport(SwiftUI)
import SwiftUI
import ETS100Core

final class AutoCompleteRunner: ObservableObject, @unchecked Sendable {
    @Published var progress: AutoCompleteProgress?
    @Published var result: AutoCompleteResult?
    @Published var errorMessage: String?
    @Published var isRunning = false

    func start(model: AppModel, route: HomeworkRoute, options: AutoCompleteOptions) {
        guard !isRunning else { return }
        isRunning = true
        errorMessage = nil
        result = nil
        progress = AutoCompleteProgress(stage: .preparing, message: "准备中", fraction: 0.02)

        Task {
            do {
                let outcome = try await model.autoComplete(route: route, options: options) { [weak self] update in
                    DispatchQueue.main.async {
                        self?.progress = update
                    }
                }
                await MainActor.run {
                    self.result = outcome
                }
                await model.load(status: route.status, force: true)
            } catch {
                let text: String
                if let ets = error as? ETSError {
                    text = ets.errorDescription ?? "未知错误"
                } else {
                    text = error.localizedDescription
                }
                await MainActor.run {
                    self.errorMessage = text
                }
            }
            await MainActor.run {
                self.isRunning = false
            }
        }
    }

    func reset() {
        errorMessage = nil
        result = nil
        progress = nil
        isRunning = false
    }
}

struct AutoCompleteView: View {
    let route: HomeworkRoute
    let paper: Paper

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var runner = AutoCompleteRunner()

    @State private var targetPercent = 100
    @State private var usesCustomTime = false
    @State private var customUseTime = 600

    private var targetRatio: Double { Double(targetPercent) / 100.0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let result = runner.result {
                        resultContent(result)
                    } else if let error = runner.errorMessage {
                        errorContent(error)
                    } else if runner.isRunning {
                        runningContent
                    } else {
                        setupContent
                    }
                }
                .padding(16)
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("一键完成")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .disabled(runner.isRunning)
                }
            }
        }
        .interactiveDismissDisabled(runner.isRunning)
    }

    // MARK: - Setup

    private var setupContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            warningCard

            SectionCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("目标分数")
                        .font(.headline)
                    Picker("目标分数", selection: $targetPercent) {
                        Text("100%").tag(100)
                        Text("95%").tag(95)
                        Text("90%").tag(90)
                        Text("80%").tag(80)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if let total = paper.totalScore, total > 0 {
                        Text("预计得分 \(scoreText(total * targetRatio)) / \(scoreText(total))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $usesCustomTime) {
                        Text("自定义作答时长")
                            .font(.headline)
                    }
                    if usesCustomTime {
                        Stepper(value: $customUseTime, in: 60...3600, step: 60) {
                            Text("\(customUseTime) 秒")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("按题目数量自动估算（选择题 10 秒、口语题 15 秒）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                runner.start(
                    model: model,
                    route: route,
                    options: AutoCompleteOptions(
                        targetRatio: targetRatio,
                        useTime: usesCustomTime ? customUseTime : nil
                    )
                )
            } label: {
                Label("开始一键完成", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("题目数量：\(paper.questionCount) 题")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
    }

    private var warningCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("提交前请确认", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text("该功能会直接向 ETS100 官方接口提交作答，上传的音频为静音占位。提交后作业状态会变为已完成，且无法撤销；请仅在确认需要时使用。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.warningBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Running

    private var runningContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(runner.progress?.stage.title ?? "处理中")
                            .font(.headline)
                        Spacer()
                        Text("\(Int((runner.progress?.fraction ?? 0) * 100))%")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: runner.progress?.fraction ?? 0)
                    Text(runner.progress?.message ?? "正在连接官方接口…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let progress = runner.progress, progress.total > 0 {
                        Text("已完成 \(progress.completed) / \(progress.total) 题")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Text("请保持应用在前台并确保网络畅通。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Result

    private func resultContent(_ result: AutoCompleteResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.scoreText)
                                .font(.title.bold())
                            Text("上报分数 / 满分")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        verificationBadge(result)
                    }

                    Divider()

                    row("官方回读", result.officialPointText)
                    row("作答时长", "\(result.useTime) 秒")
                    row("题目数量", "\(result.outcomes.count) 题")

                    Text(result.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("逐题结果")
                        .font(.headline)
                    ForEach(result.outcomes) { outcome in
                        outcomeRow(outcome)
                        if outcome.id != result.outcomes.last?.id {
                            Divider()
                        }
                    }
                }
            }

            Button {
                dismiss()
            } label: {
                Label("完成", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func verificationBadge(_ result: AutoCompleteResult) -> some View {
        let color: Color = result.verified ? .green : (result.officialPoint == nil ? .orange : .red)
        let title = result.verified ? "已核对" : (result.officialPoint == nil ? "待刷新" : "不一致")
        return Label(title, systemImage: result.verified ? "checkmark.seal.fill" : "clock.badge.questionmark")
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func outcomeRow(_ outcome: AutoCompleteQuestionOutcome) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(outcome.index)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(minWidth: 24, minHeight: 24)
                .background(AppTheme.accent, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(outcome.sectionCaption)
                    .font(.subheadline.weight(.medium))
                Text("\(outcome.typeName) · 第 \(outcome.order) 题\(outcome.isObjective ? " · 选择" : " · 口语")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !outcome.note.isEmpty {
                    Text(outcome.note)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 0)

            Text("\(scoreText(outcome.awarded)) / \(scoreText(outcome.point))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(outcome.awarded >= outcome.point ? Color.green : Color.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Error

    private func errorContent(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("提交失败", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("未完成的题目不会自动回滚；如作业状态异常，请先在官方 App 中检查。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                runner.reset()
            } label: {
                Label("返回重试", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Helpers

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }

    private func scoreText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }
}
#endif
