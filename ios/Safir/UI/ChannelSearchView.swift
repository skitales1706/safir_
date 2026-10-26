import SwiftUI

/// GET /channels/search and /channels/preview (backend routers/channels.py).
struct ChannelPreviewDTO: Decodable, Hashable, Identifiable {
    let id: String
    let name: String?
    let description: String?
    let avatarUrl: String?
    let username: String?
    let subscribersCount: Int
    let isMember: Bool
    let posts: [ChannelPostDTO]?

    var title: String { name ?? "Канал" }
}

struct ChannelPostDTO: Decodable, Hashable, Identifiable {
    let id: String
    let type: String
    let content: String
    let createdAt: String?

    /// Channels are cloud chats, so posts arrive as plain text; media is shown as a label.
    var label: String {
        switch type {
        case "text": return content
        case "image": return "🖼 Фото"
        case "video": return "🎬 Видео"
        case "voice", "audio": return "🎤 Голосовое сообщение"
        default: return "📎 Файл"
        }
    }
}

/// Telegram-style channel discovery: search public channels or paste a link / @name, see the
/// channel with its latest posts, then subscribe or open it.
struct ChannelSearchView: View {
    let onOpen: (String) -> Void
    @State private var query = ""
    @State private var results: [ChannelPreviewDTO] = []
    @State private var loading = false
    @State private var failed = false
    @State private var opened: ChannelPreviewDTO?

    var body: some View {
        VStack(spacing: 8) {
            SearchCapsule(text: $query, prompt: "Название, @имя или ссылка", busy: loading)
            List {
                if query.trimmingCharacters(in: .whitespaces).count < 2 {
                    EmptyStateView(icon: "megaphone", title: "Поиск каналов",
                                   subtitle: "Найдите публичный канал по названию или вставьте ссылку на канал")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else if failed || (results.isEmpty && !loading) {
                    EmptyStateView(icon: failed ? "wifi.slash" : "magnifyingglass",
                                   title: failed ? "Нет соединения" : "Канал не найден")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(results) { channel in
                    Button { opened = channel } label: {
                        HStack(spacing: 12) {
                            AvatarView(name: channel.title, path: channel.avatarUrl, size: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(channel.title).font(.body.weight(.semibold)).foregroundStyle(Safir.text).lineLimit(1)
                                Text(subtitle(channel)).font(.subheadline).foregroundStyle(Safir.muted).lineLimit(1)
                            }
                            Spacer()
                            if channel.isMember {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Safir.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Safir.background)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .padding(.top, 8)
        .background(Safir.background.ignoresSafeArea())
        .navigationTitle("Каналы")
        .navigationBarTitleDisplayMode(.inline)
        .animation(Safir.spring, value: results.map(\.id))
        .task(id: query) { await search() }
        .navigationDestination(item: $opened) { channel in
            ChannelPreviewView(channel: channel, link: link(for: channel), onOpen: onOpen)
        }
    }

    private func subtitle(_ c: ChannelPreviewDTO) -> String {
        let subs = countText(c.subscribersCount, ("подписчик", "подписчика", "подписчиков"))
        guard let name = c.username else { return subs }
        return "@\(name) · \(subs)"
    }

    /// What /channels/join and /channels/preview accept for this channel.
    private func link(for c: ChannelPreviewDTO) -> String {
        if let name = c.username { return "@\(name)" }
        return query.trimmingCharacters(in: .whitespaces)
    }

    /// A link, "+token" or "@name" opens that channel directly instead of searching.
    private static func looksLikeLink(_ q: String) -> Bool {
        q.hasPrefix("@") || q.hasPrefix("+") || q.contains("/c/") || q.hasPrefix("http")
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            results = []
            failed = false
            return
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled else { return }
        loading = true
        defer { loading = false }
        let api = Session.shared.api
        do {
            // "@word" may also be the start of a name: without an exact match, search normally.
            if Self.looksLikeLink(q),
               let one = try? await api.get("channels/preview", query: ["link": q], as: ChannelPreviewDTO.self) {
                results = [one]
            } else {
                results = try await api.get("channels/search", query: ["q": q], as: [ChannelPreviewDTO].self)
            }
            failed = false
        } catch {
            results = []
            failed = !(error is APIError)
        }
    }
}

/// The channel before subscribing: photo, name, subscribers, description and latest posts.
struct ChannelPreviewView: View {
    let channel: ChannelPreviewDTO
    let link: String
    let onOpen: (String) -> Void
    @State private var full: ChannelPreviewDTO?
    @State private var joining = false
    @State private var error: String?

    private var shown: ChannelPreviewDTO { full ?? channel }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                AvatarView(name: shown.title, path: shown.avatarUrl, size: 92)
                    .padding(.top, 12)
                Text(shown.title).font(.title2.bold()).foregroundStyle(Safir.text).multilineTextAlignment(.center)
                Text(countText(shown.subscribersCount, ("подписчик", "подписчика", "подписчиков")))
                    .font(.subheadline).foregroundStyle(Safir.muted)
                if let name = shown.username {
                    Text("@\(name)").font(.subheadline.weight(.medium)).foregroundStyle(Safir.accent)
                }
                if let about = shown.description, !about.isEmpty {
                    Text(about).font(.body).foregroundStyle(Safir.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Safir.card))
                }
                if let posts = shown.posts, !posts.isEmpty {
                    Text("Последние публикации").font(.subheadline.weight(.semibold)).foregroundStyle(Safir.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                    ForEach(posts) { post in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(post.label).font(.body).foregroundStyle(Safir.text)
                            if let at = post.createdAt {
                                Text(TimeText.short(Dates.millis(at))).font(.caption).foregroundStyle(Safir.muted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Safir.bubbleIn))
                    }
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(Safir.danger)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Safir.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await joinOrOpen() }
            } label: {
                HStack {
                    if joining { ProgressView().tint(.white) }
                    Text(shown.isMember ? "Открыть канал" : "Подписаться").font(.headline)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(Capsule().fill(Safir.brandGradient))
            }
            .buttonStyle(PressableStyle())
            .disabled(joining)
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
        .navigationTitle("Канал")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            full = try? await Session.shared.api.get("channels/preview", query: ["link": link], as: ChannelPreviewDTO.self)
        }
    }

    private struct JoinBody: Encodable { let link: String }

    private func joinOrOpen() async {
        if shown.isMember {
            onOpen(shown.id.lowercased())
            return
        }
        joining = true
        defer { joining = false }
        do {
            let chat = try await Session.shared.api.post("channels/join", body: JoinBody(link: link), as: APIChat.self)
            Safir.tap(.medium)
            ChatStore.shared.sync(chats: [chat], myUserId: ChatService.shared.myUserId)
            await ChatService.shared.refreshChats()
            onOpen(chat.id.lowercased())
        } catch {
            self.error = error.localizedDescription
        }
    }
}
