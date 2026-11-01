#if canImport(SwiftUI)
import SwiftUI
import ETS100Core

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showLogoutConfirm = false
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            List {
                accountSection
                dataSection
                aboutSection
                disclaimerSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .confirmationDialog("确定退出当前账号？", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) {
                    Task { await model.signOut() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("退出后需要重新输入手机号与密码。设备绑定信息会保留。")
            }
            .confirmationDialog("清除本地缓存？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清除缓存", role: .destructive) {
                    Task { await model.clearCache() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将删除已下载的资源包和解析结果，不影响账号登录。")
            }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section {
            if let profile = model.profile {
                LabeledContent("账号", value: profile.accountName.isEmpty ? "ETS100 用户" : profile.accountName)
                LabeledContent("手机号", value: profile.maskedPhone)
                if !profile.grade.isEmpty {
                    LabeledContent("年级", value: profile.grade)
                }
                if !profile.className.isEmpty {
                    LabeledContent("班级", value: profile.className)
                }
            } else {
                Text("尚未登录")
                    .foregroundStyle(.secondary)
            }

            Button("退出登录", role: .destructive) {
                showLogoutConfirm = true
            }
        } header: {
            Text("账号")
        } footer: {
            Text("云端登录会与官方客户端共享登录状态，请勿在考试期间使用。")
        }
    }

    private var dataSection: some View {
        Section {
            Button {
                showClearConfirm = true
            } label: {
                Label("清除下载缓存", systemImage: "trash")
            }
        } header: {
            Text("本地数据")
        } footer: {
            Text("资源包缓存位于应用的 Application Support 目录，退出应用不会自动删除。")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("版本", value: "\(AppInfo.version) (\(AppInfo.build))")
            Link(destination: AppInfo.repositoryURL) {
                HStack {
                    Label("开源仓库", systemImage: "chevron.left.forwardslash.chevron.right")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.tertiary)
                }
            }
            LabeledContent("Bundle ID", value: AppInfo.bundleID)
        } header: {
            Text("关于")
        }
    }

    private var disclaimerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("本应用仅供学习与技术研究使用，不提供任何考试作弊能力，也不对使用后果负责。")
                    .font(.footnote)
                Text("所有数据均来自 ETS100 官方接口与公开 CDN 资源，应用不会上传账号信息到任何第三方服务器。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("免责声明")
        }
    }
}
#endif
