import Foundation

/// 登录响应数据模型
/// 对照安卓 ETS100ApiClient.kt 中的 LoginResponse data class
struct LoginResponse: Codable {
    let code: Int
    let msg: String?
    let data: LoginData?

    struct LoginData: Codable {
        let token: String?
        let parentAccountId: String?
        let ecardList: [EcardItem]?

        enum CodingKeys: String, CodingKey {
            case token
            case parentAccountId = "parent_account_id"
            case ecardList = "ecard_list"
        }
    }

    struct EcardItem: Codable {
        let id: String?
        let name: String?
        let role: String?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case role
        }
    }
}

/// 设备绑定响应
/// 对照安卓 bindDevice() 返回的 BindResponse
struct BindDeviceResponse: Codable {
    let code: Int
    let msg: String?
    let token: String?
}

/// E卡列表响应
/// 对照安卓 getEcardList() 返回的 EcardListResponse
struct EcardListResponse: Codable {
    let code: Int
    let msg: String?
    let data: EcardListData?

    struct EcardListData: Codable {
        let parentAccountId: String?

        enum CodingKeys: String, CodingKey {
            case parentAccountId = "parent_account_id"
        }
    }
}
