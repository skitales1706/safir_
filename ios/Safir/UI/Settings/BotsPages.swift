import Observation
import SwiftUI

/// backend routers/bots.py BotOut. The token comes back only right after create / regenerate.
struct MyBot: Decodable, Identifiable, Equatable {
    let id: String
    let username: String
    var name: String
    var description: String?
    let avatarUrl: String?
    var token: String?
}

private struct BotCreateBody: Encodable {
    let username: String
    let name: String
    let description: String?
}

/// "Мои боты" (Android BotsActivity, Telegram's @BotFather): GET/POST /bots, token, delete.
@MainActor
@Observable
final class BotsStore {
    static let shared = BotsStore()
    private(set) var bots: [MyBot] = []
    private(set) var loaded = false
    var error: String?

    private var api: APIClient { Session.shared.api }

    func load() async {
        guard !DemoData.active else {
            bots = [MyBot(id: "b1", username: "school_news_bot", name: "Новости школы", description: "Расписание и объявления",
                          avatarUrl: nil, token: nil)]
            loaded = true
            return
        }
        do {
            let list = try await api.get("bots", as: [MyBot].self)
            withAnimation(Safir.spring) { bots = list }
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }

    func create(username: String, name: String, description: String) async -> MyBot? {
        do {
            let body = BotCreateBody(username: username, name: name, description: description.isEmpty ? nil : description)
            let bot = try await api.post("bots", body: body, as: MyBot.self)
            withAnimation(Safir.spring) { bots.insert(bot, at: 0) }
            return bot
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func newToken(_ bot: MyBot) async -> String? {
        do {
            let data = try await api.send("POST", "bots/\(bot.id)/token", body: nil)
            return try api.decode(MyBot.self, from: data).token
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func delete(_ bot: MyBot) async -> Bool {
        do {
            try await api.send("DELETE", "bots/\(bot.id)", body: nil)
            withAnimation(Safir.spring) { bots.removeAll { $0.id == bot.id } }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

struct MyBotsPage: View {
    @State private var store = BotsStore.shared
    @State private var creating = false

    var body: some View {
        SettingsPage(title: "Мои боты") {
            VStack(spacing: 8) {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(LinearGradient(colors: [Safir.accent, Safir.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .symbolEffect(.bounce, value: store.bots.count)
                Text(tr("Боты отвечают людям сами: рассылки, расписание, справки. Подключите свой сервер по токену — как в Telegram."))
                    .font(.footnote).foregroundStyle(Safir.muted).multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .padding(.top, 8)
            .appearIn(0)

            SettingsGroup {
                ActionSettingsRow(icon: "plus", color: Tile.green, title: "Создать бота", titleColor: Safir.accent) { creating = true }
            }
            .appearIn(1)

            if !store.bots.isEmpty {
                SettingsGroup(header: "Ваши боты") {
                    ForEach(Array(store.bots.enumerated()), id: \.element.id) { index, bot in
                        if index > 0 { SettingsDivider(inset: 66) }
                        NavigationLink(value: SettingsRoute.bot(bot.id)) {
                            HStack(spacing: 12) {
                                AvatarView(name: bot.name, path: bot.avatarUrl, size: 40)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(bot.name).font(.body).foregroundStyle(Safir.text).lineLimit(1)
                                    Text("@\(bot.username)").font(.footnote).foregroundStyle(Safir.muted)
                                }
                                Spacer()
                                RowValue()
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 60)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .appearIn(2)
            } else if !store.loaded {
                ProgressView().padding(20)
            }
        }
        .task { await store.load() }
        .sheet(isPresented: $creating) { CreateBotSheet() }
        .alert(tr("Не получилось"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.error ?? "") }
    }
}

/// Name, @username ending in "bot", description; the token is shown once after creation.
private struct CreateBotSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = BotsStore.shared
    @State private var name = ""
    @State private var username = ""
    @State private var about = ""
    @State private var busy = false
    @State private var created: MyBot?

    private var usernameValid: Bool {
        username.range(of: "^[A-Za-z][A-Za-z0-9_]{4,31}$", options: .regularExpression) != nil
            && username.lowercased().hasSuffix("bot")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let created {
                        TokenCard(bot: created, token: created.token ?? "")
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    } else {
                        SettingsGroup(header: "Имя") {
                            TextField(tr("Например: Новости школы"), text: $name)
                                .padding(.horizontal, 16).frame(minHeight: 50)
                        }
                        SettingsGroup(header: "Имя пользователя",
                                      footer: "5–32 латинские буквы, цифры и _, в конце — bot. Например: school_news_bot") {
                            HStack(spacing: 2) {
                                Text("@").foregroundStyle(Safir.muted)
                                TextField("school_news_bot", text: $username)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                if !username.isEmpty {
                                    Image(systemName: usernameValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(usernameValid ? Safir.online : Safir.danger)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .padding(.horizontal, 16).frame(minHeight: 50)
                            .animation(Safir.spring, value: usernameValid)
                        }
                        SettingsGroup(header: "Описание") {
                            TextField(tr("Что умеет бот"), text: $about, axis: .vertical)
                                .lineLimit(2...5).padding(16)
                        }
                    }
                }
                .padding(16)
            }
            .background(Safir.background.ignoresSafeArea())
            .navigationTitle(tr(created == nil ? "Новый бот" : "Бот создан"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if created == nil { Button(tr("Отмена")) { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if created != nil {
                        Button(tr("Готово")) { dismiss() }.fontWeight(.semibold)
                    } else if busy {
                        ProgressView()
                    } else {
                        Button(tr("Создать")) { create() }
                            .fontWeight(.semibold)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !usernameValid)
                    }
                }
            }
        }
        .animation(Safir.spring, value: created)
        .interactiveDismissDisabled(created != nil)
    }

    private func create() {
        busy = true
        Task {
            let bot = await store.create(username: username, name: name.trimmingCharacters(in: .whitespaces),
                                         description: about.trimmingCharacters(in: .whitespacesAndNewlines))
            busy = false
            if let bot {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                created = bot
            } else {
                dismiss()
            }
        }
    }
}

/// The bot token, with copy - shown once, like BotFather.
private struct TokenCard: View {
    let bot: MyBot
    let token: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AvatarView(name: bot.name, path: bot.avatarUrl, size: 48)
                VStack(alignment: .leading) {
                    Text(bot.name).font(.headline)
                    Text("@\(bot.username)").font(.footnote).foregroundStyle(Safir.muted)
                }
            }
            Text(tr("Токен для подключения сервера бота. Храните его в секрете: по нему можно управлять ботом."))
                .font(.footnote).foregroundStyle(Safir.muted)
            Text(token)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Safir.pill))
            Button {
                UIPasteboard.general.string = token
                Safir.tap(.medium)
                withAnimation(Safir.spring) { copied = true }
            } label: {
                Label(tr(copied ? "Скопировано" : "Копировать токен"), systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(copied ? Safir.online : Safir.accent))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Safir.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Safir.separator, lineWidth: 0.5))
    }
}

/// One bot: info, a new token, delete.
struct BotDetailPage: View {
    let botId: String
    @Environment(\.dismiss) private var dismiss
    @State private var store = BotsStore.shared
    @State private var token: String?
    @State private var confirmToken = false
    @State private var confirmDelete = false

    private var bot: MyBot? { store.bots.first { $0.id == botId } }

    var body: some View {
        SettingsPage(title: bot?.name ?? "Бот") {
            if let bot {
                VStack(spacing: 8) {
                    AvatarView(name: bot.name, path: bot.avatarUrl, size: 88)
                    Text(bot.name).font(.title3.bold())
                    Text("@\(bot.username)").font(.subheadline).foregroundStyle(Safir.accent)
                    if let about = bot.description, !about.isEmpty {
                        Text(about).font(.footnote).foregroundStyle(Safir.muted).multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 8)
                .appearIn(0)

                if let token {
                    TokenCard(bot: bot, token: token).transition(.scale(scale: 0.9).combined(with: .opacity))
                }

                SettingsGroup(footer: "Новый токен сразу отключает старый — обновите его на сервере бота.") {
                    ActionSettingsRow(icon: "key.fill", color: Tile.orange, title: "Получить новый токен") { confirmToken = true }
                    SettingsDivider()
                    ActionSettingsRow(icon: "trash.fill", color: Safir.danger, title: "Удалить бота", titleColor: Safir.danger) {
                        confirmDelete = true
                    }
                }
                .appearIn(1)
            }
        }
        .animation(Safir.spring, value: token)
        .confirmationDialog(tr("Старый токен перестанет работать."), isPresented: $confirmToken, titleVisibility: .visible) {
            Button(tr("Получить новый токен"), role: .destructive) {
                guard let bot else { return }
                Task { token = await store.newToken(bot) }
            }
        }
        .confirmationDialog(tr("Удалить бота навсегда?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(tr("Удалить"), role: .destructive) {
                guard let bot else { return }
                Task { if await store.delete(bot) { dismiss() } }
            }
        }
    }
}
