import Observation
import SwiftUI

/// schemas.ChatFolderOut - kept on the server so every device of the account shows the same ones.
struct ChatFolder: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var chatIds: [String]
}

private struct FolderIn: Encodable {
    let name: String
    let chatIds: [String]
}

private struct FoldersPut: Encodable {
    let folders: [FolderIn]
}

/// Telegram's chat folders (backend routers/folders.py): GET /folders, PUT the whole list.
/// Free accounts get 3 folders, Premium 10 (premium.LIMITS).
@MainActor
@Observable
final class FoldersStore {
    static let shared = FoldersStore()
    private(set) var folders: [ChatFolder] = []
    private(set) var loaded = false
    var error: String?

    private var api: APIClient { Session.shared.api }

    func load() async {
        guard !DemoData.active else {
            if !loaded {
                folders = [ChatFolder(id: "f1", name: "Школа", chatIds: []), ChatFolder(id: "f2", name: "Семья", chatIds: [])]
            }
            loaded = true
            return
        }
        do {
            let list = try await api.get("folders", as: [ChatFolder].self)
            withAnimation(Safir.spring) { folders = list }
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }

    /// Saves the whole list; on a refusal (e.g. the free limit) the old list comes back.
    @discardableResult
    func save(_ list: [ChatFolder]) async -> Bool {
        let before = folders
        withAnimation(Safir.spring) { folders = list }
        guard !DemoData.active else { return true }
        do {
            let body = FoldersPut(folders: list.map { FolderIn(name: $0.name, chatIds: $0.chatIds) })
            let data = try await api.send("PUT", "folders", body: body)
            let saved = try api.decode([ChatFolder].self, from: data)
            withAnimation(Safir.spring) { folders = saved }
            return true
        } catch let apiError as APIError where apiError.status == 403 {
            withAnimation(Safir.spring) { folders = before }
            error = tr("Больше папок и чатов в папке — с Safir Premium.")
            return false
        } catch {
            withAnimation(Safir.spring) { folders = before }
            self.error = error.localizedDescription
            return false
        }
    }
}

struct FoldersPage: View {
    @State private var store = FoldersStore.shared
    @State private var editing: ChatFolder?

    var body: some View {
        SettingsPage(title: "Папки с чатами") {
            VStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(LinearGradient(colors: [Safir.accent, Safir.accentDeep],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .symbolEffect(.bounce, value: store.folders.count)
                Text(tr("Разложите чаты по папкам: работа, школа, семья. Папки видны на всех ваших устройствах."))
                    .font(.footnote).foregroundStyle(Safir.muted).multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .padding(.top, 8)
            .appearIn(0)

            SettingsGroup(header: "Мои папки", footer: "Бесплатно — 3 папки, с Safir Premium — 10.") {
                ForEach(Array(store.folders.enumerated()), id: \.element.id) { index, folder in
                    if index > 0 { SettingsDivider() }
                    ActionSettingsRow(icon: "folder.fill", color: Tile.blue, title: folder.name,
                                      subtitle: chatsCount(folder.chatIds.count), chevron: true) {
                        editing = folder
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
                if !store.folders.isEmpty { SettingsDivider() }
                ActionSettingsRow(icon: "plus", color: Tile.green, title: "Создать папку", titleColor: Safir.accent) {
                    editing = ChatFolder(id: "new-\(UUID().uuidString)", name: "", chatIds: [])
                }
            }
            .appearIn(1)
        }
        .task { await store.load() }
        .sheet(item: $editing) { FolderEditor(folder: $0) }
        .alert(tr("Не получилось"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.error ?? "") }
    }

    private func chatsCount(_ n: Int) -> String {
        n == 0 ? tr("Пустая") : tr("Чатов: %d", n)
    }
}

/// Name + the chats in it, picked from the chat list; delete for an existing folder.
private struct FolderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = FoldersStore.shared
    @State private var name: String
    @State private var selected: Set<String>
    @State private var busy = false
    @State private var confirmDelete = false
    let folder: ChatFolder
    private let chats = ChatStore.shared.chats()

    init(folder: ChatFolder) {
        self.folder = folder
        _name = State(initialValue: folder.name)
        _selected = State(initialValue: Set(folder.chatIds))
    }

    private var isNew: Bool { !FoldersStore.shared.folders.contains { $0.id == folder.id } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    SettingsGroup(header: "Название") {
                        TextField(tr("Например: Работа"), text: $name)
                            .padding(.horizontal, 16).frame(minHeight: 50)
                    }
                    SettingsGroup(header: "Чаты в папке", footer: tr("Выбрано: %d", selected.count)) {
                        ForEach(Array(chats.enumerated()), id: \.element.id) { index, chat in
                            if index > 0 { SettingsDivider(inset: 66) }
                            Button {
                                Safir.tap()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    if selected.contains(chat.id) { selected.remove(chat.id) } else { selected.insert(chat.id) }
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    AvatarView(name: chat.name, path: chat.avatarUrl, size: 40)
                                    Text(chat.name).font(.body).foregroundStyle(Safir.text).lineLimit(1)
                                    Spacer()
                                    Image(systemName: selected.contains(chat.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(selected.contains(chat.id) ? Safir.accent : Safir.muted.opacity(0.5))
                                        .contentTransition(.symbolEffect(.replace))
                                }
                                .padding(.horizontal, 14)
                                .frame(minHeight: 56)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RowPressStyle())
                        }
                    }
                    if !isNew {
                        SettingsGroup {
                            ActionSettingsRow(icon: "trash.fill", color: Safir.danger, title: "Удалить папку",
                                              titleColor: Safir.danger) { confirmDelete = true }
                        }
                    }
                }
                .padding(16)
            }
            .background(Safir.background.ignoresSafeArea())
            .navigationTitle(tr(isNew ? "Новая папка" : "Папка"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Отмена")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button(tr("Готово")) { save() }
                            .fontWeight(.semibold)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .confirmationDialog(tr("Удалить папку? Чаты останутся."), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(tr("Удалить"), role: .destructive) {
                    Task {
                        if await store.save(store.folders.filter { $0.id != folder.id }) { dismiss() }
                    }
                }
            }
        }
    }

    private func save() {
        busy = true
        var edited = folder
        edited.name = name.trimmingCharacters(in: .whitespaces)
        // Keep the chat-list order, not the tap order.
        edited.chatIds = chats.map(\.id).filter(selected.contains)
        var list = store.folders
        if let i = list.firstIndex(where: { $0.id == folder.id }) { list[i] = edited } else { list.append(edited) }
        Task {
            let ok = await store.save(list)
            busy = false
            if ok {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            }
        }
    }
}
