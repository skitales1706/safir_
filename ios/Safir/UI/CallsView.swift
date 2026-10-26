import SwiftUI

/// Calls tab (Telegram): All / Missed, one row per call with direction, type and duration.
/// Tap calls back, (i) opens the chat, swipe deletes. The log lives on this device only.
struct CallsView: View {
    @State private var entries: [CallLogEntry] = []
    @State private var users: [String: APIUser] = [:]
    @State private var missedOnly = false
    @State private var confirmClear = false
    @State private var newCall = false
    private var log: CallLog { CallLog.shared }
    private var router: TabRouter { TabRouter.shared }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    TabHeader(title: "Звонки") {
                        if !entries.isEmpty {
                            PillCircleButton(systemImage: "trash", tint: Safir.danger) { confirmClear = true }
                                .transition(.scale.combined(with: .opacity))
                        }
                        PillCircleButton(systemImage: "phone.badge.plus") {
                            Safir.tap()
                            newCall = true
                        }
                        .accessibilityIdentifier("new-call")
                    }
                    CallsSegment(missedOnly: $missedOnly)
                }
                .padding(.top, 6).padding(.bottom, 8)
                List {
                    if shown.isEmpty {
                        EmptyStateView(icon: missedOnly ? "phone.arrow.down.left" : "phone",
                                       title: missedOnly ? "Нет пропущенных звонков" : "Пока нет звонков",
                                       subtitle: "Здесь появятся ваши аудио- и видеозвонки")
                            .id(missedOnly)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    ForEach(shown) { entry in
                        row(entry)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .animation(Safir.spring, value: shown.map(\.id))
                .tabBarClearance()
            }
            .background(Safir.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            // The bar belongs to the tab's root screen: a pushed chat or page covers it.
            .safirTabBar()
            .animation(Safir.spring, value: entries.isEmpty)
            .onAppear {
                reload()
                if router.tab == .calls { log.markSeen() }
            }
            .onChange(of: log.revision) { _, _ in reload() }
            .onChange(of: router.tab) { _, tab in
                if tab == .calls { log.markSeen() }
            }
            .confirmationDialog("Очистить историю звонков?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Очистить", role: .destructive) { withAnimation(Safir.spring) { log.clear() } }
            } message: {
                Text("Записи удалятся только с этого устройства.")
            }
            .sheet(isPresented: $newCall) {
                NavigationStack {
                    NewCallView { user, video in
                        newCall = false
                        router.call(user, video: video)
                    }
                }
            }
        }
    }

    private var shown: [CallLogEntry] {
        missedOnly ? entries.filter(\.isMissed) : entries
    }

    private func row(_ entry: CallLogEntry) -> some View {
        let user = users[entry.peerId]
        let name = user?.displayName ?? ChatStore.shared.displayName(entry.peerId)
        let detail = entry.durationText.isEmpty ? entry.title : "\(entry.title), \(entry.durationText)"
        return HStack(spacing: 12) {
            AvatarView(name: name, path: user?.avatarUrl, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body.weight(.semibold))
                    .foregroundStyle(entry.isMissed ? Safir.danger : Safir.text).lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: entry.outgoing ? "arrow.up.right" : "arrow.down.left")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(entry.isMissed ? Safir.danger : AppTab.calls.color)
                    if entry.video {
                        Image(systemName: "video.fill").font(.caption2).foregroundStyle(Safir.muted)
                    }
                    Text(detail).font(.subheadline).foregroundStyle(Safir.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Text(TimeText.short(entry.timestamp)).font(.subheadline).foregroundStyle(Safir.muted)
            Button {
                router.openChat(entry.chatId)
            } label: {
                Image(systemName: "info.circle").font(.title3).foregroundStyle(Safir.accent)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { callBack(entry, video: entry.video) }
        .listRowBackground(Safir.background)
        .listRowSeparatorTint(Safir.separator)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 74 }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                withAnimation(Safir.spring) { log.delete(entry.id) }
            } label: { Label("Удалить", systemImage: "trash") }
        }
        .swipeActions(edge: .leading) {
            Button { router.openChat(entry.chatId) } label: { Label("Написать", systemImage: "bubble.left.fill") }
                .tint(Safir.accent)
        }
        .contextMenu {
            Button { callBack(entry, video: false) } label: { Label("Аудиозвонок", systemImage: "phone") }
            Button { callBack(entry, video: true) } label: { Label("Видеозвонок", systemImage: "video") }
            Button { router.openChat(entry.chatId) } label: { Label("Открыть чат", systemImage: "bubble.left") }
            Button(role: .destructive) { log.delete(entry.id) } label: { Label("Удалить", systemImage: "trash") }
        }
    }

    private func callBack(_ entry: CallLogEntry, video: Bool) {
        Safir.tap()
        let user = users[entry.peerId] ?? APIUser(
            id: entry.peerId, username: "", email: nil, fullName: ChatStore.shared.displayName(entry.peerId),
            avatarUrl: nil, bio: nil, isOnline: nil, lastSeen: nil, isBot: false, isPremium: nil)
        router.call(user, video: video)
    }

    private func reload() {
        entries = log.entries()
        var found: [String: APIUser] = [:]
        for id in Set(entries.map(\.peerId)) {
            if let u = ChatStore.shared.user(id) { found[id] = u }
        }
        users = found
    }
}

