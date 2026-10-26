import SwiftUI

/// Second factor at login (mfa_policy.py): TOTP code from the authenticator app.
struct MfaCodeView: View {
    @Environment(Session.self) private var session
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Код из приложения-аутентификатора") {
                    TextField("123456", text: $code)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
                Section {
                    Button("Подтвердить") {
                        Task { await submit() }
                    }
                    .disabled(busy || code.count < 6)
                    Button("Отмена", role: .cancel) { session.cancelMfa() }
                }
            }
            .navigationTitle("Вход")
        }
    }

    private func submit() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await session.verifyMfa(code: code)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct TotpSetupResponse: Decodable {
    let secret: String
    let otpauthUri: String
}

/// The organisation requires 2FA and this account has none yet (mfa_policy.py): get a secret
/// (POST /auth/2fa/setup), add it to an authenticator app, confirm with a code (/auth/2fa/enable).
struct MfaEnrollView: View {
    let pendingToken: String
    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL
    @State private var setup: TotpSetupResponse?
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Ваша организация требует двухфакторную аутентификацию. Добавьте ключ в приложение-аутентификатор (Google Authenticator, Microsoft Authenticator и т. п.) и введите код из него.")
                        .font(.footnote)
                }
                if let setup {
                    Section("Ключ") {
                        Text(setup.secret).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        Button("Скопировать ключ") { UIPasteboard.general.string = setup.secret }
                        if let url = URL(string: setup.otpauthUri) {
                            Button("Открыть в аутентификаторе") { openURL(url) }
                        }
                    }
                    Section("Код") {
                        TextField("123456", text: $code)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                        Button("Подтвердить") { Task { await enable() } }
                            .disabled(busy || code.count < 6)
                    }
                } else {
                    ProgressView()
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button("Отмена", role: .cancel) { session.cancelMfa() }
                }
            }
            .navigationTitle("Двухфакторная защита")
            .task { await load() }
        }
    }

    private func load() async {
        do {
            let data = try await session.api.send("POST", "auth/2fa/setup", body: nil, bearer: pendingToken)
            setup = try session.api.decode(TotpSetupResponse.self, from: data)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func enable() async {
        busy = true
        defer { busy = false }
        do {
            let data = try await session.api.send("POST", "auth/2fa/enable",
                                                  body: TotpCodeRequest(code: code, deviceName: session.deviceName),
                                                  bearer: pendingToken)
            try await session.accept(try session.api.decode(TokenResponse.self, from: data))
        } catch {
            self.error = error.localizedDescription
        }
    }
}
