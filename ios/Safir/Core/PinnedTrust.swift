import CryptoKit
import Foundation
import Security

/// The production server is a bare IP with a self-signed certificate (Let's Encrypt doesn't issue
/// for IPs), same as Android's network_security_config.xml: for that one host only the bundled
/// certificate is trusted - not system CAs.
///
/// An organisation with its own PKI (DEPLOYMENT.md §20, Android OrgTrust.kt) adds through the MDM
/// (Mdm.swift -> shared Keychain): `org_ca_pem` - its CA certificates, trusted on top of the
/// system ones; `server_pins` - `sha256/<base64 SPKI>` pins for the server host: a chain without
/// one of these keys is refused even if a trusted CA signed it.
final class PinnedTrustDelegate: NSObject, URLSessionDelegate {
    static let pinnedHost = "129.101.119.187"

    private let anchor: SecCertificate? = {
        guard let url = Bundle.main.url(forResource: "safir_selfsigned", withExtension: "der"),
              let data = try? Data(contentsOf: url) else { return nil }
        return SecCertificateCreateWithData(nil, data as CFData)
    }()

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }
        let host = challenge.protectionSpace.host
        let orgCAs = Self.orgCertificates()
        let pins = Self.pins(for: host)

        if host == Self.pinnedHost {
            guard let anchor else {
                AppLog.write("Pinned certificate missing from the bundle")
                return (.cancelAuthenticationChallenge, nil)
            }
            SecTrustSetAnchorCertificates(trust, ([anchor] + orgCAs) as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust, true)
        } else if !orgCAs.isEmpty {
            SecTrustSetAnchorCertificates(trust, orgCAs as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust, false)
        } else if pins.isEmpty {
            return (.performDefaultHandling, nil)
        }

        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error) else {
            AppLog.write("TLS check failed for \(host): \(error.map { String(describing: $0) } ?? "unknown")")
            return (.cancelAuthenticationChallenge, nil)
        }
        if !pins.isEmpty {
            let chain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
            guard chain.contains(where: { Self.spkiPin($0).map(pins.contains) ?? false }) else {
                AppLog.write("TLS pin mismatch for \(host)")
                return (.cancelAuthenticationChallenge, nil)
            }
        }
        return (.useCredential, URLCredential(trust: trust))
    }

    // MARK: - Organisation CA and pins (written by Mdm.swift)

    private static func orgCertificates() -> [SecCertificate] {
        guard let pem = Keychain.get("org_ca_pem"), !pem.isEmpty else { return [] }
        return pem.components(separatedBy: "-----BEGIN CERTIFICATE-----").dropFirst().compactMap { block in
            guard let body = block.components(separatedBy: "-----END CERTIFICATE-----").first else { return nil }
            let base64 = body.components(separatedBy: .whitespacesAndNewlines).joined()
            guard let der = Data(base64Encoded: base64) else { return nil }
            return SecCertificateCreateWithData(nil, der as CFData)
        }
    }

    /// Pins apply to the configured server host only, like OkHttp's CertificatePinner on Android.
    private static func pins(for host: String) -> Set<String> {
        guard let raw = Keychain.get("server_pins"), !raw.isEmpty,
              let server = Keychain.get("base_url").flatMap(URL.init(string:))?.host ?? APIClient.defaultServer.host,
              server == host else { return [] }
        return Set(raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
    }

    /// "sha256/<base64>" of the certificate's SubjectPublicKeyInfo. Security.framework only gives
    /// the raw key, so the DER header of the SPKI is put back for the common key types.
    static func spkiPin(_ cert: SecCertificate) -> String? {
        guard let key = SecCertificateCopyKey(cert),
              let raw = SecKeyCopyExternalRepresentation(key, nil) as Data?,
              let attrs = SecKeyCopyAttributes(key) as? [String: Any],
              let type = attrs[kSecAttrKeyType as String] as? String,
              let bits = attrs[kSecAttrKeySizeInBits as String] as? Int else { return nil }
        let rsa = type == (kSecAttrKeyTypeRSA as String)
        let ec = type == (kSecAttrKeyTypeECSECPrimeRandom as String)
        let header: [UInt8]
        if rsa && bits == 2048 {
            header = [0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d,
                      0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00]
        } else if rsa && bits == 4096 {
            header = [0x30, 0x82, 0x02, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d,
                      0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x02, 0x0f, 0x00]
        } else if ec && bits == 256 {
            header = [0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06,
                      0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00]
        } else if ec && bits == 384 {
            header = [0x30, 0x76, 0x30, 0x10, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06,
                      0x05, 0x2b, 0x81, 0x04, 0x00, 0x22, 0x03, 0x62, 0x00]
        } else {
            return nil
        }
        let digest = SHA256.hash(data: Data(header) + raw)
        return "sha256/" + Data(digest).base64EncodedString()
    }
}
