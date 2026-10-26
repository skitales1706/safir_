import Observation
import SwiftUI

// MARK: - Premium

/// GET /users/me/premium (backend premium.info).
private struct PremiumInfo: Decodable {
    let isPremium: Bool
    let premiumUntil: String?
    let plans: [String: PlanPair]

    struct PlanPair: Decodable {
        let free: Int
        let premium: Int
    }
}

/// Android PremiumActivity: status hero, free vs Premium limits, Premium-only features.
struct PremiumPage: View {
    @State private var info: PremiumInfo?
    @State private var failed = false
    @State private var glow = false

    private static let limits: [(key: String, title: String, bytes: Bool)] = [
        ("upload_file_bytes", "Размер одного файла", true), ("storage_bytes", "Место для файлов", true),
        ("chat_folders", "Папки чатов", false), ("folder_chats", "Чатов в папке", false),
        ("ai_chat", "Вопросы Ёвару (за 5 мин)", false), ("ai_translate", "Перевод (за 5 мин)", false),
        ("ai_transcribe", "Голос в текст (за 5 мин)", false), ("ai_summarize", "Сводка чата (за 5 мин)", false),
    ]
    private static let features: [(icon: String, title: String)] = [
        ("sparkles", "Умный Ёвар (большая модель)"), ("face.smiling", "Все реакции, а не только 6 основных"),
        ("eye.slash", "Чтение без отметки «прочитано»"), ("person.crop.circle.badge.checkmark", "Сообщения и звонки только от контактов"),
        ("bolt.fill", "Ранний доступ к новинкам"), ("star.fill", "Значок ⭐ Premium в профиле"),
    ]

    var body: some View {
        SettingsPage(title: "Safir Premium") {
            hero.appearIn(0)
            if let info {
                SettingsGroup(header: "Лимиты") {
                    HStack {
                        Spacer()
                        Text(tr("Бесплатно")).frame(width: 78)
                        Text("Premium").frame(width: 78)
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Safir.muted)
                    .padding(.horizontal, 14).padding(.top, 10)
                    ForEach(Array(Self.limits.enumerated()), id: \.offset) { index, row in
                        if index > 0 { SettingsDivider(inset: 14) }
                        if let pair = info.plans[row.key] {
                            HStack {
                                Text(tr(row.title)).font(.subheadline).foregroundStyle(Safir.text)
                                Spacer(minLength: 6)
                                Text(Self.value(pair.free, bytes: row.bytes)).frame(width: 78)
                                    .foregroundStyle(Safir.muted)
                                Text(Self.value(pair.premium, bytes: row.bytes)).frame(width: 78)
                                    .fontWeight(.bold).foregroundStyle(Safir.accent)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                        }
                    }
                }
                .appearIn(1)

                SettingsGroup(header: "Возможности Premium",
                              footer: "Premium выдаёт администратор вашей организации. Бесплатный план ничего не отнимает — Premium только добавляет.") {
                    ForEach(Array(Self.features.enumerated()), id: \.offset) { index, feature in
                        if index > 0 { SettingsDivider() }
                        SettingsRow(icon: feature.icon, color: Tile.violet, title: feature.title) {
                            Image(systemName: info.isPremium ? "checkmark.circle.fill" : "lock.fill")
                                .foregroundStyle(info.isPremium ? Safir.online : Safir.muted)
                        }
                    }
                }
                .appearIn(2)
            } else if failed {
                Text(tr("Не удалось загрузить данные")).font(.footnote).foregroundStyle(Safir.muted)
            } else {
                ProgressView().padding(30)
            }
        }
        .task { await load() }
    }

    private var hero: some View {
        let premium = info?.isPremium == true
        return VStack(spacing: 10) {
            Image(systemName: "star.fill")
                .font(.system(size: 54))
                .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFD45A), Color(hex: 0xF59A23), Color(hex: 0xE0567F)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: Color(hex: 0xF59A23).opacity(glow ? 0.7 : 0.3), radius: glow ? 22 : 10)
                .symbolEffect(.bounce, value: info != nil)
                .padding(.top, 18)
            Text(tr(premium ? "У вас Premium" : "У вас бесплатный план"))
                .font(.system(size: 21, weight: .bold, design: .rounded))
            if premium, let until = info?.premiumUntil {
                Text(tr("до %@", TimeText.short(Dates.millis(until)))).font(.subheadline).foregroundStyle(Safir.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xF59A23).opacity(0.22), Color(hex: 0x8E6CEF).opacity(0.18), Safir.card],
                                     startPoint: .topLeading, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Safir.separator, lineWidth: 0.5))
        .onAppear {
            guard !DemoData.active else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { glow = true }
        }
    }

    private func load() async {
        if DemoData.active {
            let plans = Dictionary(uniqueKeysWithValues: Self.limits.map { ($0.key, PremiumInfo.PlanPair(free: 10, premium: 100)) })
            info = PremiumInfo(isPremium: true, premiumUntil: "2027-01-01T00:00:00", plans: plans)
            return
        }
        do {
            let loaded = try await Session.shared.api.get("users/me/premium", as: PremiumInfo.self)
            withAnimation(Safir.spring) { info = loaded }
        } catch {
            failed = true
        }
    }

    private static func value(_ v: Int, bytes: Bool) -> String {
        guard bytes else { return "\(v)" }
        let gb = Double(v) / 1_073_741_824
        return gb >= 1 ? tr("%@ ГБ", String(format: "%g", gb)) : tr("%@ МБ", String(v / 1_048_576))
    }
}

