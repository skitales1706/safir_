import Foundation
import Observation

/// One account signed in on this phone (Telegram's "add account").
struct StoredAccount: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var login: String
}

/// Several accounts side by side, like Telegram: one is active (its token/user sit in the live
/// Keychain keys every other part of the app already reads), the others wait in their own
/// Keychain slots, each with its own database file (Database.url(forAccount:)) and Signal
/// identity. Only the active one keeps a WebSocket; the others still get pushes, and the push
/// extension names the account for those (it can decrypt only the active one).
/// Limit: premium.LIMITS["accounts"] - 3 free, 5 with Premium.
@MainActor
@Observable
final class Accounts {
    static let shared = Accounts()
    private static let listKey = "accounts"
    static let freeLimit = 3

    private(set) var list: [StoredAccount] = []
    /// The login screen is open to add another account on top of a signed-in one.
    private(set) var adding = false
    private(set) var limit = Accounts.freeLimit
    /// Where to go back if adding is cancelled.
    private var returnTo: String?

    private init() {
        if let json = Keychain.get(Self.listKey)?.data(using: .utf8),
           let saved = try? JSONDecoder().decode([StoredAccount].self, from: json) {
            list = saved
        }
        // An install from before multi-account: its one signed-in account becomes the first.
        if list.isEmpty, let token = Keychain.get("auth_token"), let user = Self.decodeUser(Keychain.get("user")) {
            remember(user: user, token: token)
        }
    }

    var activeId: String? { Keychain.get("account_id") }
    var canAdd: Bool { list.count < limit }
    var others: [StoredAccount] { list.filter { $0.id != activeId } }

    // MARK: Slots

    private static func slot(_ id: String, _ key: String) -> String { "acct.\(id).\(key)" }

    private static func decodeUser(_ json: String?) -> UserDTO? {
        json?.data(using: .utf8).flatMap { try? JSONDecoder().decode(UserDTO.self, from: $0) }
    }

    private func save() {
        Keychain.set((try? JSONEncoder().encode(list)).flatMap { String(data: $0, encoding: .utf8) }, for: Self.listKey)
    }

    /// Every successful sign-in (Session.accept) - adds or refreshes the account and its slot.
    func remember(user: UserDTO, token: String) {
        let id = user.id.lowercased()
        let name = (user.fullName?.isEmpty == false ? user.fullName : nil) ?? user.username
        let entry = StoredAccount(id: id, name: name, login: user.email ?? "@\(user.username)")
        if let i = list.firstIndex(where: { $0.id == id }) { list[i] = entry } else { list.append(entry) }
        Keychain.set(token, for: Self.slot(id, "auth_token"))
        Keychain.set((try? JSONEncoder().encode(user)).flatMap { String(data: $0, encoding: .utf8) }, for: Self.slot(id, "user"))
        adding = false
        returnTo = nil
        save()
    }

    /// Signed out (or deleted / revoked): the account and its slot go; its local database too
    /// unless keepData (a session that merely expired keeps the chats for the next sign-in).
    func forget(_ id: String, keepData: Bool = false) {
        list.removeAll { $0.id == id }
        Keychain.set(nil, for: Self.slot(id, "auth_token"))
        Keychain.set(nil, for: Self.slot(id, "user"))
        if !keepData, id != Keychain.get("db_legacy_owner"), let url = try? Database.url(forAccount: id) {
            Database.remove(url: url)
        }
        save()
    }

    func session(for id: String) -> (token: String, user: UserDTO)? {
        guard let token = Keychain.get(Self.slot(id, "auth_token")),
              let user = Self.decodeUser(Keychain.get(Self.slot(id, "user"))) else { return nil }
        return (token, user)
    }

    func name(of id: String) -> String? { list.first { $0.id == id }?.name }

    /// The limit follows Premium (backend premium.LIMITS["accounts"]).
    func refreshLimit() async {
        struct Info: Decodable { let limits: [String: Int64] }
        guard let info = try? await Session.shared.api.get("users/me/premium", as: Info.self) else { return }
        limit = max(Int(info.limits["accounts"] ?? Int64(Self.freeLimit)), 1)
    }

    // MARK: Add / switch

    /// "Добавить аккаунт": parks the current account (nothing is signed out on the server) and
    /// shows the login screen. False when the limit is reached.
    func beginAdding() -> Bool {
        guard canAdd, !adding else { return false }
        returnTo = activeId
        adding = true
        Session.shared.park()
        return true
    }

    /// Back to the account that was active before "add account".
    func cancelAdding() async {
        adding = false
        guard let id = returnTo else { return }
        returnTo = nil
        await switchTo(id)
    }

    func switchTo(_ id: String) async {
        guard id != activeId || Session.shared.isParked, let saved = session(for: id) else { return }
        await Session.shared.activate(accountId: id, token: saved.token, user: saved.user)
    }
}
