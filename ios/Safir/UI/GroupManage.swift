import SwiftUI

// Group / channel management opened from the profile (Android GroupEditInfoDialog,
// AddMembersScreen, ChannelLinkCard) and the 1:1 safety number page.

private struct GroupInfoBody: Encodable {
    let name: String
    let description: String
}

private struct AddMembersBody: Encodable { let userIds: [String] }

/// DELETE /chats/{id}/members/{user} takes a (Signal-era empty) body.
struct EmptyBody: Encodable {}

struct ChannelLinkResponse: Decodable {
    let inviteToken: String?
    let username: String?
}

/// Name, description and photo of a group / channel (PATCH /chats/{id}/info, POST /chats/{id}/avatar).
struct GroupEditSheet: View {
    let chat: ChatItem
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var about = ""
    @State private var photo: UIImage?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ZStack {
                        if photo == nil { AvatarView(name: chat.name, path: chat.avatarUrl, size: 64) }
                        PhotoPickerCircle(photo: $photo)
                    }
                    .scaleEffect(1.35)
                    .padding(.vertical, 14)
                    SettingsGroup(footer: chat.isChannel ? "Описание видят все подписчики." : "Описание видят все участники.") {
                        TextField(tr(chat.isChannel ? "Название канала" : "Название группы"), text: $name)
                            .font(.body).padding(.horizontal, 14).frame(minHeight: 50)
                        SettingsDivider(inset: 14)
                        TextField(tr("Описание"), text: $about, axis: .vertical)
                            .lineLimit(2...6).font(.body).padding(14)
                    }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(Safir.danger)
                    }
                }
                .padding(16)
            }
            .background(Safir.background.ignoresSafeArea())
            .navigationTitle(tr(chat.isChannel ? "Канал" : "Группа"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Отмена")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button(tr("Готово")) { Task { await save() } }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .onAppear {
                name = chat.name
                about = chat.description ?? ""
            }
        }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        let api = Session.shared.api
        do {
            try await api.send("PATCH", "chats/\(chat.id)/info",
                               body: GroupInfoBody(name: name.trimmingCharacters(in: .whitespaces),
                                                   description: about.trimmingCharacters(in: .whitespacesAndNewlines)))
            if let photo, let jpeg = Self.jpeg(photo) {
                let boundary = "safir-\(UUID().uuidString)"
                var request = URLRequest(url: api.url("chats/\(chat.id)/avatar"))
                request.httpMethod = "POST"
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                var body = Data()
                body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"avatar.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
                body.append(jpeg)
                body.append(Data("\r\n--\(boundary)--\r\n".utf8))
                request.httpBody = body
                _ = try await api.perform(request)
            }
            await ChatService.shared.refreshChats()
            Safir.tap(.medium)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private static func jpeg(_ image: UIImage) -> Data? {
        let scale = min(1, 640 / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: 0.85)
    }
}

/// Pick people to add to a group / channel (POST /chats/{id}/members with user_ids).
struct AddMembersSheet: View {
    let chat: ChatItem
    @Environment(\.dismiss) private var dismiss
    @State private var contacts: [APIUser] = []
    @State private var query = ""
    @State private var remote: [APIUser] = []
    @State private var searching = false
    @State private var selected: [APIUser] = []
    @State private var busy = false
    @State private var error: String?

    private var existing: Set<String> { Set(ChatStore.shared.members(chat.id).map { $0.lowercased() }) }