// MARK: - Change password

private struct ForgotPasswordBody: Encodable { let email: String }
private struct ResetPasswordBody: Encodable {
    let email: String
    let code: String
    let newPassword: String
}

/// Change the password through the e-mailed code (POST /auth/forgot-password + reset-password).
/// The server then ends every session, this one too, so the app signs in again afterwards.
struct ChangePasswordPage: View {
    let email: String
    @Environment(Session.self) private var session
    @State private var sent = false
    @State private var code = ""
    @State private var password = ""
    @State private var repeatPassword = ""
    @State private var busy = false
    @State private var error: String?
    @State private var done = false

    private var valid: Bool { code.count >= 4 && password.count >= 8 && password == repeatPassword }

    var body: some View {
        SettingsPage(title: "Сменить пароль") {
            IconTile(symbol: "key.fill", color: Tile.red, size: 72)
                .symbolEffect(.bounce, value: sent)
                .padding(.top, 8)
                .appearIn(0)
            if !sent {
                SettingsGroup(footer: tr("Мы отправим код подтверждения на %@. После смены пароля Safir выйдет на всех устройствах — войдите заново с новым паролем.", email)) {
                    ActionSettingsRow(icon: "envelope.fill", color: Tile.orange, title: "Отправить код на email") { send() }
                        .disabled(busy)
                }
                .appearIn(1)
            } else {
                SettingsGroup(header: "Код из письма") {
                    TextField(tr("Код"), text: $code)
                        .keyboardType(.numberPad).textContentType(.oneTimeCode)
                        .padding(.horizontal, 16).frame(minHeight: 50)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                SettingsGroup(header: "Новый пароль", footer: password.isEmpty || password.count >= 8 ? (repeatPassword.isEmpty || password == repeatPassword ? nil : "Пароли не совпадают") : "Минимум 8 символов") {
                    SecureField(tr("Новый пароль"), text: $password)
                        .textContentType(.newPassword)
                        .padding(.horizontal, 16).frame(minHeight: 50)
                    SettingsDivider(inset: 16)
                    SecureField(tr("Повторите пароль"), text: $repeatPassword)
                        .textContentType(.newPassword)
                        .padding(.horizontal, 16).frame(minHeight: 50)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                Button(action: reset) {
                    Group {
                        if busy { ProgressView().tint(.white) } else { Text(tr("Сменить пароль")).fontWeight(.semibold) }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Safir.accent.opacity(valid ? 1 : 0.4)))
                }
                .buttonStyle(PressableStyle())
                .disabled(!valid || busy)
            }
        }
        .animation(Safir.spring, value: sent)
        .alert(tr("Не получилось"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
        .alert(tr("Пароль изменён"), isPresented: $done) {
            Button(tr("Войти заново")) { Task { await session.logout() } }
        } message: {
            Text(tr("Все сеансы завершены. Войдите с новым паролем."))
        }
    }

    private func send() {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await Session.shared.api.send("POST", "auth/forgot-password", body: ForgotPasswordBody(email: email))
                Safir.tap(.medium)
                sent = true
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func reset() {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await Session.shared.api.send("POST", "auth/reset-password",
                                                  body: ResetPasswordBody(email: email, code: code.trimmingCharacters(in: .whitespaces),
                                                                          newPassword: password))
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                done = true
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
