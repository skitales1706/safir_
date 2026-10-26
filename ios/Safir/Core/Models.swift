import Foundation

struct UserDTO: Codable, Equatable {
    let id: String
    let username: String
    let email: String?
    let fullName: String?
}

/// schemas.Token. With mfaRequired the token is only a short-lived pending token for /auth/2fa/*.
struct TokenResponse: Decodable {
    let accessToken: String
    let user: UserDTO
    let mfaRequired: Bool?
    let mfaSetupRequired: Bool?
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
    let deviceName: String
}

struct TotpCodeRequest: Encodable {
    let code: String
    let deviceName: String
}
