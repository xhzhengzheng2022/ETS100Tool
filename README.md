# ETS 助手 iOS 版 (ETS100Tool)

ETS100 云端答案提取工具 — iOS 移植版。从安卓版 Kotlin/Jetpack Compose 项目完整迁移而来，**仅保留云端模式**。

## 零 Mac 构建方案（GitHub Actions）

无需拥有 Mac，推送代码到 GitHub 即可自动构建 .ipa。

### 使用步骤

1. 在 GitHub 上创建仓库，把整个 `ETS100Tool-iOS` 文件夹推送上去
2. 推送后 GitHub Actions 自动触发，macOS 环境编译，约 5~8 分钟
3. 在仓库 Actions 页面下载 `ETS100Tool.ipa`（artifact，保留 7 天）
4. 手动触发：Actions → Build iOS IPA → Run workflow

### 签名说明

GitHub Actions 产出的 .ipa **未签名**，无法直接在 iPhone 安装。你需要以下任一方式签名：

| 签名方式 | 需要 | 成本 |
|---|---|---|
| 朋友 Mac + iOS App Signer | Mac + Apple ID | 免费 |
| 云 Mac（MacinCloud 等） | 按小时租用 | ~$1/h |
| 第三方签名服务 | 上传 .ipa | 约 ¥50-200/年 |

签名后上传 fir.im 即可分发安装。

### 前置准备

推送前先在 Xcode 中添加 ZIPFoundation SPM 依赖（否则 CI 构建会失败）：

```
File → Add Package Dependencies → https://github.com/weichsel/ZIPFoundation.git
```

如果暂时没有 Mac，可以先推送，根据 CI 报错再补依赖。

## 技术栈

| 层 | 方案 |
|---|---|
| 语言 | Swift 5.10+ |
| UI | SwiftUI（声明式） |
| 导航 | NavigationStack (iOS 16.0+) |
| 网络 | URLSession + async/await |
| JSON | Codable |
| 存储 | Keychain + UserDefaults |
| 最低版本 | **iOS 16.0** |

## 项目结构

```
ETS100Tool-iOS/
├── ETS100Tool.xcodeproj/
│   └── project.pbxproj              # Xcode 项目配置
├── ETS100Tool/
│   ├── ETS100ToolApp.swift          # @main 入口
│   ├── Info.plist                   # Bundle + ATS 配置
│   ├── Models/                      # 数据模型 (Codable)
│   │   ├── LoginResponse.swift
│   │   ├── HomeworkItem.swift
│   │   ├── HomeworkDetail.swift
│   │   ├── QuestionGroup.swift
│   │   ├── Question.swift
│   │   ├── Answer.swift
│   │   └── PaperInfo.swift
│   ├── Services/                    # 业务服务
│   │   ├── ETS100ApiClient.swift    # HTTP 客户端 (全部 API)
│   │   ├── ETS100AuthManager.swift  # Token 管理 (Keychain)
│   │   ├── ETS100AnswerReader.swift # 答案解析引擎
│   │   └── ZipPasswordGenerator.swift # ZIP 密码生成
│   ├── ViewModels/                  # MVVM ViewModel
│   │   ├── LoginViewModel.swift
│   │   ├── HomeworkListViewModel.swift
│   │   ├── AnswerViewModel.swift
│   │   └── SettingsViewModel.swift
│   ├── Views/                       # SwiftUI 页面
│   │   ├── LoginView.swift
│   │   ├── HomeworkListView.swift
│   │   ├── AnswerView.swift
│   │   ├── SettingsView.swift
│   │   └── MainTabView.swift
│   └── Helpers/                     # 工具
│       ├── Constants.swift
│       └── MD5Helper.swift
└── README.md
```

## 功能对照（安卓 → iOS）

| 安卓模块 | iOS 对应 | 状态 |
|---|---|---|
| ETS100ApiClient.kt | ETS100ApiClient.swift | 已迁移 |
| ETS100AuthManager.kt | ETS100AuthManager.swift | 已迁移 |
| ETS100AnswerReader.kt | ETS100AnswerReader.swift | 已迁移 |
| ZipPasswordGenerator.kt | ZipPasswordGenerator.swift | 已迁移 |
| CloudActivationScreen.kt | LoginView.swift | 已迁移 |
| ReadScreen.kt (云端) | HomeworkListView.swift | 已迁移 |
| AnswerActivity.kt | AnswerView.swift | 已迁移 |
| SettingsScreen.kt | SettingsView.swift | 已迁移 |
| ETS100FileReader.kt (本地) | — | 不可迁移 |
| ShizukuManager.kt | — | 不可迁移 |
| RootManager.kt | — | 不可迁移 |
| ZWCHelper.kt (零宽字符) | — | 不可迁移 |

## 构建指南

### 前置条件

- macOS 14+ / Xcode 16.0+
- Apple Developer 账号（免费账号即可，用于签名调试）
- ZIPFoundation 依赖（用于 ZIP 解压）

### 安装依赖

在 Xcode 中添加 SPM 依赖：

```
https://github.com/weichsel/ZIPFoundation.git
```

File → Add Package Dependencies → 搜索 ZIPFoundation → 选择最新版本 → Add to Target "ETS100Tool"

### 构建设置

- Target: ETS100Tool
- Bundle ID: `com.nanshanqilin.ets`
- Deployment Target: iOS 16.0
- Scheme: Release

### 编译

```
xcodebuild -project ETS100Tool.xcodeproj \
           -scheme ETS100Tool \
           -configuration Release \
           -destination 'generic/platform=iOS' \
           archive -archivePath ./build/ETS100Tool.xcarchive
```

### 导出 .ipa

```
xcodebuild -exportArchive \
           -archivePath ./build/ETS100Tool.xcarchive \
           -exportPath ./build \
           -exportOptionsPlist exportOptions.plist
```

`exportOptions.plist` 示例（Ad-hoc 分发）：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>ad-hoc</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
    <key>compileBitcode</key>
    <false/>
</dict>
</plist>
```

## .ipa 分发方案（不上架 App Store）

| 方案 | 推荐度 | 说明 |
|---|---|---|
| **AltStore / SideStore** | 推荐 | 用户用个人 Apple ID 侧载，7 天自动续签，3 台设备上限 |
| Ad-hoc 分发 | 中等 | 需开发者证书 + 用户 UDID，100 台，1 年有效期 |
| 企业证书 | 高级 | 无设备限制，需企业开发者账号 ($299/年) |

**推荐 AltStore**：安装 AltStore → 用个人 Apple ID 签名 → 侧载 .ipa，7 天自动续签。

## API 端点

| 端点 | 方法 | 说明 |
|---|---|---|
| `api.ets100.com/api/login` | POST | 账号密码登录 |
| `api.ets100.com/api/device/bind` | POST | 设备绑定 |
| `api.ets100.com/api/ecard/list` | GET | 获取父账户 ID |
| `api.ets100.com/api/homework/list` | GET | 获取作业列表 |
| `api.ets100.com/api/homework/detail` | GET | 获取作业详情 |
| `cdn.subject.ets100.com/{resource}` | GET | 下载试卷 ZIP |

所有签名使用公式：`MD5(PID + timestamp + bodyBase64 + SECRET_KEY)`

## 安全声明

- SECRET_KEY 硬编码于客户端，仅供学习交流使用
- 云端模式登录会导致 E听说官方客户端退出登录
- 本应用**仅供学习交流使用，请勿用于考试作弊**
- 使用本应用即表示您同意自行承担所有风险

## License

本项目仅用于学习和技术交流。不对任何因使用本项目产生的后果负责。
