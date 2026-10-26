import Observation
import SwiftUI

/// Archived chats, like Android's ChatArchive.kt and Telegram: kept on this device only, hidden
/// from the main list, reachable through the "Архив" row on top of it.
@MainActor
@Observable
final class ChatArchive {
    static let shared = ChatArchive()
    private static let key = "archived_chats"

    private(set) var ids: Set<String>

    private init() {
        ids = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    func isArchived(_ chatId: String) -> Bool { ids.contains(chatId) }

    func setArchived(_ chatId: String, _ archived: Bool) {
        if archived { ids.insert(chatId) } else { ids.remove(chatId) }
        UserDefaults.standard.set(Array(ids), forKey: Self.key)
    }

    func archivedChats() -> [ChatItem] {
        ChatStore.shared.chats().filter { ids.contains($0.id) }
    }
}

/// The "Архив" row on top of the chat list (only when something is archived).
struct ArchiveEntryRow: View {
    let count: Int
    let unread: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "archivebox.fill")
                .font(.system(size: 22)).foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Safir.muted))
            VStack(alignment: .leading, spacing: 2) {
                Text("Архив").font(.body.weight(.semibold)).foregroundStyle(Safir.text)
                Text("\(count) чат.").font(.subheadline).foregroundStyle(Safir.muted)
            }
            Spacer()
            if unread > 0 {
                Text("\(unread)").font(.caption.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Safir.muted))
            }
        }
        .padding(.vertical, 4)
    }
}

/// Archived chats; a row opens the chat (the list's String navigation), swipe brings it back.
struct ArchivedChatsView: View {
    @State private var items: [ChatItem] = []

    var body: some View {
        List {
            ForEach(items) { chat in
                NavigationLink(value: chat.id) {
                    ChatRow(chat: chat, myUserId: ChatService.shared.myUserId, typing: ChatService.shared.isTyping(chat.id))
                }
                .listRowBackground(Safir.background)
                .swipeActions(edge: .trailing) {
                    Button {
                        withAnimation(Safir.spring) { ChatArchive.shared.setArchived(chat.id, false) }
                        reload()
                    } label: { Label("Вернуть", systemImage: "tray.and.arrow.up") }
                    .tint(Safir.accent)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Safir.background.ignoresSafeArea())
        .overlay {
            if items.isEmpty { ContentUnavailableView("Архив пуст", systemImage: "archivebox") }
        }
        .navigationTitle("Архив")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onChange(of: ChatService.shared.revision) { _, _ in reload() }
    }

    private func reload() { items = ChatArchive.shared.archivedChats() }
}
