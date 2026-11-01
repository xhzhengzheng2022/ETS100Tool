#if canImport(SwiftUI)
import SwiftUI
import ETS100Core

struct LoginView: View {
    @EnvironmentObject private var model: AppModel

    @State private var phone = ""
    @State private var password = ""
    @State private var smsCode = ""
    @State private var rememberPassword = true
    @FocusState private var focused: Field?

    private enum Field {
        case phone
        case password
        case smsCode
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                riskNotice
                credentialsCard
                if model.requiresSMS {
                    smsCard
                }
                actionButton
                disclaimer
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Color.appGroupedBackground)
        .dismissKeyboardOnScroll()
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 78, height: 78)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 22))

            Text("ETS 助手")
                .font(.largeTitle.bold())

            Text("登录 ETS100 账号，读取云端作业答案")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    private var riskNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("使用前须知", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            Text("云端登录会顶掉 ETS100 官方客户端的登录状态；本工具仅用于学习与自查，请勿用于考试作弊。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.warningBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    private var credentialsCard: some View {
        SectionCard {
            VStack(spacing: 16) {
                fieldTitle("手机号")
                TextField("请输入注册手机号", text: $phone)
                    .textFieldStyle(.plain)
                    .font(.body.monospacedDigit())
                    .focused($focused, equals: .phone)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
                    .phoneInputStyle()

                Divider()

                fieldTitle("密码")
                SecureField("请输入 ETS100 密码", text: $password)
                    .textFieldStyle(.plain)
                    .focused($focused, equals: .password)
                    .submitLabel(model.requiresSMS ? .next : .go)
                    .onSubmit {
                        if model.requiresSMS {
                            focused = .smsCode
                        } else {
                            submitPasswordLogin()
                        }
                    }
                    .passwordInputStyle()

                Divider()

                Toggle(isOn: $rememberPassword) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("记住密码")
                            .font(.subheadline)
                        Text("密码将保存在系统钥匙串，用于自动刷新登录状态")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(AppTheme.accent)
            }
        }
    }

    private var smsCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("设备绑定", systemImage: "iphone.gen3.badge.key")
                    .font(.subheadline.weight(.semibold))

                Text("当前设备需要完成短信验证，验证成功后即可安全登录。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    TextField("短信验证码", text: $smsCode)
                        .textFieldStyle(.plain)
                        .keyboardType(.numberPad)
                        .focused($focused, equals: .smsCode)

                    Button(model.smsSent ? "重新发送" : "发送验证码") {
                        Task { await model.sendSMS(phone: phone) }
                    }
                    .font(.footnote.weight(.medium))
                    .disabled(model.isAuthenticating || phone.isEmpty)
                }
            }
        }
    }

    private var actionButton: some View {
        VStack(spacing: 10) {
            Button {
                if model.requiresSMS {
                    submitSMSLogin()
                } else {
                    submitPasswordLogin()
                }
            } label: {
                HStack {
                    if model.isAuthenticating {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(model.requiresSMS ? "验证并登录" : "登录")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(model.isAuthenticating)

            Button("登录遇到问题？先获取短信验证码") {
                Task { await model.sendSMS(phone: phone) }
            }
            .font(.footnote)
            .disabled(model.isAuthenticating)
        }
    }

    private var disclaimer: some View {
        Text("本应用不收集、不上传任何账号信息；所有请求仅发送至 ETS100 官方接口。")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }

    private func fieldTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func submitPasswordLogin() {
        focused = nil
        Task {
            await model.signIn(
                phone: phone,
                password: password,
                rememberPassword: rememberPassword
            )
        }
    }

    private func submitSMSLogin() {
        focused = nil
        Task {
            await model.signInWithSMS(
                phone: phone,
                password: password,
                code: smsCode,
                rememberPassword: rememberPassword
            )
        }
    }
}
#endif
