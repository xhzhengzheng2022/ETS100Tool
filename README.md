# ETS 助手 iOS 版 · ETS100Tool

ETS100 云端答案读取工具的 iOS 实现。以安卓版 Kotlin / Jetpack Compose 工程为蓝本重写，**仅保留云端模式**，使用开源工具 [xtool](https://github.com/xtool-org/xtool) 构建，无需 Xcode 图形界面。

> **免责声明**：本项目仅供学习、技术研究与个人自查使用。云端登录会顶掉 ETS100 官方客户端的登录状态；请勿用于考试作弊，使用产生的一切后果由使用者自行承担。

---

## 一、功能范围

| 能力 | 状态 | 说明 |
|---|---|---|
| 手机号 + 密码登录 | ✅ | 复用安卓端的签名协议与固定设备参数 |
| 设备绑定 / 短信验证码 | ✅ | `code=30014` 时自动绑定，必要时切换短信验证 |
| 当前 / 历史 / 过期作业列表 | ✅ | `g/homework/list`，按状态分栏 |
| 云端资源包下载与解密 | ✅ | CDN ZIP + 336 字节尾部密码种子 + ZipCrypto |
| `content.json` 题目与答案解析 | ✅ | 支持 choose / fill / picture / read / role / dialogue / 3q5a 等 |
| 解析结果本地缓存 | ✅ | Application Support 下的 `cloud_homework/` 与 `papers/` |
| 答案复制 / 分享 | ✅ | 单题、整卷均可复制与系统分享 |
| 本地读取（Root / Shizuku / 零宽字符） | ❌ | iOS 沙盒限制，无法实现 |
| 词汇 PK 等在线作业 | ❌ | 在线题目协议未移植，列表会给出提示 |
| 自动答题 / 自动提交 | ❌ | 本项目只读，不包含任何写操作 |

---

## 二、技术栈

| 层 | 方案 |
|---|---|
| 语言 | Swift 6.2（SwiftPM，`swift-tools-version: 6.0`） |
| UI | SwiftUI（iOS 17+） |
| 网络 | `URLSession` + async/await |
| JSON | 自研有序 `JSONValue`（保证签名逐字节一致） |
| 压缩 | 自研 ZIP 中央目录解析 + ZipCrypto + 系统 zlib（`CZlib` C 目标） |
| 存储 | Keychain（token / 密码）+ UserDefaults（手机号、机器码等） |
| 构建 | xtool（`xtool.yml` + SwiftPM library product） |

协议层 `ETS100Core` 不依赖 UIKit / SwiftUI，可在 Linux 上直接运行单元测试。

---

## 三、目录结构

```
ETS100Tool/
├── Package.swift                  # SwiftPM 清单（library product: ETS100Tool）
├── xtool.yml                      # xtool 配置（bundleID）
├── Sources/
│   ├── CZlib/                     # zlib raw inflate 的 C 桥接
│   │   ├── czlib.c
│   │   └── include/czlib.h
│   ├── ETS100Core/                # 平台无关核心层
│   │   ├── ETSConfig.swift        # 端点、设备参数、状态常量
│   │   ├── JSONValue.swift        # 有序 JSON + 紧凑序列化
│   │   ├── MD5.swift              # 纯 Swift MD5
│   │   ├── ETSError.swift         # 用户可读错误
│   │   ├── Models.swift           # 账号 / 作业 / 试卷 / 题目
│   │   ├── TextCleaning.swift     # HTML、实体、内部编号清洗
│   │   ├── ContentParser.swift    # content.json → 题目
│   │   ├── ZipPasswordGenerator.swift
│   │   ├── ZipArchive.swift       # ZipCrypto + DEFLATE
│   │   ├── AuthStore.swift        # 会话与机器码持久化
│   │   ├── ETS100APIClient.swift  # 签名与全部 API
│   │   └── CloudService.swift     # 登录 → 列表 → 下载 → 解密 → 缓存
│   └── ETS100Tool/                # SwiftUI 应用层
│       ├── ETS100ToolApp.swift    # @main
│       ├── AppModel.swift         # 全局状态
│       ├── Support/               # Keychain、环境装配、版本信息
│       └── Views/                 # 登录 / 作业列表 / 答案 / 设置
├── Tests/ETS100CoreTests/         # XCTest + 真实 content.json / 加密 ZIP 夹具
└── .github/workflows/ci.yml
```

---

## 四、构建

### 4.1 前置条件

- Swift 6.2 或更高（`swift --version` 可验证）
- [xtool](https://github.com/xtool-org/xtool/releases) 1.24+
- 任一方案：
  - **macOS**：安装 Xcode 15+，xtool 可直接使用本机 SDK；
  - **Linux / Windows**：准备 `Xcode.xip` 或 xtool 的 `darwin.xtoolsdk`，无需 Mac 图形界面。

### 4.2 常用命令

```bash
# 安装 Darwin SDK（首次需要，传入本机 Xcode.xip / Xcode.app / darwin.xtoolsdk）
xtool sdk install /path/to/Xcode.xip

# 调试构建并安装到已连接设备
xtool dev

# 只构建
xtool dev build --configuration release

# 产出未签名 .ipa
xtool dev build --configuration release --ipa

# 生成 Xcode 工程（需要图形化调试时）
xtool dev generate-xcode-project
```

`xtool.yml` 中已固定 `bundleID: com.nanshanqilin.ets`，与安卓版保持一致。

### 4.3 单元测试

协议层与压缩层不依赖 Apple 平台，Linux 上即可跑通：

```bash
swift test
```

测试覆盖：MD5 向量、JSON 紧凑序列化与签名、短信/登录参数、机器码格式、账号有效性、文本清洗、各 `structure_type` 解析、ZIP 密码派生、ZipCrypto 解密与 CRC 校验。

---

## 五、协议要点

| 项目 | 值 / 规则 |
|---|---|
| API | `https://api.ets100.com` |
| CDN | `https://cdn.subject.ets100.com`（客户端统一升级为 HTTPS） |
| PID | `grlx` |
| 签名 | `MD5(pid + timestamp + bodyBase64 + secret)` |
| 请求体 | `[{"r": route, "params": {...}}]` 紧凑 JSON → Base64 |
| 机器码 | `MD5(随机hex)[8..24] + "|" + MD5(随机hex)[8..24]`，首次生成后持久化 |
| 登录 | `POST /user/login`（`version=3`、`device_name=DESKTOP`） |
| 绑定 | `POST /user/rebind-code`（`version=2`、`device_name=1337`） |
| 账号 | `POST /m/ecard/list` |
| 作业 | `POST /g/homework/list`（`status=1/2/3`） |
| ZIP 密码 | 尾部 336 字节，校验 `MSTCHINA` 或 `EPLAT`，seed 取 `[16,144)`，两次 MD5 大写拼接为 64 字符 |

实现与安卓端逐字节对齐，相关常量集中在 [ETSConfig.swift](Sources/ETS100Core/ETSConfig.swift)。

---

## 六、安全与隐私

- token / 密码保存在 **Keychain**（`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`），不会写入普通文件。
- 手机号、机器码、账号名称等非敏感信息保存在 UserDefaults，便于自动刷新登录。
- 所有请求只发往 ETS100 官方域名，不上传任何第三方服务器。
- iOS 端不关闭 TLS 校验（安卓端曾为 CDN 放宽校验）；如遇 CDN 证书异常会直接提示错误。
- 机器码为随机生成的伪设备标识，不读取真实硬件信息。

---

## 七、持续集成

[ci.yml](.github/workflows/ci.yml) 包含：

1. **Linux 核心测试**：`swift test`，验证协议与压缩逻辑；
2. **macOS SwiftUI 编译**：`swift build` + `swift test`，验证 SwiftUI 应用层；
3. **iOS 打包检查**：下载 xtool，生成 Xcode 工程后用 `xcodebuild` 构建未签名 iOS 产物。

签名与真机安装仍需自备 Apple 开发者账号（免费账号可用 AltStore / SideStore 侧载）。

---

## 八、License

仅用于学习与技术交流。项目作者不对使用本项目造成的任何直接或间接后果负责。