    private var candidates: [APIUser] {
        let q = query.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
        let local = q.isEmpty ? contacts
            : contacts.filter { $0.displayName.lowercased().contains(q) || $0.username.lowercased().contains(q) }
        let known = Set(local.map { $0.id.lowercased() })
        let all = local + remote.filter { !known.contains($0.id.lowercased()) }
        return all.filter { !existing.contains($0.id.lowercased()) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                SearchCapsule(text: $query, prompt: "Кого добавить?", busy: searching)
                List {
                    if let error {
                        Text(error).font(.subheadline).foregroundStyle(Safir.danger).listRowBackground(Color.clear)
                    }
                    if candidates.isEmpty && !searching {
                        EmptyStateView(icon: "person.2", title: query.isEmpty ? "Нет контактов" : "Никого не найдено",
                                       subtitle: "Найдите людей по имени или @username")
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    ForEach(candidates, id: \.id) { user in
                        ContactRow(user: user, size: 42) {
                            SelectionMark(selected: selected.contains { $0.id == user.id })
                        }
                        .onTapGesture { toggle(user) }
                        .listRowBackground(Safir.background)
                        .listRowSeparatorTint(Safir.separator)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .padding(.top, 8)
            .background(Safir.background.ignoresSafeArea())
            .navigationTitle(tr(chat.isChannel ? "Добавить подписчиков" : "Добавить участников"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Отмена")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button(tr("Добавить")) { Task { await add() } }.disabled(selected.isEmpty)
                    }
                }
            }
            .task(id: query) { await search() }
            .onAppear { contacts = ChatStore.shared.contacts(excluding: ChatService.shared.myUserId) }
        }
    }

    private func toggle(_ user: APIUser) {
        Safir.tap()
        withAnimation(Safir.spring) {
            if let i = selected.firstIndex(where: { $0.id == user.id }) {
                selected.remove(at: i)
            } else {
                selected.append(user)
            }
        }
    }

    private func search() async {
        guard query.trimmingCharacters(in: .whitespaces).count >= 2 else {
            remote = []
            return
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        remote = (try? await PeopleSearch.find(query)) ?? []
    }

    private func add() async {
        busy = true
        defer { busy = false }
        do {
            ChatStore.shared.upsert(users: selected)
            try await Session.shared.api.send("POST", "chats/\(chat.id)/members",
                                              body: AddMembersBody(userIds: selected.map(\.id)))
            await ChatService.shared.refreshChats()
            Safir.tap(.medium)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Channel link for admins: public @username link or the private invite link, copy / share / revoke.
struct ChannelLinkCard: View {
    let chat: ChatItem
    @Binding var toast: String?
    @State private var link: ChannelLinkResponse?
    @State private var confirmRevoke = false

    private var url: String? {
        let base = Session.shared.api.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/"
        if let username = link?.username, !username.isEmpty { return base + username }
        return link?.inviteToken.map { base + "c/" + $0 }
    }

    var body: some View {
        SettingsGroup(header: "Ссылка") {
            if let url {
                Button {
                    UIPasteboard.general.string = url
                    Safir.tap()
                    toast = tr("Ссылка скопирована")
                } label: {
                    SettingsRow(icon: "link", color: Safir.accent, title: url,
                                subtitle: link?.username != nil ? "Публичная ссылка" : "Пригласительная ссылка") {
                        Image(systemName: "doc.on.doc").foregroundStyle(Safir.accent)
                    }
                }
                .buttonStyle(RowPressStyle())
                SettingsDivider()
                ShareLink(item: url) {
                    SettingsRow(icon: "square.and.arrow.up", color: Safir.accent, title: "Поделиться ссылкой") { EmptyView() }
                }
                .buttonStyle(RowPressStyle())
                if link?.username == nil {
                    SettingsDivider()
                    ActionSettingsRow(icon: "arrow.triangle.2.circlepath", color: Safir.danger, title: "Сбросить ссылку",
                                      titleColor: Safir.danger) { confirmRevoke = true }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 52)
            }
        }
        .task { await load(revoke: false) }
        .confirmationDialog(tr("Старая ссылка перестанет работать."), isPresented: $confirmRevoke, titleVisibility: .visible) {
            Button(tr("Сбросить ссылку"), role: .destructive) { Task { await load(revoke: true) } }
        }
    }

    private func load(revoke: Bool) async {
        let api = Session.shared.api
        do {
            let data = try await api.send(revoke ? "POST" : "GET", "channels/\(chat.id)/invite-link", body: nil)
            let decoded = try api.decode(ChannelLinkResponse.self, from: data)
            withAnimation(Safir.spring) { link = decoded }
        } catch {
            AppLog.write("Channel link failed: \(error.localizedDescription)")
        }
    }
}

/// Signal safety number of a 1:1 chat: compare it in person; confirm after a key change.
struct SafetyNumberPage: View {
    let chat: ChatItem
    @State private var digits: String?
    @State private var ownKeyMismatch = false
    @State private var changePending = false
    @State private var loaded = false

    private var myUserId: String { ChatService.shared.myUserId }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: changePending ? "exclamationmark.shield.fill" : "lock.shield.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(changePending ? Color.orange : Safir.accent)
                    .symbolEffect(.bounce, value: loaded)
                    .padding(.top, 24)
                Text(tr("Сверьте этот номер с собеседником лично. Если он совпадает у обоих — переписку никто не перехватывает."))
                    .font(.subheadline).foregroundStyle(Safir.muted).multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Group {
                    if let digits {
                        Text(verbatim: digits)
                            .font(.system(size: 20, weight: .medium, design: .monospaced))
                            .foregroundStyle(Safir.text).multilineTextAlignment(.center).lineSpacing(6)
                            .textSelection(.enabled)
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity).padding(20)
                .background(Safir.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Safir.separator, lineWidth: 0.5))
                .padding(.horizontal, 16)
                if ownKeyMismatch {
                    Label(tr("Сервер хранит не ваш текущий ключ - возможна подмена"), systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(Safir.danger).padding(.horizontal, 24)
                }
                if changePending {
                    VStack(spacing: 12) {
                        Label(tr("Ключ собеседника изменился или появилось новое устройство. Сверьте номер лично, затем подтвердите."),
                              systemImage: "exclamationmark.shield")
                            .font(.footnote).foregroundStyle(.orange)
                        Button {
                            Task { await acknowledge() }
                        } label: {
                            Text(tr("Я сверил номер - подтвердить")).font(.body.weight(.semibold)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).frame(height: 50)
                                .background(Safir.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(PressableStyle())
                    }
                    .padding(.horizontal, 16)
                    .transition(.opacity)
                }
            }
            .padding(.bottom, 32)
        }
        .background(Safir.background.ignoresSafeArea())
        .navigationTitle(tr("Номер безопасности"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await load() }
    }

    private func load() async {
        guard let partner = chat.partnerId else { return }
        if let result = await SignalService.shared.safetyNumber(myUserId: myUserId, partnerId: partner) {
            digits = result.digits
            ownKeyMismatch = result.ownKeyMismatch
        } else {
            digits = tr("Собеседник ещё не зарегистрировал ключи")
        }
        changePending = (try? await SignalService.shared.isIdentityChangePending(partner)) ?? false
        loaded = true
    }

    private func acknowledge() async {
        guard let partner = chat.partnerId else { return }
        try? await SignalService.shared.acknowledgeIdentityChange(partner)
        Safir.tap(.medium)
        withAnimation(Safir.spring) { changePending = false }
    }
}
