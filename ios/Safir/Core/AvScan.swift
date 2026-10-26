import Foundation

/// Antivirus check before a file is encrypted and sent (DLP policy `scan_files`, backend
/// av_scan.py, Android AvScan.kt): the plaintext goes to the organisation's own server once, over
/// the pinned TLS session, is streamed to ClamAV there and dropped. Fail closed: while the policy
/// requires the check, a file that couldn't be checked is not sent.
enum AvScan {
    private struct Result: Decodable { let clean: Bool; let threat: String? }

    /// Nil = may be sent; otherwise the text to show the user.
    @MainActor
    static func check(_ data: Data, filename: String) async -> String? {
        guard AppSecurity.shared.policy.scanFiles else { return nil }
        let api = Session.shared.api
        let boundary = "safir-\(UUID().uuidString)"
        var body = Data()
        let safeName = filename.replacingOccurrences(of: "\"", with: "")
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        var request = URLRequest(url: api.url("files/scan"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        do {
            let result = try api.decode(Result.self, from: try await api.perform(request))
            if result.clean { return nil }
            return "Антивирус нашёл угрозу в файле: \(result.threat ?? "?"). Файл не отправлен."
        } catch {
            AppLog.write("Antivirus check failed: \(error.localizedDescription)")
            return "Антивирусная проверка недоступна - файл не отправлен"
        }
    }
}
