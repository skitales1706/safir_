import CryptoKit
import Foundation

/// Decrypted attachments on disk. Caches/ - iOS may purge it, everything here can be downloaded
/// and decrypted again (the key stays in the message row).
enum MediaCache {
    static var directory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Files I send are kept outside the purgeable cache until the upload is done.
    static var outgoingDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("outgoing", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func file(messageId: String, ext: String) -> URL {
        directory.appendingPathComponent("med_\(messageId.replacingOccurrences(of: "/", with: "_")).\(ext)")
    }

    static func remove(messageId: String) {
        let prefix = "med_\(messageId)"
        let fm = FileManager.default
        for url in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        where url.lastPathComponent.hasPrefix(prefix) {
            try? fm.removeItem(at: url)
        }
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: outgoingDirectory)
    }

    static func ext(for type: String) -> String {
        switch type {
        case "image": return "jpg"
        case "video": return "mp4"
        case "audio": return "m4a"
        default: return "bin"
        }
    }
}

/// Upload / download of encrypted attachments. Uploads are resumable (backend
/// resumable_uploads.py) so a dropped link continues from the last byte; downloads resume with
/// HTTP Range. The server only ever sees ciphertext.
@MainActor
final class MediaService {
    static let shared = MediaService()
    private var inFlight: [String: Task<URL?, Never>] = [:]
    private var api: APIClient { Session.shared.api }

    private struct UploadSession: Codable {
        let uploadId: String
        let size: Int
        let received: Int
    }

    private struct UploadCreate: Encodable {
        let size: Int
    }

    private struct UploadDone: Decodable {
        let fileUrl: String
    }

    /// Uploads ciphertext, returns the absolute URL on our server.
    func upload(_ data: Data, onProgress: @escaping (Double) -> Void = { _ in }) async throws -> String {
        let session = try await api.post("upload/sessions", body: UploadCreate(size: data.count), as: UploadSession.self)
        var offset = session.received
        let chunk = 512 * 1024
        var failures = 0
        while offset < data.count {
            let end = min(offset + chunk, data.count)
            var request = URLRequest(url: api.url("upload/sessions/\(session.uploadId)", query: ["offset": String(offset)]))
            request.httpMethod = "PUT"
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.httpBody = data.subdata(in: offset..<end)
            do {
                let body = try await api.perform(request)
                offset = try api.decode(UploadSession.self, from: body).received
                failures = 0
                onProgress(Double(offset) / Double(max(data.count, 1)))
            } catch let error as APIError where error.status == 409 {
                // Offset mismatch: ask where the server is and continue from there.
                offset = try await api.get("upload/sessions/\(session.uploadId)", as: UploadSession.self).received
            } catch {
                failures += 1
                guard ChatService.isTransient(error), failures <= 5 else { throw error }
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 * failures))
                if let s = try? await api.get("upload/sessions/\(session.uploadId)", as: UploadSession.self) {
                    offset = s.received
                }
            }
        }
        let body = try await api.send("POST", "upload/sessions/\(session.uploadId)/complete", body: nil)
        let done = try api.decode(UploadDone.self, from: body)
        return api.ownServerURL(done.fileUrl)?.absoluteString ?? done.fileUrl
    }

    /// The decrypted file for a media message, downloading it once. Nil while there is nothing
    /// to show yet (instant send whose file isn't uploaded) or when it can't be decrypted.
    func resolve(_ m: MessageItem) async -> URL? {
        if let path = m.localPath, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let target = MediaCache.file(messageId: m.serverId, ext: MediaCache.ext(for: m.type))
        if FileManager.default.fileExists(atPath: target.path) { return target }
        guard !m.content.isEmpty, let keyB64 = m.fileKey, let key = MediaCrypto.key(fromBase64: keyB64),
              let url = api.ownServerURL(m.content) else { return nil }
        if let running = inFlight[m.serverId] { return await running.value }
        let messageId = m.serverId
        let task = Task<URL?, Never> { @MainActor in
            defer { self.inFlight[messageId] = nil }
            do {
                let sealed = try await self.download(url, partName: "med_\(messageId).part")
                let plain = try MediaCrypto.decrypt(sealed, key: key)
                try plain.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                return target
            } catch {
                AppLog.write("Media download failed: \(error.localizedDescription)")
                return nil
            }
        }
        inFlight[messageId] = task
        return await task.value
    }

    /// Ranged download into a part file that survives a dropped link.
    private func download(_ url: URL, partName: String) async throws -> Data {
        let part = MediaCache.directory.appendingPathComponent(partName)
        var attempt = 0
        while true {
            let have = ((try? FileManager.default.attributesOfItem(atPath: part.path))?[.size] as? NSNumber)?.intValue ?? 0
            var request = URLRequest(url: url)
            if have > 0 { request.setValue("bytes=\(have)-", forHTTPHeaderField: "Range") }
            do {
                let chunk = try await api.perform(request)
                if have > 0, let handle = try? FileHandle(forWritingTo: part) {
                    handle.seekToEndOfFile()
                    handle.write(chunk)
                    try? handle.close()
                } else {
                    try chunk.write(to: part)
                }
                let data = try Data(contentsOf: part)
                try? FileManager.default.removeItem(at: part)
                return data
            } catch let error as APIError where error.status == 416 {
                // Range past the end: the part file is stale - start over.
                try? FileManager.default.removeItem(at: part)
                attempt += 1
                if attempt > 2 { throw error }
            } catch {
                attempt += 1
                guard ChatService.isTransient(error), attempt <= 3 else { throw error }
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 * attempt))
            }
        }
    }
}
