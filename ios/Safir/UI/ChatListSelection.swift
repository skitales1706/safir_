import Observation
import SwiftUI

/// Pinned chats, like Android's isPinned and Telegram: kept on this device, shown on top of the
/// list in pin order. Free accounts pin 5, like Telegram.
@MainActor
@Observable
final class ChatPins {
    static let shared = ChatPins()
    private static let key = "pinned_chats"
    static let limit = 5

    private(set) var ids: [String]

    private init() {
        ids = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    func isPinned(_ chatId: String) -> Bool { ids.contains(chatId) }

    /// False when the limit is reached.
    @discardableResult
    func setPinned(_ chatId: String, _ pinned: Bool) -> Bool {
        if pinned {
            guard !ids.contains(chatId) else { return true }
            guard ids.count < Self.limit else { return false }
            ids.insert(chatId, at: 0)
        } else {
            ids.removeAll { $0 == chatId }
        }
        UserDefaults.standard.set(ids, forKey: Self.key)
        return true
    }

    /// Pinned chats first (in pin order), the rest keep their order.
    func sorted(_ chats: [ChatItem]) -> [ChatItem] {
        let rank = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let pinned = chats.filter { rank[$0.id] != nil }.sorted { rank[$0.id]! < rank[$1.id]! }
        return pinned + chats.filter { rank[$0.id] == nil }
    }
}

/// What the chat list shows: a type filter or one of the user's folders (Android folder tabs).
enum ChatTab: Hashable {
    case filter(ChatFilter)
    case folder(String)
}

/// Filter chips followed by the folder tabs; long press on a folder opens the folder settings.
struct ChatTabChips: View {
    @Binding var selected: ChatTab
    let chats: [ChatItem]
    let folders: [ChatFolder]
    var onEditFolders: () -> Void
    @Namespace private var ns

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ChatFilter.allCases) { filter in
                        let count = filter == .all ? 0 : chats.filter { filter.matches($0) && $0.unreadCount > 0 }.count
                        chip(.filter(filter), title: filter.rawValue, count: count)
                    }
                    ForEach(folders) { folder in
                        let ids = Set(folder.chatIds)
                        chip(.folder(folder.id), title: folder.name,
                             count: chats.filter { ids.contains($0.id) && $0.unreadCount > 0 }.count)
                            .contextMenu {
                                Button { onEditFolders() } label: { Label(tr("Изменить папки"), systemImage: "folder.badge.gearshape") }
                            }
                    }
                    Button {
                        Safir.tap()
                        onEditFolders()
                    } label: {
                        Image(systemName: folders.isEmpty ? "folder.badge.plus" : "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Safir.muted)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Safir.pill))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("edit-folders")
                }
                .padding(.horizontal, 16)
            }
            .onChange(of: selected) { _, tab in
                withAnimation(Safir.spring) { proxy.scrollTo(tab, anchor: .center) }
            }
        }
    }

    private func chip(_ tab: ChatTab, title: String, count: Int) -> some View {
        Button {
            Safir.tap()
            withAnimation(Safir.spring) { selected = tab }
        } label: {
            HStack(spacing: 5) {
                Text(tr(title)).font(.subheadline.weight(.semibold)).lineLimit(1)
                if count > 0 {
                    Text("\(count)").font(.caption2.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Safir.accent))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .foregroundStyle(selected == tab ? Safir.accent : Safir.muted)
            .padding(.horizontal, 14).frame(height: 34)
            .background {
                if selected == tab {
                    Capsule().fill(Safir.accent.opacity(0.18)).matchedGeometryEffect(id: "chip", in: ns)
                } else {
                    Capsule().fill(Safir.pill)
                }
            }
        }
        .buttonStyle(.plain)
        .id(tab)
    }
}

/// Round check on the left of a row while selecting (Telegram).
struct SelectionCheck: View {
    let on: Bool

    var body: some View {
        Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22))
            .foregroundStyle(on ? Safir.accent : Safir.muted.opacity(0.5))
            .contentTransition(.symbolEffect(.replace))
    }
}

/// Glass bar with the bulk actions (Android ChatSelectionActionBar): read, pin, mute, archive,
/// delete. Like Telegram an action marks read if any selected chat is unread, pins if any is
/// unpinned and so on.
struct ChatSelectionBar: View {
    let selected: [ChatItem]
    var onRead: (Bool) -> Void
    var onPin: (Bool) -> Void
    var onMute: (Bool) -> Void
    var onArchive: () -> Void
    var onDelete: () -> Void

    var body: some View {
        let enabled = !selected.isEmpty
        let anyUnread = selected.contains { $0.unreadCount > 0 } || !enabled
        let anyUnpinned = selected.contains { !ChatPins.shared.isPinned($0.id) } || !enabled
        let anyUnmuted = selected.contains { !$0.isMuted } || !enabled
        HStack(spacing: 0) {
            action(anyUnread ? "checkmark.message" : "message.badge", anyUnread ? "Прочитано" : "Непрочитано", enabled) {
                onRead(anyUnread)
            }
            action(anyUnpinned ? "pin" : "pin.slash", anyUnpinned ? "Закрепить" : "Открепить", enabled) {
                onPin(anyUnpinned)
            }
            action(anyUnmuted ? "bell.slash" : "bell", anyUnmuted ? "Без звука" : "Со звуком", enabled) {
                onMute(anyUnmuted)
            }
            action("archivebox", "В архив", enabled, action: onArchive)
            action("trash", "Удалить", enabled, danger: true, action: onDelete)
        }
        .padding(.vertical, 8).padding(.horizontal, 4)
        .safirGlass(in: RoundedRectangle(cornerRadius: 30, style: .continuous), rim: true)
        .padding(.horizontal, 12)
    }

    private func action(_ icon: String, _ title: String, _ enabled: Bool, danger: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button {
            if danger {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            } else {
                Safir.tap(.medium)
            }
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 19, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(tr(title)).font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(danger ? Safir.danger : Safir.accent)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}
