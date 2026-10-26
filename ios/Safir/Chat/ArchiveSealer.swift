import CryptoKit
import Foundation
import Security

/// Organisation compliance archive (backend compliance.py, Android ArchiveSealer.kt). When the
/// organisation turns it on, every E2E message is sealed a SECOND time to the archive public key
/// and sent as `archive`; only the security officer's offline key can open it.
///
/// Format: "v1.<key_id>.<b64 RSA-OAEP-SHA256 wrapped AES key>.<b64 12-byte IV>.<b64 AES-256-GCM
/// ciphertext+tag>", plaintext JSON {"type", "content"}.
actor ArchiveSealer {
    static let shared = ArchiveSealer()

    private struct ArchiveKeyResponse: Decodable {
        let mode: String?
        let keyId: String?
        let publicKeyPem: String?
    }

    private var key: (id: String, publicKey: SecKey)?
    private var fetchedAt: Date?
    private let refresh: TimeInterval = 10 * 60

    /// Next send refetches the key (after a 409 archive_required).
    func invalidate() { fetchedAt = nil }

    /// The sealed copy, or nil when the organisation has no archive (the server decides whether
    /// a missing copy is acceptable).
    func seal(type: String, content: String) async -> String? {
        guard let key = await current() else { return nil }
        do {
            let json = try JSONSerialization.data(withJSONObject: ["type": type, "content": content])
            let aes = SymmetricKey(size: .bits256)
            let sealed = try AES.GCM.seal(json, using: aes)
            let rawKey = aes.withUnsafeBytes { Data($0) }
            var error: Unmanaged<CFError>?
            guard let wrapped = SecKeyCreateEncryptedData(key.publicKey, .rsaEncryptionOAEPSHA256, rawKey as CFData, &error) as Data? else {
                return nil
            }
            let iv = sealed.nonce.withUnsafeBytes { Data($0) }
            let ct = sealed.ciphertext + sealed.tag
            return "v1.\(key.id).\(wrapped.base64EncodedString()).\(iv.base64EncodedString()).\(ct.base64EncodedString())"
        } catch {
            return nil
        }
    }

    private func current() async -> (id: String, publicKey: SecKey)? {
        if let fetchedAt, Date().timeIntervalSince(fetchedAt) < refresh { return key }
        do {
            let api = await Session.shared.api
            let r = try await api.get("compliance/archive-key", as: ArchiveKeyResponse.self)
            if let pem = r.publicKeyPem, !pem.isEmpty, let id = r.keyId, !id.isEmpty, r.mode != nil, r.mode != "off" {
                key = Self.rsaPublicKey(pem: pem).map { (id: id, publicKey: $0) }
            } else {
                key = nil
            }
            fetchedAt = Date()
        } catch {
            // Keep the last known key - the server enforces in "required" mode.
        }
        return key
    }

    /// PEM "PUBLIC KEY" (X.509 SubjectPublicKeyInfo) -> SecKey. Security.framework wants the
    /// inner PKCS#1 RSAPublicKey, so the SPKI wrapper is peeled off first.
    static func rsaPublicKey(pem: String) -> SecKey? {
        let body = pem.components(separatedBy: "\n").filter { !$0.hasPrefix("-----") }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let der = Data(base64Encoded: body, options: .ignoreUnknownCharacters) else { return nil }
        let pkcs1 = spkiToPkcs1(der) ?? der
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]
        return SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, nil)
    }

    /// SEQUENCE { SEQUENCE { algorithm }, BIT STRING { 0x00, RSAPublicKey } } -> RSAPublicKey.
    private static func spkiToPkcs1(_ der: Data) -> Data? {
        let bytes = [UInt8](der)
        var i = 0
        func readLength() -> Int? {
            guard i < bytes.count else { return nil }
            var len = Int(bytes[i])
            i += 1
            if len & 0x80 != 0 {
                let n = len & 0x7f
                guard n > 0, n <= 4, i + n <= bytes.count else { return nil }
                len = 0
                for _ in 0..<n {
                    len = (len << 8) | Int(bytes[i])
                    i += 1
                }
            }
            return len
        }
        guard i < bytes.count, bytes[i] == 0x30 else { return nil }
        i += 1
        guard readLength() != nil else { return nil }
        guard i < bytes.count, bytes[i] == 0x30 else { return nil }
        i += 1
        guard let algLen = readLength() else { return nil }
        i += algLen
        guard i < bytes.count, bytes[i] == 0x03 else { return nil }
        i += 1
        guard let bitLen = readLength(), i < bytes.count, bytes[i] == 0x00 else { return nil }
        i += 1
        let end = i + bitLen - 1
        guard end <= bytes.count, end > i else { return nil }
        return Data(bytes[i..<end])
    }
}
