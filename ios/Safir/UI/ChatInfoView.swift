import SwiftUI

private struct ChatPrivacyRequest: Encodable {
    let ttlSeconds: Int?
    let isSecret: Bool?
}

private struct ChatPrivacyResponse: Decodable {
    let ttlSeconds: Int?
    let isSecret: Bool?
}

private struct RoleBody: Encodable { let role: String }

/// What the confirmation dialog at the bottom of the profile is about.
private enum ProfileConfirm: Equatable {
    case clear, block, deleteChat, leave, deleteGroup
    case remove(String)
}

/// Telegram-style profile opened from the chat header (Android UserProfileScreen / GroupProfileScreen):
/// big avatar and status, action tiles, info, shared media, chat settings, members, danger zone.
/// Also shows a group member who has no chat with me yet (`ChatItem.person`).
struct ChatInfoView: View {
    let chat: ChatItem
    var openedFromChat = true
    /// The chat was left or deleted: close the chat screen too.
    var onGone: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var current: ChatItem?
    @State private var shared = SharedContent()
    @State private var ttl = 0
    @State private var secret = false
    @State private var muted = false
    @State private var summary: String?
    @State private var summarizing = false
    @State private var error: String?
    @State private var toast: String?
    @State private var offset: CGFloat = 0
    @State private var confirm: ProfileConfirm?
    @State private var editing = false
    @State private var adding = false
    @State private var showSafety = false
    @State private var member: ChatItem?
    @State private var openChatId: String?
    /// Contact card text being shared (Android ProfileActivity sharedContact).
    @State private var sharingContact: String?
    @State private var theming = false
    @State private var notifying = false
    @State private var notifSummary = ""

    private var c: ChatItem { current ?? chat }
    private var service: ChatService { ChatService.shared }
    private var myUserId: String { service.myUserId }
    private var api: APIClient { Session.shared.api }
    private var apiTarget: String { c.isGroup ? c.id : (c.partnerId ?? "") }
    private var stored: Bool { current != nil }
    private var isAdmin: Bool { c.myRole == "admin" || c.myRole == "owner" }
    private var isOwner: Bool { c.myRole == "owner" }
    private var partner: APIUser? { c.partnerId.flatMap { ChatStore.shared.user($0) } }

