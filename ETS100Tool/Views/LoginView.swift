import SwiftUI

/// 登录页面
/// 对照安卓 CloudActivationScreen.kt
struct LoginView: View {
    @StateObject private var viewModel = LoginViewModel()
    var onLoginSuccess: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 32)

                    // 云端图标
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 72))
                        .foregroundColor(.blue)

                    Spacer().frame(height: 16)

                    // 标题
                    Text("云端模式")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("在线获取作业和答案")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer().frame(height: 48)

                    // 手机号输入
                    VStack(alignment: .leading, spacing: 6) {
                        Text("手机号").font(.caption).foregroundColor(.secondary)
                        TextField("请输入手机号", text: $viewModel.phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 24)

                    Spacer().frame(height: 16)

                    // 密码输入
                    VStack(alignment: .leading, spacing: 6) {
                        Text("密码").font(.caption).foregroundColor(.secondary)
                        HStack {
                            if viewModel.isPasswordVisible {
                                TextField("请输入密码", text: $viewModel.password)
                                    .textContentType(.password)
                            } else {
                                SecureField("请输入密码", text: $viewModel.password)
                                    .textContentType(.password)
                            }
                            Button {
                                viewModel.isPasswordVisible.toggle()
                            } label: {
                                Image(systemName: viewModel.isPasswordVisible ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 24)

                    Spacer().frame(height: 32)

                    // 登录按钮
                    Button {
                        Task { await viewModel.login() }
                    } label: {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "arrow.right.circle.fill")
                                Text("登 录")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            (viewModel.phone.isEmpty || viewModel.password.isEmpty || viewModel.isLoading)
                                ? Color.blue.opacity(0.4)
                                : Color.blue
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(viewModel.phone.isEmpty || viewModel.password.isEmpty || viewModel.isLoading)
                    .padding(.horizontal, 24)

                    Spacer().frame(height: 24)

                    // 风险提示卡片
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.orange)
                            Text("登录风险提示")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        Text("登录云端模式可能会导致 E听说账号在官方客户端退出登录。请确认当前没有正在使用 E听说，再继续登录。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .background(Color(.systemGray6).opacity(0.5))
                    .cornerRadius(12)
                    .padding(.horizontal, 24)
                }
            }
            .navigationTitle("ETS100 云端登录")
            .alert("错误", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("确定") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onChange(of: viewModel.isLoggedIn) { _, loggedIn in
                if loggedIn { onLoginSuccess() }
            }
        }
    }
}
