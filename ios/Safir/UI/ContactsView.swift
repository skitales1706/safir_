import SwiftUI

/// Screens opened from Contacts and from "New message" (Telegram's action rows).
enum PeopleSheet: String, Identifiable, Hashable {
    case addContact, newGroup, newChannel, findChannels
    var id: String { rawValue }
}

/// The screen for a PeopleSheet; the caller provides the NavigationStack.
struct PeopleSheetContent: View {
    let sheet: PeopleSheet
    let onOpen: (String) -> Void

    var body: some View {
        switch sheet {
        case .addContact: AddContactView(onOpen: onOpen)
        case .newGroup: MemberPickerStep(kind: .group, onOpen: onOpen)
        case .newChannel: ChannelInfoStep(onOpen: onOpen)
        case .findChannels: ChannelSearchView(onOpen: onOpen)
        }
    }
}

/// Contacts tab (Telegram): only contacts. "Invite friends" above the search, "+" (top right)
/// opens "New contact". Groups / channels are created from the chat list's "+".
struct ContactsView: View {
    @Environment(Session.self) private var session
    @State private var contacts: [APIUser] = []
    @State private var query = ""
    @State private var addContact = false
    @State private var showInvite = false
    private var router: TabRouter { TabRouter.shared }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    TabHeader(title: "Контакты", subtitle: contacts.isEmpty ? nil : countText(contacts.count)) {
                        PillCircleButton(systemImage: "person.badge.plus") {
                            Safir.tap()
                            addContact = true
                        }
                        .accessibilityIdentifier("add-contact")
                    }
                    Button {
                        Safir.tap()
                        showInvite = true
                    } label: {
                        ActionRowLabel(icon: "qrcode", title: "Пригласить друзей")
                            .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                    SearchCapsule(text: $query, prompt: "Поиск контактов")
                }
                .padding(.top, 6).padding(.bottom, 8)
                ScrollViewReader { proxy in
                    list
                        .onChange(of: router.reselect) { _, _ in
                            if router.tab == .contacts, let first = shown.first {
                                withAnimation(Safir.spring) { proxy.scrollTo(first.id, anchor: .top) }
                            }
                        }
                }
            }
            .background(Safir.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            // The bar belongs to the tab's root screen: a pushed chat or page covers it.
            .safirTabBar()
            .onAppear(perform: reload)
            .onChange(of: ChatService.shared.revision) { _, _ in reload() }
            .sheet(isPresented: $showInvite) { InviteSheet(text: inviteText, link: inviteLink) }
            .sheet(isPresented: $addContact, onDismiss: reload) {
                NavigationStack {
                    AddContactView { chatId in
                        addContact = false
                        router.openChat(chatId)
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { addContact = false } }
                    }
                }
            }
        }
    }

    private var list: some View {
        List {
            if shown.isEmpty {
                EmptyStateView(icon: query.isEmpty ? "person.2" : "magnifyingglass",
                               title: query.isEmpty ? "Пока нет контактов" : "Никого не найдено",
                               subtitle: query.isEmpty
                                   ? "Нажмите + вверху и найдите человека по имени или @username"
                                   : "Проверьте имя или @username")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(shown, id: \.id) { user in
                row(user)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(Safir.spring, value: shown.map(\.id))
        .refreshable {
            await ChatService.shared.refreshChats()
            reload()
        }
        .tabBarClearance()
    }

    private func row(_ user: APIUser) -> some View {
        Button {
            Safir.tap()
            router.openChat(with: user)
        } label: {
            ContactRow(user: user)
        }
        .buttonStyle(.plain)
        .id(user.id)
        .listRowBackground(Safir.background)
        .listRowSeparatorTint(Safir.separator)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 74 }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { router.call(user, video: true) } label: { Label("Видео", systemImage: "video.fill") }
                .tint(AppTab.calls.color)
            Button { router.call(user, video: false) } label: { Label("Звонок", systemImage: "phone.fill") }
                .tint(Safir.accent)
        }
        .contextMenu {
            Button { router.openChat(with: user) } label: { Label("Написать", systemImage: "bubble.left") }
            Button { router.call(user, video: false) } label: { Label("Аудиозвонок", systemImage: "phone") }
            Button { router.call(user, video: true) } label: { Label("Видеозвонок", systemImage: "video") }
        }
    }

    private var shown: [APIUser] {
        let q = query.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
        guard !q.isEmpty else { return contacts }
        return contacts.filter { $0.displayName.lowercased().contains(q) || $0.username.lowercased().contains(q) }
    }

    /// Same text as Android's InviteSheet: the web client on this server works with no install.
    private var inviteLink: String {
        var base = Session.shared.api.baseURL.absoluteString
        if base.hasSuffix("/") { base.removeLast() }
        return base + "/app/"
    }

    private var inviteText: String {
        var text = "Привет! Я в Safir — защищённом мессенджере со сквозным шифрованием."
        if case .loggedIn(let me) = session.state, !me.username.isEmpty {
            text += "\nНайдите меня: @\(me.username)"
        }
        return text + "\n" + inviteLink
    }

    private func reload() {
        contacts = ChatStore.shared.contacts(excluding: ChatService.shared.myUserId)
    }
}