    private static let ttlOptions: [(seconds: Int, title: String)] = [
        (0, "Выкл."), (30, "30 секунд"), (300, "5 минут"), (3600, "1 час"), (86_400, "1 день"), (604_800, "1 неделя"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                GeometryReader { g in
                    Color.clear.preference(key: ProfileScrollKey.self, value: g.frame(in: .named("profile")).minY)
                }
                .frame(height: 0)
                ProfileHeader(name: c.name, path: c.avatarUrl, status: status, statusAccent: statusAccent,
                              online: !c.isGroup && partner?.isOnline == true, premium: partner?.isPremium == true,
                              pull: offset)
                    .padding(.bottom, -18)
                tiles.appearIn(1)
                infoGroup.appearIn(2)
                if c.isChannel && isAdmin { ChannelLinkCard(chat: c, toast: $toast).appearIn(3) }
                if !shared.isEmpty { SharedMediaSection(content: shared).appearIn(4) }
                if stored { settingsGroup.appearIn(5) }
                if c.isGroup && (!c.isChannel || isAdmin) { membersGroup.appearIn(6) }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(Safir.danger).padding(.horizontal, 16)
                }
                if stored { dangerGroup.appearIn(7) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .coordinateSpace(name: "profile")
        .onPreferenceChange(ProfileScrollKey.self) { offset = $0 }
        .background(Safir.background.ignoresSafeArea())
        .overlay(alignment: .top) { topBar }
        .toolbar(.hidden, for: .navigationBar)
        .settingsToast($toast)
        .animation(Safir.spring, value: muted)
        .navigationDestination(item: $member) { ChatInfoView(chat: $0, openedFromChat: false) }
        .navigationDestination(item: $openChatId) { ChatView(chatId: $0) }
        .navigationDestination(isPresented: $showSafety) { SafetyNumberPage(chat: c) }
        .sheet(isPresented: $editing) { GroupEditSheet(chat: c) }
        .sheet(isPresented: $adding) { AddMembersSheet(chat: c) }
        .sheet(isPresented: $theming) { ChatThemeSheet(chatId: c.id) }
        .navigationDestination(isPresented: $notifying) { ChatNotificationsPage(chat: c, muted: $muted) }
        .sheet(isPresented: Binding(get: { sharingContact != nil }, set: { if !$0 { sharingContact = nil } })) {
            ChatPickerSheet(title: "Поделиться контактом") { chatId in
                if let text = sharingContact { service.sendText(text, chatId: chatId) }
                toast = tr("Контакт отправлен")
            }
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible, presenting: confirm) { what in
            Button(confirmButton(what), role: .destructive) { Task { await perform(what) } }
        }
        .alert(tr("Краткое содержание"), isPresented: Binding(get: { summary != nil }, set: { if !$0 { summary = nil } })) {
            Button(tr("Копировать")) { UIPasteboard.general.string = summary }
            Button("OK", role: .cancel) {}
        } message: {
            Text(summary ?? "")
        }
        .onAppear {
            current = ChatStore.shared.chat(chat.id)
            ttl = c.ttlSeconds
            secret = c.isSecret
            muted = c.isMuted
            shared = SharedContent(chatId: chat.id)
            notifSummary = tr(NotificationPrefs.summary(chat.id, muted: muted))
        }
        .onChange(of: muted) { _, value in notifSummary = tr(NotificationPrefs.summary(chat.id, muted: value)) }
        .onChange(of: notifying) { _, open in
            if !open { notifSummary = tr(NotificationPrefs.summary(chat.id, muted: muted)) }
        }
        .onChange(of: service.revision) { _, _ in
            if let fresh = ChatStore.shared.chat(chat.id) { current = fresh }
        }
    }

    // MARK: Header

    private var status: String {
        _ = service.revision
        if c.isChannel { return "\(c.subscribersCount) " + tr("подписчиков") }
        if c.isGroup {
            let ids = ChatStore.shared.members(c.id)
            let online = ids.filter { ChatStore.shared.user($0)?.isOnline == true }.count
            return "\(ids.count) " + tr("участников") + (online > 1 ? ", \(online) " + tr("в сети") : "")
        }
        if c.isBot { return tr("бот") }
        if service.isTyping(c.id) { return tr("печатает…") }
        guard let partner else { return "" }
        return partner.isOnline == true ? tr("в сети") : tr(TimeText.lastSeen(partner.lastSeen))
    }

    private var statusAccent: Bool { !c.isGroup && (partner?.isOnline == true || service.isTyping(c.id)) }

    /// Floating back / edit circles; the name settles into a glass capsule once the header scrolls away.
    private var topBar: some View {
        HStack(spacing: 8) {
            GlassCircle(action: { dismiss() }) { Image(systemName: "chevron.left") }
                .accessibilityIdentifier("profile-back")
            Spacer()
            if offset < -150 {
                Text(verbatim: c.name).font(.headline).foregroundStyle(Safir.text).lineLimit(1)
                    .padding(.horizontal, 18).frame(height: 44).glassCapsule()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
            if c.isGroup && isAdmin {
                GlassCircle(action: { editing = true }) { Image(systemName: "pencil") }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 10).padding(.top, 4)
        .animation(Safir.spring, value: offset < -150)
    }

    @ViewBuilder
    private var tiles: some View {
        HStack(spacing: 8) {
            if !c.isGroup {
                ProfileActionTile(icon: "message.fill", title: "Сообщение") { openMessages() }
            }
            if stored {
                ProfileActionTile(icon: muted ? "bell.slash.fill" : "bell.fill", title: muted ? "Включить" : "Без звука") {
                    muted.toggle()
                    ChatStore.shared.setChatFlags(c.id, isMuted: muted)
                }
            }
            if !c.isCloud {
                ProfileActionTile(icon: "phone.fill", title: "Звонок") { CallService.shared.start(chat: c, video: false) }
                ProfileActionTile(icon: "video.fill", title: "Видео") { startVideo() }
            }
            if c.isGroup && isAdmin {
                ProfileActionTile(icon: "person.badge.plus", title: "Добавить") { adding = true }
            }
            if c.isGroup && !isOwner {
                ProfileActionTile(icon: "rectangle.portrait.and.arrow.right", title: "Выйти", danger: true) { confirm = .leave }
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var infoGroup: some View {
        SettingsGroup {
            if c.isGroup {
                if let d = c.description, !d.isEmpty {
                    infoText(d, label: "Описание")
                    SettingsDivider()
                } else if isAdmin {
                    ActionSettingsRow(icon: "text.alignleft", color: Safir.accent, title: "Добавить описание") { editing = true }
                    SettingsDivider()
                }
                SettingsRow(icon: c.isChannel ? "megaphone.fill" : "person.3.fill", color: Safir.accent,
                            title: c.isChannel ? "Канал" : "Группа",
                            subtitle: c.isChannel ? "Пишут владелец и админы, подписчики читают"
                                                  : "Все участники могут писать") { EmptyView() }
                SettingsDivider()
                SettingsRow(icon: c.isChannel ? "cloud.fill" : "lock.fill", color: Safir.accent,
                            title: c.isChannel ? "Облачный канал" : "Сквозное шифрование",
                            subtitle: c.isChannel ? "Посты хранятся на сервере, как в Telegram"
                                                  : "Сообщения читают только участники") { EmptyView() }
            } else {
                if let username = partner?.username ?? c.username {
                    Button {
                        UIPasteboard.general.string = "@" + username
                        Safir.tap()
                        toast = tr("Имя пользователя скопировано")
                    } label: {
                        SettingsRow(icon: "at", color: Safir.accent, title: "@" + username, subtitle: "Имя пользователя") {
                            Image(systemName: "doc.on.doc").font(.footnote).foregroundStyle(Safir.accent)
                        }
                    }
                    .buttonStyle(RowPressStyle())
                }
                if let bio = partner?.bio, !bio.isEmpty {
                    SettingsDivider()
                    infoText(bio, label: "О себе")
                }
                if let partner, !c.isBot {
                    SettingsDivider()
                    ActionSettingsRow(icon: "person.crop.circle.badge.plus", color: Safir.accent,
                                      title: "Поделиться контактом", chevron: true) {
                        sharingContact = SharedContact.text(userId: partner.id, name: partner.fullName ?? c.name,
                                                            username: partner.username)
                    }
                }
                if !c.isCloud {
                    SettingsDivider()
                    SettingsRow(icon: "lock.fill", color: Safir.accent, title: "Сквозное шифрование",
                                subtitle: "Signal Protocol: сообщения и звонки видите только вы двое") { EmptyView() }
                }
            }
        }
    }

    private func infoText(_ text: String, label: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(symbol: "info", color: Safir.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: text).font(.body).foregroundStyle(Safir.text).fixedSize(horizontal: false, vertical: true)
                Text(tr(label)).font(.footnote).foregroundStyle(Safir.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    @ViewBuilder
    private var settingsGroup: some View {
        SettingsGroup(header: "Настройки чата") {
            if !c.isCloud {
                SettingsRow(icon: "timer", color: Safir.accent, title: "Исчезающие сообщения") {
                    Menu {
                        Picker("", selection: $ttl) {
                            ForEach(Self.ttlOptions, id: \.seconds) { Text(tr($0.title)).tag($0.seconds) }
                        }
                    } label: {
                        RowValue(value: tr(Self.ttlOptions.first { $0.seconds == ttl }?.title ?? "Выкл."))
                    }
                }
                .onChange(of: ttl) { _, value in
                    if value != c.ttlSeconds { Task { await setTTL(value) } }
                }
                SettingsDivider()
                // Secret chat (backend set_chat_privacy, Android SecretChat.kt): the screen is hidden
                // while recorded and in the app switcher; screenshots are reported.
                SwitchRow(icon: "eye.slash.fill", color: Safir.accent, title: "Секретный чат",
                          subtitle: "Скрыт при записи экрана и в переключателе приложений", isOn: $secret)
                    .onChange(of: secret) { _, value in
                        if value != c.isSecret { Task { await setSecret(value) } }
                    }
                if !c.isGroup {
                    SettingsDivider()
                    ActionSettingsRow(icon: "checkmark.shield.fill", color: Safir.accent, title: "Номер безопасности",
                                      chevron: true) { showSafety = true }
                }
                SettingsDivider()
            }
            ActionSettingsRow(icon: "paintbrush.fill", color: Safir.accent, title: "Обои чата",
                              value: ChatThemes.shared.wallpapers[c.id] == nil ? tr("По умолчанию") : nil,
                              chevron: true) { theming = true }
            SettingsDivider()
            ActionSettingsRow(icon: "bell.badge.fill", color: Safir.accent, title: "Уведомления",
                              value: notifSummary, chevron: true) {
                notifying = true
            }
            SettingsDivider()
            // Ёвар reads the last messages on request (AiTools, backend /ai/summarize).
            ActionSettingsRow(icon: "text.badge.star", color: Safir.accent, title: "Краткое содержание чата",
                              value: summarizing ? "…" : nil) {
                guard !summarizing else { return }
                summarizing = true
                Task {
                    summary = await AiTools.summarize(chatId: c.id) ?? tr("Краткое содержание сейчас недоступно")
                    summarizing = false
                }
            }
        }
    }

    private var membersGroup: some View {
        let roles = ChatStore.shared.memberRoles(c.id).sorted { a, b in
            let rank = ["owner": 0, "admin": 1]
            let ra = rank[a.role] ?? 2, rb = rank[b.role] ?? 2
            if ra != rb { return ra < rb }
            let oa = ChatStore.shared.user(a.userId)?.isOnline == true, ob = ChatStore.shared.user(b.userId)?.isOnline == true
            if oa != ob { return oa }
            return ChatStore.shared.displayName(a.userId) < ChatStore.shared.displayName(b.userId)
        }
        return SettingsGroup(header: "\(roles.count) " + tr(c.isChannel ? "подписчиков" : "участников")) {
            if isAdmin {
                ActionSettingsRow(icon: "person.badge.plus", color: Safir.accent,
                                  title: c.isChannel ? "Добавить подписчиков" : "Добавить участников",
                                  titleColor: Safir.accent) { adding = true }
                if !roles.isEmpty { SettingsDivider() }
            }
            ForEach(Array(roles.enumerated()), id: \.element.userId) { index, m in
                if index > 0 { SettingsDivider(inset: 68) }
                memberButton(m.userId, role: m.role)
            }
        }
    }

    private func memberButton(_ userId: String, role: String) -> some View {
        let isMe = userId.lowercased() == myUserId.lowercased()
        return Button { openMember(userId) } label: {
            MemberRow(userId: userId, role: role, isMe: isMe)
        }
        .buttonStyle(RowPressStyle())
        .disabled(isMe)
        .contextMenu {
            if !isMe && role != "owner" {
                if isOwner {
                    Button(tr(role == "admin" ? "Снять админа" : "Сделать админом"),
                           systemImage: role == "admin" ? "person.fill.xmark" : "person.badge.shield.checkmark") {
                        Task { await setRole(userId, admin: role != "admin") }
                    }
                }
                if isAdmin {
                    Button(tr("Удалить из группы"), systemImage: "person.fill.badge.minus", role: .destructive) {
                        confirm = .remove(userId)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var dangerGroup: some View {
        SettingsGroup {
            if c.isGroup {
                if isOwner {
                    ActionSettingsRow(icon: "trash.fill", color: Safir.danger,
                                      title: c.isChannel ? "Удалить канал" : "Удалить группу",
                                      titleColor: Safir.danger) { confirm = .deleteGroup }
                } else {
                    ActionSettingsRow(icon: "rectangle.portrait.and.arrow.right", color: Safir.danger,
                                      title: c.isChannel ? "Отписаться" : "Выйти из группы",
                                      titleColor: Safir.danger) { confirm = .leave }
                }
            } else {
                ActionSettingsRow(icon: "eraser.fill", color: Safir.danger, title: "Очистить историю",
                                  titleColor: Safir.danger) { confirm = .clear }
                // POST /users/{id}/block; undone in Settings -> Privacy -> Blocked.
                if c.partnerId != nil && !c.isBot {
                    SettingsDivider()
                    ActionSettingsRow(icon: "hand.raised.fill", color: Safir.danger, title: "Заблокировать",
                                      titleColor: Safir.danger) { confirm = .block }
                }
                SettingsDivider()
                ActionSettingsRow(icon: "trash.fill", color: Safir.danger, title: "Удалить чат",
                                  titleColor: Safir.danger) { confirm = .deleteChat }
            }
        }
    }

    // MARK: Navigation

    private func openMessages() {
        if openedFromChat {
            dismiss()
        } else if let user = partner {
            openChatId = ChatStore.shared.ensureDirectChat(myUserId: myUserId, partner: user)
        }
    }

    private func openMember(_ userId: String) {
        guard let user = ChatStore.shared.user(userId) else { return }
        Safir.tap()
        member = ChatStore.shared.chat(ChatIds.direct(myUserId, userId)) ?? ChatItem.person(user, myUserId: myUserId)
    }

    /// Groups: a meeting on the organisation's SFU when the server has one, else the peer-to-peer call.
    private func startVideo() {
        guard c.isGroup else {
            CallService.shared.start(chat: c, video: true)
            return
        }
        let target = c
        Task {
            switch await MeetingService.shared.join(chat: target) {
            case .joined: break
            case .unavailable: CallService.shared.start(chat: target, video: true)
            case .failed: error = tr("Не удалось подключиться к видеовстрече")
            }
        }
    }

    // MARK: Confirmations

    private var confirmTitle: String {
        switch confirm {
        case .clear: return tr("Все сообщения будут удалены с этого телефона.")
        case .block: return tr("Собеседник не сможет писать и звонить вам.")
        case .deleteChat: return tr("Чат будет удалён.")
        case .leave: return tr(c.isChannel ? "Вы отпишетесь от канала." : "Вы выйдете из группы, чат исчезнет из списка.")
        case .deleteGroup: return tr("Чат будет удалён для всех участников со всеми сообщениями.")
        case .remove(let id): return ChatStore.shared.displayName(id)
        case nil: return ""
        }
    }

    private func confirmButton(_ what: ProfileConfirm) -> String {
        switch what {
        case .clear: return tr("Очистить историю")
        case .block: return tr("Заблокировать")
        case .deleteChat: return tr("Удалить чат")
        case .leave: return tr(c.isChannel ? "Отписаться" : "Выйти из группы")
        case .deleteGroup: return tr(c.isChannel ? "Удалить канал" : "Удалить группу")
        case .remove: return tr("Удалить из группы")
        }
    }

    private func perform(_ what: ProfileConfirm) async {
        do {
            switch what {
            case .clear:
                ChatStore.shared.clearMessages(c.id)
                withAnimation(Safir.spring) { shared = SharedContent() }
                toast = tr("История очищена")
            case .block:
                guard let partner = c.partnerId else { return }
                try await api.send("POST", "users/\(partner)/block", body: nil)
                Safir.tap(.medium)
                toast = tr("Заблокирован")
            case .deleteChat:
                ChatStore.shared.deleteChat(c.id)
                _ = try? await api.send("DELETE", "chats/\(apiTarget)", body: nil)
                onGone()
            case .leave:
                try await api.send("POST", "chats/\(c.id)/leave", body: nil)
                ChatStore.shared.deleteChat(c.id)
                onGone()
            case .deleteGroup:
                try await api.send("DELETE", "groups/\(c.id)", body: nil)
                ChatStore.shared.deleteChat(c.id)
                onGone()
            case .remove(let userId):
                try await api.send("DELETE", "chats/\(c.id)/members/\(userId)", body: EmptyBody())
                await service.refreshChats()
                Safir.tap(.medium)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Server

    private func setRole(_ userId: String, admin: Bool) async {
        do {
            try await api.send("POST", "chats/\(c.id)/members/\(userId)/role", body: RoleBody(role: admin ? "admin" : "member"))
            await service.refreshChats()
            Safir.tap(.medium)
            toast = tr(admin ? "Назначен админом" : "Больше не админ")
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func setTTL(_ value: Int) async {
        do {
            let data = try await api.send("PATCH", "chats/\(apiTarget)/privacy",
                                          body: ChatPrivacyRequest(ttlSeconds: value, isSecret: nil))
            let response = try api.decode(ChatPrivacyResponse.self, from: data)
            ChatStore.shared.setChatFlags(c.id, ttlSeconds: response.ttlSeconds ?? value, isSecret: response.isSecret)
        } catch {
            self.error = error.localizedDescription
            ttl = c.ttlSeconds
        }
    }

    private func setSecret(_ value: Bool) async {
        do {
            let data = try await api.send("PATCH", "chats/\(apiTarget)/privacy",
                                          body: ChatPrivacyRequest(ttlSeconds: nil, isSecret: value))
            let response = try api.decode(ChatPrivacyResponse.self, from: data)
            ChatStore.shared.setChatFlags(c.id, ttlSeconds: response.ttlSeconds ?? c.ttlSeconds, isSecret: response.isSecret ?? value)
        } catch {
            self.error = error.localizedDescription
            secret = c.isSecret
        }
    }
}
