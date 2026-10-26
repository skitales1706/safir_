import SwiftUI

struct LoginView: View {
    @Environment(Session.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showTelegram = false
    @State private var showRegister = false
    @State private var sso: SSOConfig?
    @State private var ssoLogin = SSOLogin()

    private var ssoOnly: Bool { Mdm.shared.config.requireSso }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        SafirLogo(size: 88)
                        Text("Safir").font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(Safir.text)
                        Text("Защищённый мессенджер организации.\nСообщения шифруются на вашем устройстве.")
                            .font(.footnote).multilineTextAlignment(.center).foregroundStyle(Safir.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .listRowBackground(Color.clear)
                }
                // MDM "SSO only" (Mdm.swift): no password, Telegram or sign-up - just the organisation.
                if !ssoOnly {
                    Section {
                        TextField("Email", text: $email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Пароль", text: $password)
                            .textContentType(.password)
                    }
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
                if !ssoOnly {
                    Section {
                        Button {
                            Task { await submit() }
                        } label: {
                            HStack {
                                Text("Войти")
                                if busy {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(busy || email.isEmpty || password.isEmpty)
                    }
                }
                Section {
                    if !ssoOnly {
                        Button { showTelegram = true } label: { Label("Войти через Telegram", systemImage: "paperplane") }
                    }
                    if let sso, sso.enabled || ssoOnly {
                        Button { Task { await signInSSO() } } label: {
                            Label(sso.label ?? "Войти через организацию (SSO)", systemImage: "building.2")
                        }
                        .disabled(busy)
                    }
                    if !ssoOnly && !Mdm.shared.config.disableRegistration {
                        Button { showRegister = true } label: { Label("Регистрация", systemImage: "person.badge.plus") }
                    }
                }
                if Accounts.shared.adding {
                    // "Add account" (Accounts.swift): back to the account that is still signed in.
                    Section {
                        Button("Отмена - вернуться в свой аккаунт") { Task { await Accounts.shared.cancelAdding() } }
                    }
                }
                Section {
                    NavigationLink("Журнал") { LogView() }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showTelegram) { TelegramLoginView() }
            .sheet(isPresented: $showRegister) { RegisterView() }
            .task { sso = try? await session.api.get("auth/sso/config", as: SSOConfig.self) }
        }
    }

    private func signInSSO() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await ssoLogin.signIn(session: session)
        } catch {
            AppLog.write("SSO failed: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }

    private func submit() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await session.login(email: email, password: password)
            password = ""
        } catch {
            AppLog.write("Login failed: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }
}
