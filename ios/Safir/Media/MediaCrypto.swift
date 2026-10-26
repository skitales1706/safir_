import CryptoKit
import Foundation

/// Attachment encryption, byte-compatible with Android's SecurityUtils / MediaThumbnails:
/// a fresh AES-256 key per file; the file on the server is IV(12) || ciphertext || tag(16)
/// (AES-GCM "combined"), and the key itself travels inside the Signal message.
enum MediaCrypto {
    /// Thumbnails share the file's key, so they are bound to their role with GCM AAD - the server
    /// can't swap a preview and a file.
    private static let thumbnailAAD = Data("tochpayom-thumbnail-v1".utf8)

    static func newKey() -> SymmetricKey { SymmetricKey(size: .bits256) }

    static func keyBase64(_ key: SymmetricKey) -> String {
        key.withUnsafeBytes { Data($0) }.base64EncodedString()
    }

    static func key(fromBase64 b64: String) -> SymmetricKey? {
        guard let data = Data(base64Encoded: b64), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    static func encrypt(_ plain: Data, key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(plain, using: key).combined else {
            throw CryptoKitError.incorrectParameterSize
        }
        return combined
    }

    static func decrypt(_ sealed: Data, key: SymmetricKey) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key)
    }

    static func sealThumbnail(_ jpeg: Data, key: SymmetricKey) -> String? {
        guard let combined = try? AES.GCM.seal(jpeg, using: key, authenticating: thumbnailAAD).combined else { return nil }
        return combined.base64EncodedString()
    }

    static func openThumbnail(_ b64: String?, keyBase64: String?) -> Data? {
        guard let b64, let keyBase64, let sealed = Data(base64Encoded: b64), let key = key(fromBase64: keyBase64),
              let box = try? AES.GCM.SealedBox(combined: sealed) else { return nil }
        return try? AES.GCM.open(box, using: key, authenticating: thumbnailAAD)
    }
}
