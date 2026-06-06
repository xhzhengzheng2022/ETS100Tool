import SwiftUI

/// 答案详情展示页面
/// 对照安卓 AnswerActivity.kt + PaperDetailScreen + formatPaperAsText
struct AnswerView: View {
    let paper: PaperInfo
    @StateObject private var viewModel = AnswerViewModel()
    @State private var expandedSections: Set<String> = []
    @State private var showCopiedToast: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 试卷标题
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.paperTitle)
                        .font(.title2)
                        .fontWeight(.bold)

                    HStack(spacing: 12) {
                        Label("\(viewModel.totalQuestions) 题", systemImage: "list.number")
                        Label("\(viewModel.groups.count) 种题型", systemImage: "square.grid.2x2")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(16)

                Divider()

                // 按题型分组展示
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.groups.indices, id: \.self) { groupIndex in
                        let group = viewModel.groups[groupIndex]
                        Section {
                            if expandedSections.contains(group.id) {
                                ForEach(group.questions) { question in
                                    QuestionCard(
                                        question: question,
                                        colorHex: group.categoryColorHex
                                    )
                                    Divider().padding(.leading, 16)
                                }
                            }
                        } header: {
                            SectionHeader(
                                group: group,
                                questionCount: group.questions.count,
                                isExpanded: expandedSections.contains(group.id),
                                colorHex: group.categoryColorHex,
                                onToggle: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if expandedSections.contains(group.id) {
                                            expandedSections.remove(group.id)
                                        } else {
                                            expandedSections.insert(group.id)
                                        }
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.copyToClipboard()
                    showCopiedToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopiedToast = false
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                Text("已复制到剪贴板")
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.75))
                    .foregroundColor(.white)
                    .cornerRadius(20)
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut, value: showCopiedToast)
            }
        }
        .onAppear {
            viewModel.load(from: paper)
            // 默认展开所有分组
            expandedSections = Set(viewModel.groups.map { $0.id })
        }
    }
}

// MARK: - 分组标题

struct SectionHeader: View {
    let group: QuestionGroup
    let questionCount: Int
    let isExpanded: Bool
    let colorHex: String
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // 颜色指示条
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: colorHex))
                    .frame(width: 4, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.caption)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("\(group.typeName) \(questionCount) 题")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.systemGray6).opacity(0.3))
        }
        .buttonStyle(.plain)

        if let original = group.originalContent, !original.isEmpty, isExpanded {
            VStack(alignment: .leading, spacing: 4) {
                Text("原文")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(Color(hex: colorHex))
                Text(original)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}

// MARK: - 题目卡片

struct QuestionCard: View {
    let question: QuestionItem
    let colorHex: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 题号 + 问题
            HStack(alignment: .top, spacing: 8) {
                Text("\(question.order).")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(Color(hex: colorHex))
                    .frame(width: 28, alignment: .leading)

                Text(question.questionText)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 答案
            VStack(alignment: .leading, spacing: 6) {
                ForEach(question.answers.indices, id: \.self) { idx in
                    HStack(alignment: .top, spacing: 8) {
                        if question.answers.count > 1 {
                            Text("参考\(idx + 1):")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                                .frame(width: 52, alignment: .leading)
                        } else {
                            Text("答案:")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                                .frame(width: 36, alignment: .leading)
                        }

                        Text(question.answers[idx])
                            .font(.body)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.06))
            .cornerRadius(8)

            // 原文（如果该题有独立原文）
            if let original = question.originalText, !original.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("原文")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(hex: colorHex))
                    Text(original)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
    }
}
