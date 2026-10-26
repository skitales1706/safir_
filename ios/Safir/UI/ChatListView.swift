import SwiftUI

struct ChatListView: View {
    @Environment(Session.self) private var session
    private var chats: ChatService { ChatService.shared }
    @State private var items: [ChatItem] = []
    @State private var query = ""
    @State private var tab: ChatTab = .filter(.all)
    @State private var folders = FoldersStore.shared
    @State private var showFolders = false
    /// Non-nil while selecting chats (Android ChatListSelection).
    @State private var selection: Set<String>?
    @State private var confirmBulkDelete = false
    @State private var pinLimitHit = false
    @State private var showSaved = false
    private var pins: ChatPins { ChatPins.shared }
    @State private var router = TabRouter.shared
    @State private var showNewChat = false
    @State private var showAssistant = false
    private var archive: ChatArchive { ChatArchive.shared }
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack(path: $router.chatPath) {
            VStack(spacing: 0) {
                header
                ScrollViewReader { proxy in
                    List {
                        if let error = session.setupError {
                            Section {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Ключи шифрования не зарегистрированы").font(.subheadline.bold())
                                    Text(error).font(.caption).foregroundStyle(Safir.muted)
                                    Button("Повторить") { Task { await session.retrySetup() } }
                                }
                            }
                        }
                        // Archived chats behind one row on top, like Telegram / Android.
                        if !archive.ids.isEmpty && query.isEmpty {
                            let archived = archive.archivedChats()
                            NavigationLink {
                                ArchivedChatsView()
                            } label: {
                                ArchiveEntryRow(count: archived.count, unread: archived.map(\.unreadCount).reduce(0, +))
                            }
                            .listRowBackground(Safir.background)
                            .listRowSeparatorTint(Safir.separator)
                        }
                        ForEach(filtered) { chat in
                            row(chat)
                            .listRowBackground(selection?.contains(chat.id) == true ? Safir.accent.opacity(0.10) : Safir.background)
                            .listRowSeparatorTint(Safir.separator)
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 76 }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    withAnimation(Safir.spring) { ChatStore.shared.deleteChat(chat.id) }
                                    reload()
                                } label: { Label("Удалить", systemImage: "trash") }
                                Button {
                                    ChatStore.shared.setChatFlags(chat.id, isMuted: !chat.isMuted)
                                    reload()
                                } label: {
                                    Label(chat.isMuted ? "Со звуком" : "Без звука", systemImage: chat.isMuted ? "bell" : "bell.slash")
                                }
                                .tint(.orange)
                            }
                            .contextMenu { if selection == nil { rowMenu(chat) } }
                            .swipeActions(edge: .leading) {
                                Button {
                                    togglePin([chat], pin: !pins.isPinned(chat.id))
                                } label: {
                                    Label(pins.isPinned(chat.id) ? "Открепить" : "Закрепить",
                                          systemImage: pins.isPinned(chat.id) ? "pin.slash" : "pin")
                                }
                                .tint(.green)
                                Button {
                                    withAnimation(Safir.spring) { archive.setArchived(chat.id, true) }
                                    reload()
                                } label: { Label("В архив", systemImage: "archivebox") }
                                .tint(.gray)
                                Button {
                                    ChatService.shared.markRead(chat.id)
                                } label: { Label("Прочитано", systemImage: "checkmark.message") }
                                .tint(Safir.accent)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .animation(Safir.spring, value: filtered.map(\.id))
                    .refreshable { await chats.refreshChats() }
                    .tabBarClearance()
                    .onChange(of: router.reselect) { _, _ in
                        if router.tab == .chats, let first = filtered.first {
                            withAnimation(Safir.spring) { proxy.scrollTo(first.id, anchor: .top) }
                        }
                    }
                }
            }
            .background(Safir.background.ignoresSafeArea())
            // Ёвар floats above the Settings tab (Android AiFloatingButton, WhatsApp's Meta AI).
            .overlay(alignment: .bottom) {
                if let selection {
                    ChatSelectionBar(
                        selected: items.filter { selection.contains($0.id) },
                        onRead: { read in
                            if read { for id in selection { ChatService.shared.markRead(id) } }
                            endSelection()
                        },
                        onPin: { pin in
                            togglePin(items.filter { selection.contains($0.id) }, pin: pin)
                            endSelection()
                        },
                        onMute: { mute in
                            for id in selection { ChatStore.shared.setChatFlags(id, isMuted: mute) }
                            endSelection()
                        },
                        onArchive: {
                            withAnimation(Safir.spring) { for id in selection { archive.setArchived(id, true) } }
                            endSelection()
                        },
                        onDelete: { confirmBulkDelete = true }
                    )
                    .padding(.bottom, SafirTabBar.clearance + 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !searchFocused && selection == nil {
                    AiFloatingButton {
                        Safir.tap()
                        showAssistant = true
                    }
                    .accessibilityIdentifier("open-ai")
                    .padding(.trailing, 18)
                    .padding(.bottom, SafirTabBar.clearance + 8)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(Safir.spring, value: searchFocused)
            .animation(Safir.spring, value: selection == nil)
            .confirmationDialog(tr("Удалить выбранные чаты?"), isPresented: $confirmBulkDelete, titleVisibility: .visible) {
                Button(tr("Удалить"), role: .destructive) {
                    withAnimation(Safir.spring) { for id in selection ?? [] { ChatStore.shared.deleteChat(id) } }
                    endSelection()
                }
            }
            .alert(tr("Можно закрепить не больше %d чатов", ChatPins.limit), isPresented: $pinLimitHit) {
                Button("OK", role: .cancel) {}
            }
            .sheet(isPresented: $showFolders) {
                NavigationStack { FoldersPage() }
            }
            .toolbar(.hidden, for: .navigationBar)
            // The bar belongs to the tab's root screen: a pushed chat or page covers it.
            .safirTabBar()
            .navigationDestination(for: String.self) { chatId in
                ChatView(chatId: chatId)
            }
            .navigationDestination(isPresented: $showAssistant) {
                AssistantView()
            }
            .navigationDestination(isPresented: $showSaved) {
                SavedMessagesView()
            }
            .sheet(isPresented: $showNewChat) {
                NewChatView { chatId in
                    showNewChat = false
                    router.openChat(chatId)
                }
            }
            .onAppear {
                reload()
                Task { await folders.load() }
                Notifier.shared.openChat = { id in TabRouter.shared.openChat(id) }
            }
            .onChange(of: chats.revision) { _, _ in reload() }
            .onChange(of: router.pendingAction) { _, action in
                guard let action else { return }
                router.pendingAction = nil
                switch action {
                case "new": showNewChat = true
                case "saved": showSaved = true
                case "search": searchFocused = true
                default: break
                }
            }
        }
    }

    /// Android ChatListTopBar: title (or "Connecting..." with a spinner), round pill buttons,
    /// the search capsule and the filter chips.
    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if let selection {
                    Button(tr("Отмена")) { endSelection() }
                        .font(.body.weight(.semibold)).foregroundStyle(Safir.accent)
                    Spacer()
                    Text(tr("Выбрано: %d", selection.count))
                        .font(.system(size: 20, weight: .semibold)).foregroundStyle(Safir.text)
                        .contentTransition(.numericText())
                    Spacer()
                    Button(tr(selection.count == filtered.count ? "Снять" : "Все")) {
                        Safir.tap()
                        withAnimation(Safir.spring) {
                            self.selection = selection.count == filtered.count ? [] : Set(filtered.map(\.id))
                        }
                    }
                    .font(.body.weight(.semibold)).foregroundStyle(Safir.accent)
                } else if chats.connected {
                    Text("Safir").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(Safir.text)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().tint(Safir.accent)
                        Text("Соединение…").font(.system(size: 20, weight: .semibold)).foregroundStyle(Safir.text)
                    }
                }
                if selection == nil {
                    Spacer()
                    PillCircleButton(systemImage: "bookmark.fill") {
                        Safir.tap()
                        showSaved = true
                    }
                    .accessibilityIdentifier("open-saved")
                    PillCircleButton(systemImage: "checkmark.circle") {
                        Safir.tap()
                        withAnimation(Safir.spring) { selection = [] }
                    }
                    .accessibilityIdentifier("select-chats")
                    PillCircleButton(systemImage: "plus") {
                        Safir.tap()
                        showNewChat = true
                    }
                    .accessibilityIdentifier("new-chat")
                }
            }
            .frame(height: 40)
            .padding(.horizontal, 16)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Safir.muted)
                TextField("Поиск", text: $query).focused($searchFocused)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Safir.muted) }
                }
            }
            .padding(.horizontal, 14).frame(height: 42)
            .background(Capsule().fill(Safir.pill))
            .padding(.horizontal, 16)
            ChatTabChips(selected: $tab, chats: items, folders: folders.folders) { showFolders = true }
        }
        .padding(.top, 6).padding(.bottom, 8)
        .animation(Safir.spring, value: chats.connected)
    }

    private var filtered: [ChatItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let folderIds: Set<String>? = {
            guard case .folder(let id) = tab else { return nil }
            return Set(folders.folders.first { $0.id == id }?.chatIds ?? [])
        }()
        let matchesTab: (ChatItem) -> Bool = { chat in
            switch tab {
            case .filter(let filter): return filter.matches(chat)
            case .folder: return folderIds?.contains(chat.id) == true
            }
        }
        return pins.sorted(items).filter { chat in
            !archive.isArchived(chat.id) && matchesTab(chat) && (q.isEmpty || chat.name.lowercased().contains(q)
                                     || (chat.lastMessage ?? "").lowercased().contains(q))
        }
    }

    private func reload() {
        items = ChatStore.shared.chats()
        // A folder deleted on another device falls back to "Все".
        if case .folder(let id) = tab, folders.loaded, !folders.folders.contains(where: { $0.id == id }) {
            tab = .filter(.all)
        }
    }

    @ViewBuilder
    private func row(_ chat: ChatItem) -> some View {
        let rowView = ChatRow(chat: chat, myUserId: chats.myUserId, typing: chats.isTyping(chat.id),
                              pinned: pins.isPinned(chat.id))
        if let selection {
            Button {
                Safir.tap()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if selection.contains(chat.id) { self.selection?.remove(chat.id) } else { self.selection?.insert(chat.id) }
                }
            } label: {
                HStack(spacing: 10) {
                    SelectionCheck(on: selection.contains(chat.id))
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    rowView
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: chat.id) { rowView }
        }
    }

    @ViewBuilder
    private func rowMenu(_ chat: ChatItem) -> some View {
        Button {
            togglePin([chat], pin: !pins.isPinned(chat.id))
        } label: {
            Label(tr(pins.isPinned(chat.id) ? "Открепить" : "Закрепить"), systemImage: pins.isPinned(chat.id) ? "pin.slash" : "pin")
        }
        Button {
            ChatStore.shared.setChatFlags(chat.id, isMuted: !chat.isMuted)
            reload()
        } label: {
            Label(tr(chat.isMuted ? "Со звуком" : "Без звука"), systemImage: chat.isMuted ? "bell" : "bell.slash")
        }
        Button {
            withAnimation(Safir.spring) { archive.setArchived(chat.id, true) }
            reload()
        } label: { Label(tr("В архив"), systemImage: "archivebox") }
        Button {
            Safir.tap(.medium)
            withAnimation(Safir.spring) { selection = [chat.id] }
        } label: { Label(tr("Выбрать"), systemImage: "checkmark.circle") }
        Button(role: .destructive) {
            withAnimation(Safir.spring) { ChatStore.shared.deleteChat(chat.id) }
            reload()
        } label: { Label(tr("Удалить"), systemImage: "trash") }
    }

    private func togglePin(_ list: [ChatItem], pin: Bool) {
        var hitLimit = false
        withAnimation(Safir.spring) {
            for chat in list where !pins.setPinned(chat.id, pin) { hitLimit = true }
        }
        if hitLimit {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            pinLimitHit = true
        } else {
            Safir.tap(.medium)
        }
        reload()
    }

    private func endSelection() {
        withAnimation(Safir.spring) { selection = nil }
        reload()
    }
}

