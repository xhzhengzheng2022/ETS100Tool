import SwiftUI

/// 设置页面
/// 对照安卓 SettingsScreen.kt + GeneralSettingsScreen.kt（简化版）
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showLogoutAlert: Bool = false
    @State private var showAboutSheet: Bool = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: - 账号信息

                if viewModel.isLoggedIn {
                    Section("账号") {
                        HStack {
                            Text("手机号")
                            Spacer()
                            Text(viewModel.phone)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("机器码")
                            Spacer()
                            Text(String(viewModel.deviceCode.prefix(8)) + "...")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }

                    Section {
                        Button(role: .destructive) {
                            showLogoutAlert = true
                        } label: {
                            HStack {
                                Spacer()
                                Text("退出登录")
                                Spacer()
                            }
                        }
                    }
                } else {
                    Section("账号") {
                        HStack {
                            Text("状态")
                            Spacer()
                            Text("未登录")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // MARK: - 关于

                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("v\(viewModel.appVersion)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Bundle ID")
                        Spacer()
                        Text(Constants.BUNDLE_ID)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }

                    Button {
                        showAboutSheet = true
                    } label: {
                        HStack {
                            Text("关于 ETS 助手")
                            Spacer()
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // MARK: - 免责声明

                Section("免责声明") {
                    Text("本应用仅供学习交流使用，请勿用于考试作弊。云端模式登录会导致 E听说官方客户端退出登录。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("设置")
            .alert("确认退出", isPresented: $showLogoutAlert) {
                Button("取消", role: .cancel) {}
                Button("退出登录", role: .destructive) {
                    viewModel.logout()
                }
            } message: {
                Text("退出登录后需要重新输入账号密码。")
            }
            .sheet(isPresented: $showAboutSheet) {
                NavigationStack {
                    List {
                        Section {
                            VStack(spacing: 12) {
                                Image(systemName: "graduationcap.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.blue)
                                Text("ETS 助手")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Text("v\(viewModel.appVersion)")
                                    .foregroundColor(.secondary)
                                Text("ETS100 云端答案提取工具")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }

                        Section("技术信息") {
                            HStack {
                                Text("平台")
                                Spacer()
                                Text("iOS (SwiftUI)")
                                    .foregroundColor(.secondary)
                            }
                            HStack {
                                Text("最低版本")
                                Spacer()
                                Text("iOS 16.0")
                                    .foregroundColor(.secondary)
                            }
                        }

                        Section("法律声明") {
                            Text("本应用仅供学习交流使用。使用本应用即表示您同意不会将其用于任何作弊或违反考试规则的行为。开发者不承担任何因使用本应用而产生的法律责任。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .navigationTitle("关于")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("完成") { showAboutSheet = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}
