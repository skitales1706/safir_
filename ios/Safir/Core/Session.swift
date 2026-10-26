import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class Session {
    static let shared = Session()

    enum State: Equatable {
        case loggedOut
        case mfaCode(pendingToken: String)
        case mfaSetupRequired(pendingToken: String)
        case loggedIn(UserDTO)
    }

    private(set) var state: State = .loggedOut
    private(set) var pushToken: String?
    let api: APIClient
    /// Stable per install, never regenerated (same meaning as Android's getOrCreateDeviceId).
    let deviceId: String

    private init() {
        api = APIClient.shared
        if let existing = Keychain.get("device_id") {
            deviceId = existing
        } else {
            deviceId = UUID().uuidString.lowercased()
            Keychain.set(deviceId, for: "device_id")
        }
        if let token = Keychain.get("auth_token"),
           let data = Keychain.get("user")?.data(using: .utf8),
           let user = try? JSONDecoder().decode(UserDTO.self, from: data) {
            api.token = token
            state = .loggedIn(user)
        }
        if DemoData.active {
            if DemoData.loggedOut {
                state = .loggedOut
            } else {
                DemoData.seed()
                state = .loggedIn(DemoData.me)
                ChatService.shared.startDemo(myUserId: DemoData.me.id)
            }
        }
    }

    var deviceName: String { UIDevice.current.name }

    func login(email: String, password: String) async throws {
        let body = LoginRequest(email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                                password: password, deviceName: deviceName)
        let response = try await api.post("auth/login", body: body, as: TokenResponse.self)
        try await accept(response)
    }

    func verifyMfa(code: String) async throws {
        guard case .mfaCode(let pending) = state else { return }
        let body = TotpCodeRequest(code: code.trimmingCharacters(in: .whitespaces), deviceName: deviceName)
        // The pending token only opens /auth/2fa/* - passed explicitly, never kept as the session.
        let data = try await api.send("POST", "auth/2fa/verify", body: body, bearer: pending)
        try await accept(try api.decode(TokenResponse.self, from: data))
    }

    /// Every sign-in path ends here (password, Telegram, SSO, 2FA).
    func accept(_ response: TokenResponse) async throws {
        if response.mfaSetupRequired == true {
            state = .mfaSetupRequired(pendingToken: response.accessToken)
            return
        }
        if response.mfaRequired == true {
            state = .mfaCode(pendingToken: response.accessToken)
            return
        }
        // Each account has its own database file (Accounts.swift), so another account signing
        // in never mixes its chats and Signal state with the previous one's.
        let id = response.user.id.lowercased()
        if Keychain.get("account_id") != id {
            ChatService.shared.stop()
            try? Database.shared.reopen(url: Database.url(forAccount: id))
        }
        Keychain.set(id, for: "account_id")
        api.token = response.accessToken
        Keychain.set(response.accessToken, for: "auth_token")
        Keychain.set(String(data: try JSONEncoder().encode(response.user), encoding: .utf8), for: "user")
        Accounts.shared.remember(user: response.user, token: response.accessToken)
        parked = false
        state = .loggedIn(response.user)
        AppLog.write("Logged in")
        await startAfterLogin(user: response.user)
        await PushRegistrar.requestAuthorization()
    }

    private(set) var deviceReady = false
    /// "Add account" is showing the login screen; the previous account is only set aside.
    private(set) var parked = false
    var isParked: Bool { parked }
    private(set) var setupError: String?
    private var started = false

    /// App launch with a saved session.
    func resume() async {
        APIClient.onAuthFailure = { status, detail in
            Task { @MainActor in Session.shared.handleAuthFailure(status: status, detail: detail) }
        }
        guard !started, !DemoData.active, case .loggedIn(let user) = state else { return }
        await startAfterLogin(user: user)
        await PushRegistrar.requestAuthorization()
    }

    /// Device registration + Signal bundle (same order as Android's MainViewModel), then the
    /// push tokens and the message pipeline. Runs after login and on every launch.
    func startAfterLogin(user: UserDTO) async {
        started = true
        // Identity keys are scoped by email like Android; a Telegram-login account has none.
        let email = user.email ?? ""
        await SignalService.shared.configure(email: email.isEmpty ? user.id : email)
        do {
            try await api.send("POST", "devices/register", body: DeviceRegisterRequest(
                deviceId: deviceId, deviceName: deviceName,
                protocolVersion: SignalService.protocolVersion, isRooted: JailbreakCheck.isJailbroken))
            if await SignalService.shared.myDeviceId() == nil {
                try await SignalService.shared.ensureBundleUploaded(installId: deviceId)
            } else {
                await SignalService.shared.topUpIfNeeded(installId: deviceId)
            }
            deviceReady = true
            setupError = nil
            CallService.shared.registerVoIP()
            await sendPushTokens()
            ChatService.shared.start(myUserId: user.id.lowercased(), installId: deviceId)
        } catch {
            setupError = error.localizedDescription
            AppLog.write("Device setup failed: \(error.localizedDescription)")
        }
    }

    func retrySetup() async {
        guard case .loggedIn(let user) = state else { return }
        await startAfterLogin(user: user)
    }

    /// "Add account": stop the active account locally (still signed in on the server, its slot
    /// in Accounts keeps the token) and show the login screen.
    func park() {
        ChatService.shared.stop()
        api.token = nil
        deviceReady = false
        started = false
        setupError = nil
        parked = true
        Keychain.set(nil, for: "auth_token")
        Keychain.set(nil, for: "user")
        state = .loggedOut
    }

    /// Make another signed-in account the active one: its database, token and pipeline.
    func activate(accountId id: String, token: String, user: UserDTO) async {
        ChatService.shared.stop()
        do {
            try Database.shared.reopen(url: Database.url(forAccount: id))
        } catch {
            AppLog.write("Account switch failed: \(error.localizedDescription)")
            return
        }
        Keychain.set(id, for: "account_id")
        Keychain.set(token, for: "auth_token")
        Keychain.set(String(data: (try? JSONEncoder().encode(user)) ?? Data(), encoding: .utf8), for: "user")
        api.token = token
        deviceReady = false
        started = false
        setupError = nil
        parked = false
        state = .loggedIn(user)
        AppLog.write("Switched account")
        await resume()
        await AppSecurity.shared.refreshPolicy()
    }

    /// After this account is gone from the phone: the next signed-in one takes over, if any.
    private func continueWithAnotherAccount(leaving id: String?, keepData: Bool = false) {
        if let id { Accounts.shared.forget(id, keepData: keepData) }
        guard let next = Accounts.shared.list.first else { return }
        Task { await Accounts.shared.switchTo(next.id) }
    }

    func logout() async {
        ChatService.shared.stop()
        if api.token != nil {
            // Drop this install's device row so nobody keeps encrypting to it, then the session.
            _ = try? await api.send("DELETE", "devices/\(deviceId)", body: nil)
            _ = try? await api.send("POST", "auth/logout", body: nil)
        }
        let leaving = Keychain.get("account_id")
        clearLocalSession()
        AppLog.write("Logged out")
        continueWithAnotherAccount(leaving: leaving)
    }

    /// 401 = token revoked/expired; 403 device_blocked / device_wiped = an admin cut this
    /// install off (routers/devices.py). A wipe erases chats and keys, then reports back.
    private func handleAuthFailure(status: Int, detail: String) {
        guard case .loggedIn = state else { return }
        switch (status, detail) {
        case (401, _):
            forceSignOut(reason: "session expired", wipe: false)
        case (403, "device_wiped"):
            let token = api.token
            let id = deviceId
            forceSignOut(reason: "remote wipe", wipe: true)
            Task {
                _ = try? await api.send("POST", "devices/\(id)/wiped", body: nil, bearer: token)
            }
        case (403, "device_blocked"), (403, "device_not_allowed"):
            forceSignOut(reason: detail, wipe: false)
        default:
            break
        }
    }

    func forceSignOut(reason: String, wipe: Bool) {
        ChatService.shared.stop()
        if wipe {
            try? Schema.wipeAccountData(Database.shared)
            MediaCache.clearAll()
        }
        let leaving = Keychain.get("account_id")
        clearLocalSession()
        AppLog.write("Signed out by the server: \(reason)")
        continueWithAnotherAccount(leaving: leaving, keepData: !wipe)
    }

    private func clearLocalSession() {
        api.token = nil
        deviceReady = false
        started = false
        Keychain.set(nil, for: "auth_token")
        Keychain.set(nil, for: "user")
        state = .loggedOut
    }

    func cancelMfa() {
        api.token = nil
        state = .loggedOut
    }

    func pushTokenReceived(_ token: String) {
        pushToken = token
        AppLog.write("APNs token received (\(token.prefix(8))...)")
        Task { await sendPushTokens() }
    }

    private(set) var voipToken: String?

    func voipTokenReceived(_ token: String?) {
        voipToken = token
        Task { await sendPushTokens() }
    }

    /// PUT /devices/{id}/push (backend apns.py) - only once this install is a registered device.
    private func sendPushTokens() async {
        guard deviceReady, pushToken != nil || voipToken != nil else { return }
        #if DEBUG
        let sandbox = true
        #else
        let sandbox = false
        #endif
        do {
            try await api.send("PUT", "devices/\(deviceId)/push",
                               body: PushTokenRequest(apnsToken: pushToken, voipToken: voipToken, sandbox: sandbox))
            AppLog.write("Push tokens registered")
        } catch {
            AppLog.write("Push token registration failed: \(error.localizedDescription)")
        }
    }
}