struct ChatRow: View {
    let chat: ChatItem
    let myUserId: String
    let typing: Bool
    var pinned = false

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(name: chat.name, path: chat.avatarUrl, size: 54)
                .overlay(alignment: .bottomTrailing) {
                    if isOnline {
                        Circle().fill(Safir.online).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Safir.background, lineWidth: 2.5))
                            .transition(.scale)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if chat.isChannel {
                        Image(systemName: "megaphone.fill").font(.caption).foregroundStyle(.secondary)
                    } else if chat.isGroup {
                        Image(systemName: "person.2.fill").font(.caption).foregroundStyle(.secondary)
                    } else if chat.isSecret {
                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(.green)
                    }
                    Text(chat.name).font(.system(.body, weight: .semibold)).foregroundStyle(Safir.text).lineLimit(1)
                    Spacer()
                    if chat.lastSenderId == myUserId && chat.lastMessage != nil {
                        TicksView(status: chat.lastStatus, isDelivered: chat.lastIsRead, isRead: chat.lastIsRead)
                            .foregroundStyle(.secondary)
                    }
                    Text(TimeText.short(chat.lastMessageTime)).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    if typing {
                        HStack(spacing: 4) {
                            Text("печатает").font(.subheadline).foregroundStyle(Safir.accent)
                            TypingDots()
                        }
                    } else {
                        Text(chat.lastMessage ?? " ").font(.subheadline).foregroundStyle(Safir.muted).lineLimit(2)
                    }
                    Spacer()
                    if chat.isMuted {
                        Image(systemName: "bell.slash.fill").font(.caption2).foregroundStyle(Safir.muted)
                    }
                    if pinned && chat.unreadCount == 0 {
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Safir.muted)
                            .rotationEffect(.degrees(45))
                            .transition(.scale.combined(with: .opacity))
                    }
                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(.caption.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .frame(minWidth: 22)
                            .background(Capsule().fill(chat.isMuted ? Safir.muted : Safir.accent))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .animation(Safir.spring, value: chat.unreadCount)
    }

    private var isOnline: Bool {
        guard !chat.isGroup, let partner = chat.partnerId else { return false }
        return ChatStore.shared.user(partner)?.isOnline == true
    }
}
