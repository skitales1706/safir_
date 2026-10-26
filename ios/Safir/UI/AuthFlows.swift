import AuthenticationServices
import CryptoKit
import SwiftUI

// MARK: - Telegram login (backend routers/telegram_auth.py)

private struct TelegramStart: Decodable {
    let loginId: String
    let secret: String
    let botUrl: String
    let expiresIn: Int
}

private struct TelegramPoll: Encodable {
    let loginId: String
    let secret: String
    let deviceName: String
}

private struct TelegramPollResponse: Decodable {
    let status: String
    let token: TokenResponse?
    let phone: String?
    let suggestedName: String?
}

private struct TelegramRegister: Encodable {
    let loginId: String
    let secret: String
    let username: String
    let fullName: String
    let protocolVersion: Int
    let deviceName: String
}

/// Phone login through the organisation's Telegram bot: open the bot, share the phone number,
/// this screen polls until the server confirms (and asks for a name the first time).
struct TelegramLoginView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var start: TelegramStart?
    @State private var needsName = false
    @State private var fullName = ""
    @State private var username = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let start {
                    if needsName {
                        Section("Новый аккаунт") {
                            TextField("Имя и фамилия", text: $fullName)
                            TextField("Логин", text: $username)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                            Button("Создать") { Task { await register(start) } }
                                .disabled(fullName.isEmpty || username.count < 3)
                        }
                    } else {
                        Section {
                            Text("Откройте бота, нажмите «Старт» и поделитесь номером телефона. Этот экран продолжит сам.")
                            if let url = URL(string: start.botUrl) {
                                Button("Открыть Telegram") { openURL(url) }
                            }
                            HStack {
                                ProgressView()
                                Text("Ожидание подтверждения…").foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    ProgressView()
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Вход через Telegram")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .task { await run() }
        }
    }

    private func run() async {
        let api = session.api
        do {
            let started = try api.decode(TelegramStart.self, from: try await api.send("POST", "auth/telegram/start", body: nil))
            start = started
            if let url = URL(string: started.botUrl) { openURL(url) }
            let deadline = Date().addingTimeInterval(TimeInterval(started.expiresIn))
            while Date() < deadline && !Task.isCancelled && !needsName {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let body = TelegramPoll(loginId: started.loginId, secret: started.secret, deviceName: session.deviceName)
                guard let data = try? await api.send("POST", "auth/telegram/poll", body: body),
                      let poll = try? api.decode(TelegramPollResponse.self, from: data) else { continue }
                if poll.status == "authorized", let token = poll.token {
                    try await session.accept(token)
                    dismiss()
                    return
                }
                if poll.status == "needs_registration" {
                    fullName = poll.suggestedName ?? ""
                    needsName = true
                }
            }
            if !needsName && !Task.isCancelled { error = "Время ожидания истекло. Попробуйте снова." }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func register(_ start: TelegramStart) async {
        let api = session.api
        do {
            let body = TelegramRegister(loginId: start.loginId, secret: start.secret, username: username.lowercased(),
                                        fullName: fullName, protocolVersion: SignalService.protocolVersion,
                                        deviceName: session.deviceName)
            let data = try await api.send("POST", "auth/telegram/register", body: body)
            try await session.accept(try api.decode(TokenResponse.self, from: data))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Single sign-on (backend routers/sso.py: OIDC / SAML)

struct SSOConfig: Decodable {
    let enabled: Bool
    let label: String?
}

private struct SSOExchange: Encodable {
    let code: String
    let codeVerifier: String
    let deviceName: String
}

/// The browser part runs in ASWebAuthenticationSession; the server sends the result back to
/// safir://sso?code&state and the code is traded (with the PKCE verifier) for a session -
/// another app that registered safir:// can't use an intercepted code without the verifier.
@MainActor
final class SSOLogin: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let redirect = "safir://sso"
    private var webSession: ASWebAuthenticationSession?

    func signIn(session: Session) async throws {
        let verifier = Self.base64URL(Data((0..<48).map { _ in UInt8.random(in: 0...255) }))
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = UUID().uuidString
        let url = session.api.url("auth/sso/start", query: [
            "redirect_uri": Self.redirect, "code_challenge": challenge, "state": state, "device_name": session.deviceName,
        ])
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let web = ASWebAuthenticationSession(url: url, callbackURLScheme: "safir") { url, error in
                if let url {
                    cont.resume(returning: url)
                } else {
                    cont.resume(throwing: error ?? URLError(.cancelled))
                }
            }
            web.presentationContextProvider = self
            web.prefersEphemeralWebBrowserSession = true
            webSession = web
            web.start()
        }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            let reason = items.first(where: { $0.name == "error" })?.value ?? "SSO response was not valid"
            throw APIError(status: 0, detail: reason)
        }
        let data = try await session.api.send("POST", "auth/sso/exchange",
                                              body: SSOExchange(code: code, codeVerifier: verifier, deviceName: session.deviceName))
        try await session.accept(try session.api.decode(TokenResponse.self, from: data))
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Registration (POST /auth/register)

private struct RegisterRequest: Encodable {
    let username: String
    let email: String
    let fullName: String
    let password: String
    let protocolVersion: Int
    let deviceName: String
}

struct RegisterView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var fullName = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Имя и фамилия", text: $fullName)
                    TextField("Логин", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Email", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    SecureField("Пароль (от 8 символов)", text: $password).textContentType(.newPassword)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button("Зарегистрироваться") { Task { await register() } }
                        .disabled(busy || fullName.isEmpty || username.count < 3 || !email.contains("@") || password.count < 8)
                }
            }
            .navigationTitle("Регистрация")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
    }

    private func register() async {
        busy = true
        defer { busy = false }
        do {
            let body = RegisterRequest(username: username.lowercased(), email: email.lowercased(), fullName: fullName,
                                       password: password, protocolVersion: SignalService.protocolVersion,
                                       deviceName: session.deviceName)
            let data = try await session.api.send("POST", "auth/register", body: body)
            try await session.accept(try session.api.decode(TokenResponse.self, from: data))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
