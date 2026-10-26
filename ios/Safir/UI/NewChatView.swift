import SwiftUI

/// Telegram's "New message" (the chat list's "+"): search on top, then Create group / contact /
/// channel, then all contacts A-Z. Searching also asks the server (GET /users?query=), so people
/// never talked to show up too.
struct NewChatView: View {
    let onOpen: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var contacts: [APIUser] = []
    @State private var query = ""
    @State private var remote: [APIUser] = []
    @State private var searching = false
    @State private var pushed: PeopleSheet?

    private var myUserId: String { ChatService.shared.myUserId }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                SearchCapsule(text: $query, prompt: "Имя или @username", busy: searching)
                List {
                    if query.isEmpty {
                        Section {
                            ActionRow(icon: "person.2", title: "Создать группу") { pushed = .newGroup }
                            ActionRow(icon: "person.badge.plus", title: "Создать контакт") { pushed = .addContact }
                            ActionRow(icon: "megaphone", title: "Создать канал") { pushed = .newChannel }
                        }
                        .listRowBackground(Safir.background)
                        .listRowSeparator(.hidden)
                    }
                    if people.isEmpty && !searching {
                        EmptyStateView(icon: query.isEmpty ? "person.2" : "magnifyingglass",
                                       title: query.isEmpty ? "Пока нет контактов" : "Никого не найдено",
                                       subtitle: "Найдите человека по имени или @username")
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    if query.isEmpty {
                        // All contacts A-Z under letter headers, as in Telegram.
                        ForEach(letterSections) { section in
                            Section {
                                ForEach(section.users, id: \.id) { user in personRow(user) }
                            } header: {
                                SectionCaption(text: section.letter)
                            }
                        }
                    } else if !people.isEmpty {
                        Section {
                            ForEach(people, id: \.id) { user in personRow(user) }
                        } header: {
                            SectionCaption(text: "Результаты")
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .animation(Safir.spring, value: people.map(\.id))
            }
            .padding(.top, 8)
            .background(Safir.background.ignoresSafeArea())
            .navigationTitle("Новое сообщение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
            .navigationDestination(item: $pushed) { sheet in
                PeopleSheetContent(sheet: sheet, onOpen: onOpen)
            }
            .task(id: query) { await search() }
            .onAppear { contacts = ChatStore.shared.contacts(excluding: myUserId) }
        }
    }

    private func personRow(_ user: APIUser) -> some View {
        Button { open(user) } label: { ContactRow(user: user) }
            .buttonStyle(.plain)
            .listRowBackground(Safir.background)
            .listRowSeparatorTint(Safir.separator)
    }

    /// Contacts sorted by name and grouped by first letter.
    private var letterSections: [LetterSection] {
        let sorted = contacts.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        var sections: [LetterSection] = []
        for user in sorted {
            let letter = user.displayName.first.map { String($0).uppercased() } ?? "#"
            if sections.last?.letter == letter {
                sections[sections.count - 1].users.append(user)
            } else {
                sections.append(LetterSection(letter: letter, users: [user]))
            }
        }
        return sections
    }

    /// Contacts matching the query, then server results that aren't contacts yet.
    private var people: [APIUser] {
        let q = query.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
        let local = q.isEmpty ? contacts
            : contacts.filter { $0.displayName.lowercased().contains(q) || $0.username.lowercased().contains(q) }
        let known = Set(local.map { $0.id.lowercased() })
        return local + remote.filter { !known.contains($0.id.lowercased()) }
    }

    private func search() async {
        guard query.trimmingCharacters(in: .whitespaces).count >= 2 else {
            remote = []
            return
        }
        try? await Task.sleep(nanoseconds: 300_000_000)  // debounce typing
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        remote = (try? await PeopleSearch.find(query)) ?? []
    }

    private func open(_ user: APIUser) {
        Safir.tap()
        onOpen(ChatStore.shared.ensureDirectChat(myUserId: myUserId, partner: user))
    }
}

struct LetterSection: Identifiable {
    let letter: String
    var users: [APIUser]
    var id: String { letter }
}
