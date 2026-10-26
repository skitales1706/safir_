import Foundation

// Wire models for backend routers/keys.py and routers/group_keys.py (snake_case on the wire,
// converted by APIClient's coders). Same shapes as Android's ApiService.kt.

struct SignedPreKeyDTO: Codable {
    let keyId: Int
    let publicKey: String
    let signature: String
}

struct OneTimePreKeyDTO: Codable {
    let keyId: Int
    let publicKey: String
}

struct UploadKeyBundleRequest: Encodable {
    let identityKey: String
    let registrationId: Int
    let signedPrekey: SignedPreKeyDTO
    let kyberSignedPrekey: SignedPreKeyDTO
    let oneTimePrekeys: [OneTimePreKeyDTO]
    /// This install's UUID (models.UserDevice) - the server assigns the small Signal device id.
    let deviceId: String
}

struct UploadKeyBundleResponse: Decodable {
    let ratchetDeviceId: Int
}

struct KeyBundleResponse: Decodable {
    let identityKey: String
    let registrationId: Int
    let signedPrekey: SignedPreKeyDTO
    let kyberSignedPrekey: SignedPreKeyDTO
    let oneTimePrekey: OneTimePreKeyDTO?
    let deviceId: Int?
}

struct RatchetIdentityInfo: Decodable {
    let deviceId: Int
    let identityKey: String
    let registrationId: Int
}

struct RatchetIdentityListResponse: Decodable {
    let identities: [RatchetIdentityInfo]
}

struct PrekeyCountResponse: Decodable {
    let count: Int
}

struct SenderKeyUploadItem: Encodable {
    let targetId: String
    let ciphertext: String
    let targetDeviceId: Int
}

struct UploadSenderKeyRequest: Encodable {
    let keyVersion: Int
    let items: [SenderKeyUploadItem]
    let deviceId: String
}

struct SenderKeyDownloadItem: Decodable {
    let senderId: String
    let keyVersion: Int
    let ciphertext: String
    let senderDeviceId: Int?
}

struct SenderKeysResponse: Decodable {
    let items: [SenderKeyDownloadItem]
}

struct DeviceRegisterRequest: Encodable {
    let deviceId: String
    let deviceName: String
    let protocolVersion: Int
    let isRooted: Bool?
}

struct PushTokenRequest: Encodable {
    let apnsToken: String?
    let voipToken: String?
    let sandbox: Bool
}