/// "Все | Пропущенные" with a sliding thumb (Telegram's segmented control, Android CallsSegment).
struct CallsSegment: View {
    @Binding var missedOnly: Bool
    @Namespace private var ns
    private static let thumb = Safir.dynamic(light: 0xFFFFFF, dark: 0x2A3546)

    var body: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { missed in
                let selected = missed == missedOnly
                Button {
                    guard !selected else { return }
                    Safir.tap()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { missedOnly = missed }
                } label: {
                    Text(missed ? "Пропущенные" : "Все")
                        .font(.subheadline.weight(selected ? .semibold : .medium))
                        .foregroundStyle(selected ? (missed ? Safir.danger : Safir.text) : Safir.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if selected {
                                Capsule().fill(Self.thumb)
                                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "segment", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .frame(height: 38)
        .background(Capsule().fill(Safir.pill))
        .padding(.horizontal, 16)
    }
}

/// "New call": pick a contact, then audio or video.
struct NewCallView: View {
    let onCall: (APIUser, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var contacts: [APIUser] = []
    @State private var query = ""
    @State private var remote: [APIUser] = []
    @State private var searching = false

    var body: some View {
        VStack(spacing: 8) {
            SearchCapsule(text: $query, prompt: "Имя или @username", busy: searching)
            List {
                if people.isEmpty && !searching {
                    EmptyStateView(icon: "phone.badge.plus", title: query.isEmpty ? "Нет контактов" : "Никого не найдено",
                                   subtitle: "Найдите человека по имени или @username")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(people, id: \.id) { user in
                    ContactRow(user: user) {
                        HStack(spacing: 18) {
                            Button { onCall(user, false) } label: {
                                Image(systemName: "phone.fill").font(.title3).foregroundStyle(Safir.accent)
                            }
                            .buttonStyle(.borderless)
                            Button { onCall(user, true) } label: {
                                Image(systemName: "video.fill").font(.title3).foregroundStyle(Safir.accent)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .listRowBackground(Safir.background)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .padding(.top, 8)
        .background(Safir.background.ignoresSafeArea())
        .navigationTitle("Новый звонок")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
        }
        .onAppear { contacts = ChatStore.shared.contacts(excluding: ChatService.shared.myUserId) }
        .task(id: query) {
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
    }

    private var people: [APIUser] {
        let q = query.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
        let local = q.isEmpty ? contacts
            : contacts.filter { $0.displayName.lowercased().contains(q) || $0.username.lowercased().contains(q) }
        let known = Set(local.map { $0.id.lowercased() })
        return local + remote.filter { !known.contains($0.id.lowercased()) }
    }
}
