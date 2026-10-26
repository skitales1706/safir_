import PhotosUI
import SwiftUI

/// Telegram's creation flows.
/// Group:   pick members -> name + photo -> create.
/// Channel: name + description + photo -> public (@link) or private -> add subscribers -> create.
enum GroupKind {
    case group, channel
}

struct ChannelDraft {
    var name = ""
    var description = ""
    var photo: UIImage?
    var isPublic = false
    var username = ""
}

// MARK: - Members

struct MemberPickerStep: View {
    let kind: GroupKind
    var draft: ChannelDraft?
    let onOpen: (String) -> Void

    @State private var contacts: [APIUser] = []
    @State private var query = ""
    @State private var remote: [APIUser] = []
    @State private var searching = false
    @State private var selected: [APIUser] = []
    @State private var next = false
    @State private var busy = false
    @State private var error: String?
    @State private var warning: String?
    @State private var createdId: String?

    private static let maxMembers = 200

    var body: some View {
        VStack(spacing: 8) {
            if !selected.isEmpty {
                chips.transition(.move(edge: .top).combined(with: .opacity))
            }
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
                        SelectionMark(selected: isSelected(user))
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
        .animation(Safir.spring, value: selected.map(\.id))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(kind == .group ? "Новая группа" : "Подписчики").font(.headline)
                    Text("\(selected.count) из \(Self.maxMembers)").font(.caption).foregroundStyle(Safir.muted)
                        .contentTransition(.numericText())
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if kind == .group {
                    Button("Далее") { next = true }.disabled(selected.isEmpty)
                } else if busy {
                    ProgressView()
                } else {
                    Button(selected.isEmpty ? "Пропустить" : "Создать") { Task { await createChannel() } }
                }
            }
        }
        .navigationDestination(isPresented: $next) {
            GroupInfoStep(members: selected, onOpen: onOpen)
        }
        .task(id: query) { await search() }
        .onAppear {
            contacts = ChatStore.shared.contacts(excluding: ChatService.shared.myUserId)
        }
        .alert("Канал создан", isPresented: Binding(get: { warning != nil }, set: { if !$0 { warning = nil } })) {
            Button("OK") { if let createdId { onOpen(createdId) } }
        } message: {
            Text(warning ?? "")
        }
    }

    /// Selected people as removable chips (Telegram's token field).
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(selected, id: \.id) { user in
                    Button { toggle(user) } label: {
                        HStack(spacing: 6) {
                            AvatarView(name: user.displayName, path: user.avatarUrl, size: 26)
                            Text(user.fullName?.split(separator: " ").first.map(String.init) ?? user.username)
                                .font(.subheadline.weight(.medium)).foregroundStyle(Safir.text)
                            Image(systemName: "xmark").font(.caption2.bold()).foregroundStyle(Safir.muted)
                        }
                        .padding(.leading, 3).padding(.trailing, 10).frame(height: 32)
                        .background(Capsule().fill(Safir.accent.opacity(0.14)))
                    }
                    .buttonStyle(PressableStyle())
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// Contacts (filtered by the query) followed by server results that aren't contacts.
    private var candidates: [APIUser] {
        let q = query.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
        let local = q.isEmpty ? contacts
            : contacts.filter { $0.displayName.lowercased().contains(q) || $0.username.lowercased().contains(q) }
        let known = Set(local.map { $0.id.lowercased() })
        return local + remote.filter { !known.contains($0.id.lowercased()) }
    }

    private func isSelected(_ user: APIUser) -> Bool {
        selected.contains { $0.id == user.id }
    }

    private func toggle(_ user: APIUser) {
        Safir.tap()
        if let i = selected.firstIndex(where: { $0.id == user.id }) {
            selected.remove(at: i)
        } else if selected.count < Self.maxMembers {
            selected.append(user)
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

    private func createChannel() async {
        guard let draft else { return }
        busy = true
        defer { busy = false }
        do {
            let result = try await GroupCreator.create(
                name: draft.name, members: selected, isChannel: true, description: draft.description,
                username: draft.isPublic ? draft.username : nil, photo: draft.photo)
            if let note = result.warning {
                createdId = result.chatId
                warning = note
            } else {
                onOpen(result.chatId)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Group name and photo

struct GroupInfoStep: View {
    let members: [APIUser]
    let onOpen: (String) -> Void

    @State private var name = ""
    @State private var photo: UIImage?
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    PhotoPickerCircle(photo: $photo)
                    TextField("Название группы", text: $name)
                        .font(.title3)
                        .focused($focused)
                        .submitLabel(.done)
                }
                .padding(.vertical, 6)
            } footer: {
                Text("Сообщения в группе защищены сквозным шифрованием.")
            }
            if let error {
                Section { Text(error).foregroundStyle(Safir.danger) }
            }
            Section {
                ForEach(members, id: \.id) { user in
                    ContactRow(user: user, size: 40)
                }
            } header: {
                SectionCaption(text: countText(members.count, ("участник", "участника", "участников")))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Safir.background.ignoresSafeArea())
        .navigationTitle("Новая группа")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if busy {
                    ProgressView()
                } else {
                    Button("Создать") { Task { await create() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { focused = true }
    }

    private func create() async {
        busy = true
        defer { busy = false }
        do {
            let result = try await GroupCreator.create(
                name: name, members: members, isChannel: false, description: nil, username: nil, photo: photo)
            onOpen(result.chatId)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Channel steps

struct ChannelInfoStep: View {
    let onOpen: (String) -> Void
    @State private var draft = ChannelDraft()
    @State private var next = false
    @FocusState private var focused: Bool

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    PhotoPickerCircle(photo: $draft.photo)
                    TextField("Название канала", text: $draft.name)
                        .font(.title3)
                        .focused($focused)
                }
                .padding(.vertical, 6)
            }
            Section {
                TextField("Описание", text: $draft.description, axis: .vertical)
                    .lineLimit(3...6)
            } footer: {
                Text("Можно добавить описание канала. Каналы — для публикаций большой аудитории; они не используют сквозное шифрование.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Safir.background.ignoresSafeArea())
        .navigationTitle("Новый канал")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Далее") { next = true }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationDestination(isPresented: $next) {
            ChannelTypeStep(draft: draft, onOpen: onOpen)
        }
        .onAppear { focused = true }
    }
}

struct ChannelTypeStep: View {
    @State var draft: ChannelDraft
    let onOpen: (String) -> Void
    @State private var next = false

    private var usernameValid: Bool {
        draft.username.range(of: "^[A-Za-z][A-Za-z0-9_]{4,31}$", options: .regularExpression) != nil
    }

    var body: some View {
        List {
            Section {
                typeRow(isPublic: true, title: "Публичный канал", hint: "Канал можно найти в поиске, подписаться может любой.")
                typeRow(isPublic: false, title: "Частный канал", hint: "Подписаться можно только по ссылке-приглашению.")
            } header: {
                SectionCaption(text: "Тип канала")
            }
            if draft.isPublic {
                Section {
                    HStack(spacing: 2) {
                        Text("@").foregroundStyle(Safir.muted)
                        TextField("ссылка", text: $draft.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    SectionCaption(text: "Публичная ссылка")
                } footer: {
                    Text(draft.username.isEmpty || usernameValid
                         ? "По этой ссылке канал можно найти в поиске. 5–32 символа: латинские буквы, цифры и _."
                         : "Ссылка должна начинаться с буквы: 5–32 символа, латиница, цифры и _.")
                        .foregroundStyle(draft.username.isEmpty || usernameValid ? Safir.muted : Safir.danger)
                }
                .transition(.opacity)
            } else {
                Section {
                    Label("Ссылка-приглашение будет создана автоматически", systemImage: "link")
                        .foregroundStyle(Safir.muted)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Safir.background.ignoresSafeArea())
        .animation(Safir.spring, value: draft.isPublic)
        .navigationTitle("Тип канала")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Далее") { next = true }
                    .disabled(draft.isPublic && !usernameValid)
            }
        }
        .navigationDestination(isPresented: $next) {
            MemberPickerStep(kind: .channel, draft: draft, onOpen: onOpen)
        }
    }

    private func typeRow(isPublic: Bool, title: String, hint: String) -> some View {
        Button {
            Safir.tap()
            draft.isPublic = isPublic
        } label: {
            HStack(alignment: .top, spacing: 12) {
                SelectionMark(selected: draft.isPublic == isPublic)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Safir.text)
                    Text(hint).font(.footnote).foregroundStyle(Safir.muted)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Photo

/// Round "add photo" button; shows the picked picture.
struct PhotoPickerCircle: View {
    @Binding var photo: UIImage?
    @State private var item: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            ZStack {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    Safir.accent.opacity(0.14)
                    Image(systemName: "camera.fill").font(.title2).foregroundStyle(Safir.accent)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onChange(of: item) { _, picked in
            Task {
                if let data = try? await picked?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    withAnimation(Safir.spring) { photo = image }
                }
            }
        }
    }
}

// MARK: - Server

/// POST /groups, then the optional channel description (PATCH /chats/{id}/info), public
/// username (PATCH /channels/{id}/username) and photo (POST /chats/{id}/avatar).
@MainActor
enum GroupCreator {
    struct Result {
        let chatId: String
        /// Set when the chat exists but an optional step failed.
        let warning: String?
    }

    private struct InfoBody: Encodable { let description: String }
    private struct UsernameBody: Encodable { let username: String }

    static func create(name: String, members: [APIUser], isChannel: Bool, description: String?,
                       username: String?, photo: UIImage?) async throws -> Result {
        let api = Session.shared.api
        let me = ChatService.shared.myUserId
        let chat = try await api.post(
            "groups", body: CreateGroupRequest(name: name.trimmingCharacters(in: .whitespaces),
                                               memberIds: members.map { $0.id.lowercased() }, isChannel: isChannel),
            as: APIChat.self)
        ChatStore.shared.upsert(users: members)
        ChatStore.shared.sync(chats: [chat], myUserId: me)
        let id = chat.id.lowercased()

        var problems: [String] = []
        if let text = description?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            do {
                try await api.send("PATCH", "chats/\(id)/info", body: InfoBody(description: text))
            } catch {
                problems.append("описание")
            }
        }
        if let username, !username.isEmpty {
            do {
                try await api.send("PATCH", "channels/\(id)/username", body: UsernameBody(username: username))
            } catch let e as APIError where e.status == 409 {
                problems.append("ссылка @\(username) уже занята")
            } catch {
                problems.append("ссылка @\(username)")
            }
        }
        if let photo, let jpeg = jpeg(photo) {
            do {
                try await uploadAvatar(chatId: id, jpeg: jpeg)
            } catch {
                problems.append("фото")
            }
        }
        await ChatService.shared.refreshChats()
        let warning = problems.isEmpty ? nil
            : "Не удалось сохранить: \(problems.joined(separator: ", ")). Это можно изменить в настройках."
        return Result(chatId: id, warning: warning)
    }

    /// Avatars are small: longest side 640 px, JPEG.
    private static func jpeg(_ image: UIImage) -> Data? {
        let scale = min(1, 640 / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }

    private static func uploadAvatar(chatId: String, jpeg: Data) async throws {
        let api = Session.shared.api
        let boundary = "safir-\(UUID().uuidString)"
        var request = URLRequest(url: api.url("chats/\(chatId)/avatar"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"avatar.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
        body.append(jpeg)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        _ = try await api.perform(request)
    }
}
