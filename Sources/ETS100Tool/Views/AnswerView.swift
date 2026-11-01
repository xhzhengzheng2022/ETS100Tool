#if canImport(SwiftUI)
import SwiftUI
import ETS100Core

struct AnswerView: View {
    let route: HomeworkRoute

    @EnvironmentObject private var model: AppModel
    @State private var copiedQuestionID: String?

    private var paper: Paper? {
        model.paper(for: route.homework.id)
    }

    var body: some View {
        Group {
            if let paper {
                paperContent(paper)
            } else if model.paperLoadingID == route.homework.id {
                loadingState
            } else if let error = model.paperError {
                errorState(error)
            } else {
                loadingState
            }
        }
        .background(Color.appGroupedBackground)
        .navigationTitle(route.homework.name)
        .inlineNavigationTitle()
        .toolbar {
            if let paper {
                ToolbarItem(placement: .automatic) {
                    ShareLink(item: fullText(paper)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .task {
            await model.loadPaper(for: route)
        }
    }

    // MARK: - Paper

    private func paperContent(_ paper: Paper) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                headerCard(paper)

                ForEach(paper.sections) { section in
                    sectionView(section)
                }

                Text("答案来自云端资源包解析，仅供学习自查。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .padding(16)
        }
        .dismissKeyboardOnScroll()
    }

    private func headerCard(_ paper: Paper) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(paper.title)
                .font(.title3.bold())
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                tag(paper.regionLabel, systemImage: "cloud")
                tag("\(paper.questionCount) 题", systemImage: "list.number")
                if let total = paper.totalScore, total > 0 {
                    tag("满分 \(scoreText(total))", systemImage: "checkmark.seal")
                }
            }

            HStack(spacing: 10) {
                Button {
                    Clipboard.copy(fullText(paper))
                    flash(copiedQuestionID: "__all__")
                } label: {
                    Label(
                        copiedQuestionID == "__all__" ? "已复制" : "复制全文",
                        systemImage: copiedQuestionID == "__all__" ? "checkmark" : "doc.on.doc"
                    )
                    .font(.footnote.weight(.medium))
                }
                .buttonStyle(.bordered)

                ShareLink(item: fullText(paper)) {
                    Label("分享", systemImage: "square.and.arrow.up")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)
            }

            Text(paper.parsedAt, format: .dateTime.year().month().day().hour().minute())
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 16))
    }

    private func sectionView(_ section: PaperSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.caption)
                    .font(.headline)
                Spacer(minLength: 8)
                Text("\(section.questions.count) 题")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let original = section.originalContent, !original.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("原文", systemImage: "text.alignleft")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(original)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 12))
            }

            ForEach(section.questions) { question in
                questionCard(question, sectionHasOriginal: !(section.originalContent ?? "").isEmpty)
            }
        }
    }

    private func questionCard(_ question: Question, sectionHasOriginal: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(question.displayOrder ?? question.order)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 24, minHeight: 24)
                    .background(AppTheme.accent, in: Circle())

                Text(question.questionText)
                    .font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                Spacer(minLength: 0)

                Button {
                    Clipboard.copy(question.shareText)
                    flash(copiedQuestionID: question.id)
                } label: {
                    Image(systemName: copiedQuestionID == question.id ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if !question.options.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { _, option in
                        Text(option)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.leading, 34)
            }

            if !question.answers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("答案", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)

                    ForEach(Array(question.answers.enumerated()), id: \.offset) { _, answer in
                        Text(answer)
                            .font(.callout)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.answerBackground, in: RoundedRectangle(cornerRadius: 10))
            } else if let original = question.originalText, !original.isEmpty, !sectionHasOriginal {
                Text(original)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 34)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)

            if let progress = model.progress {
                Text("正在下载 \(progress.index)/\(progress.total)")
                    .font(.subheadline.weight(.medium))
                Text(progress.currentFileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("正在解析云端资源包…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("首次读取需要下载并解密资源包，请保持网络畅通。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("解析失败", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("重试") {
                Task { await model.reloadPaper(route) }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Helpers

    private func tag(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private func scoreText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func fullText(_ paper: Paper) -> String {
        var lines: [String] = [paper.title, ""]
        for section in paper.sections {
            lines.append("【\(section.caption)】")
            if let original = section.originalContent, !original.isEmpty {
                lines.append(original)
                lines.append("")
            }
            for question in section.questions {
                lines.append(question.shareText)
                lines.append("")
            }
        }
        lines.append("—— 由 ETS 助手 iOS 版解析，仅供学习自查")
        return lines.joined(separator: "\n")
    }

    private func flash(copiedQuestionID id: String) {
        copiedQuestionID = id
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if copiedQuestionID == id {
                copiedQuestionID = nil
            }
        }
    }
}
#endif
