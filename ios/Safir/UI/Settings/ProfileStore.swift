import Observation
import SwiftUI
import UIKit

/// schemas.UserResponse - my own account, with the privacy fields.
struct MyProfile: Codable, Equatable {
    let id: String
    let username: String
    var email: String?
    var fullName: String?
    var avatarUrl: String?
    var bio: String?
    var privacyLastSeen: String?
    var privacyAvatar: String?
    var privacyMessages: String?
    var readReceipts: Bool?
    var isPremium: Bool?

    var displayName: String {
        if let fullName, !fullName.isEmpty { return fullName }
        return username
    }
}

/// PATCH /users/me (schemas.UserUpdate) - nil fields are left out and stay unchanged.
struct ProfileUpdate: Encodable {
    var fullName: String?
    var bio: String?
    var privacyLastSeen: String?
    var privacyAvatar: String?
    var privacyMessages: String?
    var readReceipts: Bool?
}

/// schemas.SessionResponse - one signed-in device (GET /auth/sessions).
struct SessionInfo: Decodable, Identifiable, Equatable {
    let jti: String
    let deviceName: String
    let createdAt: String?
    let isCurrent: Bool

    var id: String { jti }
}

/// The settings screens' server side: profile, privacy, avatar, sessions, blocked people.
@MainActor
@Observable
final class ProfileStore {
    static let shared = ProfileStore()

    private(set) var me: MyProfile?
    private(set) var sessions: [SessionInfo] = []
    private(set) var blocked: [APIUser] = []
    private(set) var uploadingAvatar = false
    var error: String?

    private var api: APIClient { Session.shared.api }

    func load(fallback user: UserDTO) async {
        if me == nil || me?.id != user.id {
            me = MyProfile(id: user.id, username: user.username, email: user.email, fullName: user.fullName)
        }
        guard !DemoData.active else {
            me?.bio = "Учитель информатики · Исфара"
            me?.isPremium = true
            return
        }
        do {
            me = try await api.get("users/me", as: MyProfile.self)
        } catch {
            AppLog.write("Profile load failed: \(error.localizedDescription)")
        }
    }

    /// Applied on screen at once (switches and checkmarks don't jump back while the request
    /// runs) and rolled back if the server refuses.
    @discardableResult
    func update(_ change: ProfileUpdate) async -> Bool {
        let before = me
        if let v = change.fullName { me?.fullName = v }
        if let v = change.bio { me?.bio = v }
        if let v = change.privacyLastSeen { me?.privacyLastSeen = v }
        if let v = change.privacyAvatar { me?.privacyAvatar = v }
        if let v = change.privacyMessages { me?.privacyMessages = v }
        if let v = change.readReceipts { me?.readReceipts = v }
        guard !DemoData.active else { return true }
        do {
            let data = try await api.send("PATCH", "users/me", body: change)
            let updated = try api.decode(MyProfile.self, from: data)
            withAnimation(Safir.spring) { me = updated }
            return true
        } catch {
            withAnimation(Safir.spring) { me = before }
            self.error = error.localizedDescription
            return false
        }
    }

    /// POST /users/me/avatar (multipart, JPEG). The picture is cut to a 640 px square first.
    func uploadAvatar(_ image: UIImage) async {
        guard let jpeg = Self.squareJPEG(image, side: 640) else { return }
        uploadingAvatar = true
        defer { uploadingAvatar = false }
        let boundary = "safir-\(UUID().uuidString)"
        var request = URLRequest(url: api.url("users/me/avatar"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"avatar.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
        body.append(jpeg)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        do {
            let data = try await api.perform(request)
            let updated = try api.decode(MyProfile.self, from: data)
            withAnimation(Safir.spring) { me = updated }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadSessions() async {
        guard !DemoData.active else {
            sessions = [SessionInfo(jti: "a", deviceName: UIDevice.current.name, createdAt: nil, isCurrent: true),
                        SessionInfo(jti: "b", deviceName: "Redmi Note 12", createdAt: "2026-10-20T09:12:00", isCurrent: false),
                        SessionInfo(jti: "c", deviceName: "Safir Desktop · Windows", createdAt: "2026-10-18T17:40:00", isCurrent: false)]
            return
        }
        do {
            let list = try await api.get("auth/sessions", as: [SessionInfo].self)
            withAnimation(Safir.spring) { sessions = list.sorted { $0.isCurrent && !$1.isCurrent } }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func revoke(_ session: SessionInfo) async {
        if !DemoData.active {
            do { try await api.send("DELETE", "auth/sessions/\(session.jti)", body: nil) } catch {
                self.error = error.localizedDescription
                return
            }
        }
        withAnimation(Safir.spring) { sessions.removeAll { $0.jti == session.jti } }
    }

    func revokeOthers() async {
        if !DemoData.active {
            do { try await api.send("POST", "auth/sessions/revoke-others", body: nil) } catch {
                self.error = error.localizedDescription
                return
            }
        }
        withAnimation(Safir.spring) { sessions.removeAll { !$0.isCurrent } }
    }

    func loadBlocked() async {
        guard !DemoData.active else { return }
        do {
            let list = try await api.get("users/me/blocked", as: [APIUser].self)
            withAnimation(Safir.spring) { blocked = list }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func unblock(_ user: APIUser) async {
        do {
            try await api.send("DELETE", "users/\(user.id)/block", body: nil)
            withAnimation(Safir.spring) { blocked.removeAll { $0.id == user.id } }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private static func squareJPEG(_ image: UIImage, side: CGFloat) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = side / min(size.width, size.height)
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.jpegData(withCompressionQuality: 0.85) { _ in
            image.draw(in: CGRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2,
                                  width: drawn.width, height: drawn.height))
        }
    }
}