/// "5 контактов" with Russian plural forms.
func countText(_ n: Int, _ forms: (String, String, String) = ("контакт", "контакта", "контактов")) -> String {
    let mod10 = n % 10, mod100 = n % 100
    let word: String
    if mod10 == 1 && mod100 != 11 {
        word = forms.0
    } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
        word = forms.1
    } else {
        word = forms.2
    }
    return "\(n) \(word)"
}

/// "New contact" (Android NewContactDialog): type a name or @username, matching people appear
/// live; "Добавить" saves the person to Contacts, tapping the row opens the chat.
struct AddContactView: View {
    let onOpen: (String) -> Void
    @State private var text = ""
    @State private var results: [APIUser] = []
    @State private var loading = false
    @State private var failed = false
    @State private var added: Set<String> = []
    @FocusState private var focused: Bool

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(Safir.brandGradient))
                    Text("Найдите человека по имени или @username").font(.subheadline)
                        .foregroundStyle(Safir.muted).multilineTextAlignment(.center)
                    HStack(spacing: 8) {
                        Text("@").font(.headline).foregroundStyle(Safir.accent)
                        TextField("username или имя", text: $text)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused)
                        if loading { ProgressView().controlSize(.small) }
                    }
                    .padding(.horizontal, 16).frame(height: 48)
                    .background(Capsule().fill(Safir.pill))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            Section {
                if failed {
                    Label("Нет соединения. Попробуйте позже", systemImage: "wifi.slash").foregroundStyle(Safir.muted)
                } else if text.count >= 2 && results.isEmpty && !loading {
                    Label("Никого не найдено", systemImage: "person.fill.questionmark").foregroundStyle(Safir.muted)
                }
                ForEach(results, id: \.id) { user in
                    ContactRow(user: user) {
                        if added.contains(user.id) {
                            Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Safir.online)
                                .transition(.scale)
                        } else {
                            // Plain style: a bordered button would take taps for the whole List row.
                            Button { add(user) } label: {
                                Text("Добавить").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    .padding(.horizontal, 14).frame(height: 32)
                                    .background(Capsule().fill(Safir.accent))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .onTapGesture {
                        add(user)
                        onOpen(ChatStore.shared.ensureDirectChat(myUserId: ChatService.shared.myUserId, partner: user))
                    }
                    .listRowBackground(Safir.background)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Safir.background.ignoresSafeArea())
        .navigationTitle("Новый контакт")
        .navigationBarTitleDisplayMode(.inline)
        .animation(Safir.spring, value: results.map(\.id))
        .task(id: text) { await search() }
        .onAppear { focused = true }
    }

    private func add(_ user: APIUser) {
        Safir.tap(.medium)
        ChatStore.shared.upsert(users: [user])
        withAnimation(Safir.spring) { _ = added.insert(user.id) }
    }

    private func search() async {
        guard text.trimmingCharacters(in: .whitespaces).count >= 2 else {
            results = []
            failed = false
            return
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled else { return }
        loading = true
        defer { loading = false }
        do {
            results = Array(try await PeopleSearch.find(text).prefix(20))
            failed = false
        } catch {
            failed = true
        }
    }
}
