import SwiftUI

/// GET /users/me/account (backend routers/account.py).
struct AccountInfo: Decodable {
    let canDelete: Bool
    let reason: String?
    let confirmWith: String      // "password" | "email" | "telegram" | "none"
    let accountTtlDays: Int
    let ttlChoices: [Int]
}

enum AccountTTL {
    static func title(_ days: Int) -> String {
        switch days {
        case 0: return "Никогда"
        case 30: return "1 месяц"
        case 90: return "3 месяца"
        case 180: return "6 месяцев"
        case 365: return "1 год"
        case 545: return "18 месяцев"
        case 730: return "2 года"
        default: return "\(days) дн."
        }
    }
}

/// Accounts on this phone (Accounts.swift): switch, add (limit 3 / Premium 5), like Telegram.
struct AccountsPage: View {
    @State private var accounts = Accounts.shared
    @State private var limitAlert = false

    var body: some View {
        List {
            Section {
                ForEach(accounts.list) { account in
                    Button {
                        guard account.id != accounts.activeId else { return }
                        Safir.tap()
                        Task { await accounts.switchTo(account.id) }
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(name: account.name, path: nil, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.name).foregroundStyle(Safir.text)
                                Text(account.login).font(.caption).foregroundStyle(Safir.muted)
                            }
                            Spacer()
                            if account.id == accounts.activeId {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Safir.accent)
                            }
                        }
                    }
                }
                Button {
                    if !accounts.beginAdding() { limitAlert = true }
                } label: {
                    Label("Добавить аккаунт", systemImage: "plus.circle")
                }
            } footer: {
                Text("Одновременно можно войти в \(accounts.limit) аккаунта (с Premium - до 5).")
            }
        }
        .navigationTitle("Аккаунты")
        .navigationBarTitleDisplayMode(.inline)
        .task { await accounts.refreshLimit() }
        .alert("Достигнут лимит", isPresented: $limitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("На одном устройстве можно держать \(accounts.limit) аккаунта. Подключите Premium, чтобы добавить до 5, или выйдите из одного из аккаунтов.")
        }
    }
}

/// "Если я не захожу" - self-destruct after inactivity (PUT /users/me/account-ttl).
struct AccountTTLPage: View {
    @State private var info: AccountInfo?
    @State private var error: String?

    var body: some View {
        List {
            if let info {
                Section {
                    ForEach(info.ttlChoices, id: \.self) { days in
                        Button {
                            Task { await set(days) }
                        } label: {
                            HStack {
                                Text(AccountTTL.title(days)).foregroundStyle(Safir.text)
                                Spacer()
                                if days == info.accountTtlDays { Image(systemName: "checkmark").foregroundStyle(Safir.accent) }
                            }
                        }
                    }
                } footer: {
                    Text("Если вы не заходите в Safir это время, аккаунт удалится вместе с контактами и группами. Аккаунты организации (AD, SSO) так не удаляются.")
                }
            } else if let error {
                Text(error).foregroundStyle(.red)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Удалить автоматически")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            info = try await Session.shared.api.get("users/me/account", as: AccountInfo.self)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func set(_ days: Int) async {
        struct Body: Encodable { let days: Int }
        do {
            let data = try await Session.shared.api.send("PUT", "users/me/account-ttl", body: Body(days: days))
            info = try Session.shared.api.decode(AccountInfo.self, from: data)
            Safir.tap()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// "Удалить аккаунт": password, or a code sent to the e-mail / Telegram (POST /users/me/delete).
struct DeleteAccountPage: View {
    @State private var info: AccountInfo?
    @State private var secret = ""
    @State private var codeSent = false
    @State private var busy = false
    @State private var confirm = false
    @State private var error: String?

    private var usesPassword: Bool { info?.confirmWith == "password" }

    var body: some View {
        List {
            Section {
                Label("Удаление нельзя отменить", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text("Профиль, контакты, ключи шифрования и устройства будут удалены, вы выйдете из всех групп и каналов. В чатах у собеседников останутся сообщения от «Удалённый аккаунт».")
                    .font(.footnote).foregroundStyle(Safir.muted)
            }
            if let info {
                if !info.canDelete {
                    Section { Text(reasonText(info.reason)).foregroundStyle(Safir.muted) }
                } else if usesPassword {
                    Section("Подтвердите паролем") {
                        SecureField("Пароль", text: $secret).textContentType(.password)
                    }
                } else {
                    Section {
                        if codeSent {
                            TextField("Код из 6 цифр", text: $secret).keyboardType(.numberPad)
                        }
                        Button(codeSent ? "Отправить код ещё раз" : "Получить код") { Task { await sendCode() } }
                            .disabled(busy)
                    } header: {
                        Text(info.confirmWith == "telegram" ? "Код придёт в Telegram" : "Код придёт на почту")
                    }
                }
                if info.canDelete {
                    Section {
                        Button("Удалить аккаунт", role: .destructive) { confirm = true }
                            .disabled(busy || secret.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } else {
                ProgressView()
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Удалить аккаунт")
        .navigationBarTitleDisplayMode(.inline)
        .task { info = try? await Session.shared.api.get("users/me/account", as: AccountInfo.self) }
        .confirmationDialog("Удалить аккаунт навсегда?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { Task { await delete() } }
        }
    }

    private func reasonText(_ reason: String?) -> String {
        guard let reason else { return "Этот аккаунт нельзя удалить отсюда." }
        if reason.contains("organisation") { return "Аккаунтом управляет ваша организация - удалить его может администратор." }
        if reason.contains("Administrators") { return "Сначала передайте роль администратора другому сотруднику." }
        return reason
    }

    private func sendCode() async {
        busy = true
        defer { busy = false }
        do {
            try await Session.shared.api.send("POST", "users/me/delete/code", body: nil)
            codeSent = true
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete() async {
        struct Body: Encodable { let password: String?; let code: String? }
        busy = true
        defer { busy = false }
        let value = secret.trimmingCharacters(in: .whitespaces)
        do {
            try await Session.shared.api.send("POST", "users/me/delete",
                                              body: Body(password: usesPassword ? value : nil, code: usesPassword ? nil : value))
            Session.shared.forceSignOut(reason: "account deleted", wipe: true)
        } catch {
            if (error as? APIError)?.status == 400 {
                self.error = usesPassword ? "Неверный пароль" : "Неверный или просроченный код"
            } else {
                self.error = error.localizedDescription
            }
        }
    }
}
