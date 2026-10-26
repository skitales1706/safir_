import SwiftUI

// Building blocks of the Telegram-style profile (ChatInfoView): big header, action tiles,
// shared media tabs and member rows. Android: UserProfileScreen / GroupProfileScreen / ProfileSections.

extension ChatItem {
    /// A 1:1 profile for someone without a chat yet (a group member); nothing is stored.
    static func person(_ user: APIUser, myUserId: String) -> ChatItem {
        ChatItem(id: ChatIds.direct(myUserId, user.id), name: user.displayName, avatarUrl: user.avatarUrl,
                 isGroup: false, isChannel: false, isBot: user.isBot ?? false, partnerId: user.id.lowercased(),
                 lastMessage: nil, lastMessageTime: 0, lastSenderId: nil, lastStatus: 0, lastIsRead: false,
                 unreadCount: 0, groupKeyVersion: 0, ttlSeconds: 0, isSecret: false, pinnedMessageId: nil,
                 description: nil, username: user.username, subscribersCount: 0, myRole: nil, isMuted: false)
    }
}

/// How far the profile is scrolled (negative = pulled down past the top).
struct ProfileScrollKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Avatar that pops in and stretches when pulled, name, status, on a soft accent glow.
struct ProfileHeader: View {
    let name: String
    let path: String?
    let status: String
    var statusAccent = false
    var online = false
    var premium = false
    var pull: CGFloat = 0
    @State private var shown = false

    var body: some View {
        VStack(spacing: 0) {
            AvatarView(name: name, path: path, size: 108)
                .overlay(alignment: .bottomTrailing) {
                    if online {
                        Circle().fill(Safir.online).frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Safir.background, lineWidth: 3.5))
                            .offset(x: -6, y: -6)
                    }
                }
                .shadow(color: Safir.accent.opacity(0.35), radius: 22, y: 8)
                .scaleEffect((shown ? 1 : 0.6) * (1 + min(max(pull, 0), 140) / 450), anchor: .bottom)
                .opacity(shown ? 1 : 0)
            HStack(spacing: 6) {
                Text(verbatim: name)
                    .font(.system(size: 24, weight: .bold)).foregroundStyle(Safir.text)
                    .multilineTextAlignment(.center).lineLimit(2)
                if premium {
                    Image(systemName: "star.circle.fill").font(.system(size: 20)).foregroundStyle(Safir.accent)
                }
            }
            .padding(.top, 14).padding(.horizontal, 32)
            Text(verbatim: status)
                .font(.subheadline.weight(statusAccent ? .medium : .regular))
                .foregroundStyle(statusAccent ? Safir.accent : Safir.muted)
                .padding(.top, 3).padding(.horizontal, 32)
                .animation(.easeInOut, value: status)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64).padding(.bottom, 18)
        .background(alignment: .top) {
            LinearGradient(colors: [Safir.accent.opacity(0.24), Safir.accent.opacity(0.07), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 340 + max(pull, 0))
                .offset(y: -100 - max(pull, 0))
        }
        .onAppear {
            if AppSettings.shared.reduceAnimations {
                shown = true
            } else {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) { shown = true }
            }
        }
    }
}

/// Card button under the header: Сообщение / Звук / Звонок / Видео / Добавить / Выйти.
struct ProfileActionTile: View {
    let icon: String
    let title: String
    var danger = false
    let action: () -> Void

    var body: some View {
        Button {
            Safir.tap()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(danger ? Safir.danger : Safir.accent)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(height: 24)
                Text(tr(title))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(danger ? Safir.danger : Safir.text)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity).frame(height: 66)
            .background(Safir.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Safir.separator, lineWidth: 0.5))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Member of a group / channel: avatar with the online dot, name, status, role badge.
struct MemberRow: View {
    let userId: String
    let role: String
    let isMe: Bool

    var body: some View {
        let user = ChatStore.shared.user(userId)
        let online = user?.isOnline == true
        HStack(spacing: 12) {
            AvatarView(name: ChatStore.shared.displayName(userId), path: user?.avatarUrl, size: 42)
                .overlay(alignment: .bottomTrailing) {
                    if online {
                        Circle().fill(Safir.online).frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Safir.card, lineWidth: 2.5))
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(isMe ? tr("Вы") : ChatStore.shared.displayName(userId))
                    .font(.body.weight(.medium)).foregroundStyle(Safir.text).lineLimit(1)
                Text(user.map { tr($0.statusText) } ?? "")
                    .font(.footnote).foregroundStyle(online ? Safir.accent : Safir.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            if role == "owner" || role == "admin" {
                Text(tr(role == "owner" ? "владелец" : "админ"))
                    .font(.caption.weight(.semibold)).foregroundStyle(Safir.accent)
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(Capsule().fill(Safir.accent.opacity(0.14)))
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }
}

// MARK: - Shared media

enum SharedTab: Int, CaseIterable {
    case media, files, links, voice

    var title: String {
        switch self {
        case .media: return "Медиа"
        case .files: return "Файлы"
        case .links: return "Ссылки"
        case .voice: return "Голосовые"
        }
    }
}

struct SharedLink: Identifiable {
    let url: URL
    let message: MessageItem
    var id: String { "\(message.serverId)|\(url.absoluteString)" }
}

/// Photos, videos, files, links and voice notes of a chat, newest first (from the local database).
struct SharedContent {
    var media: [MessageItem] = []
    var files: [MessageItem] = []
    var links: [SharedLink] = []
    var voice: [MessageItem] = []

    init() {}

    init(chatId: String) {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        for m in ChatStore.shared.messages(chatId, limit: 3000).reversed() where !m.isPending {
            switch m.type {
            case "image", "video": media.append(m)
            case "file": files.append(m)
            case "audio": voice.append(m)
            case "text":
                guard let detector, m.content.contains(".") else { continue }
                let range = NSRange(m.content.startIndex..., in: m.content)
                for match in detector.matches(in: m.content, range: range) {
                    if let url = match.url, url.scheme?.hasPrefix("http") == true {
                        links.append(SharedLink(url: url, message: m))
                    }
                }
            default: break
            }
        }
    }

    func count(_ tab: SharedTab) -> Int {
        switch tab {
        case .media: return media.count
        case .files: return files.count
        case .links: return links.count
        case .voice: return voice.count
        }
    }

    var isEmpty: Bool { SharedTab.allCases.allSatisfy { count($0) == 0 } }
}

/// Telegram's tabs under the profile: a sliding pill over the chosen tab, a 3-column grid of media.
struct SharedMediaSection: View {
    let content: SharedContent
    @State private var tab: SharedTab = .media
    @Namespace private var pill
    @Environment(\.openURL) private var openURL

    private var tabs: [SharedTab] { SharedTab.allCases.filter { content.count($0) > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tabs, id: \.self) { t in
                        Button {
                            Safir.tap()
                            withAnimation(Safir.spring) { tab = t }
                        } label: {
                            HStack(spacing: 5) {
                                Text(tr(t.title))
                                Text(verbatim: "\(content.count(t))").foregroundStyle(Safir.muted)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(tab == t ? Safir.accent : Safir.text)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background {
                                if tab == t {
                                    Capsule().fill(Safir.accent.opacity(0.14)).matchedGeometryEffect(id: "pill", in: pill)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
            }
            Group {
                switch tab {
                case .media: mediaGrid
                case .files: rows(content.files) { FileMessageView(message: $0) }
                case .links: linkRows
                case .voice: rows(content.voice) { AudioMessageView(message: $0) }
                }
            }
            .transition(.opacity)
        }
        .padding(.vertical, 10)
        .background(Safir.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Safir.separator, lineWidth: 0.5))
        .onAppear {
            if content.count(tab) == 0, let first = tabs.first { tab = first }
        }
    }

    private var mediaGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
            ForEach(content.media.prefix(90)) { MediaThumb(message: $0) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 10)
    }

    private func rows<Row: View>(_ items: [MessageItem], @ViewBuilder row: @escaping (MessageItem) -> Row) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.prefix(40).enumerated()), id: \.element.id) { index, m in
                if index > 0 { SettingsDivider(inset: 14) }
                HStack(spacing: 10) {
                    row(m)
                    Spacer(minLength: 4)
                    Text(verbatim: TimeText.short(m.timestamp)).font(.caption).foregroundStyle(Safir.muted)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
        }
    }

    private var linkRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(content.links.prefix(40).enumerated()), id: \.element.id) { index, link in
                if index > 0 { SettingsDivider() }
                Button { openURL(link.url) } label: {
                    HStack(spacing: 14) {
                        IconTile(symbol: "link", color: Safir.accent, size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: link.url.host ?? link.url.absoluteString)
                                .font(.body.weight(.medium)).foregroundStyle(Safir.text).lineLimit(1)
                            Text(verbatim: link.url.absoluteString)
                                .font(.footnote).foregroundStyle(Safir.accent).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).frame(minHeight: 54)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
            }
        }
    }
}

/// Square photo / video cell: the downloaded picture when it is on the phone, else the encrypted
/// mini preview; a tap opens the full file.
struct MediaThumb: View {
    let message: MessageItem
    @State private var picture: UIImage?
    @State private var viewing: UIImage?
    @State private var playing: URL?
    @State private var loading = false

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let picture {
                    Image(uiImage: picture).resizable().scaledToFill()
                } else if let data = MediaCrypto.openThumbnail(message.thumbnail, keyBase64: message.fileKey),
                          let preview = UIImage(data: data) {
                    Image(uiImage: preview).resizable().scaledToFill().blur(radius: 3)
                } else {
                    Safir.accent.opacity(0.1)
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if message.type == "video" {
                    Image(systemName: "play.fill").font(.caption.bold()).foregroundStyle(.white)
                        .padding(6).shadow(color: .black.opacity(0.5), radius: 3)
                }
            }
            .overlay { if loading { ProgressView().tint(.white) } }
            .contentShape(Rectangle())
            .onTapGesture { Task { await open() } }
            .task(id: message.serverId) {
                guard message.type == "image", MediaAutoload.isLocal(message),
                      let url = await MediaService.shared.resolve(message) else { return }
                picture = UIImage(contentsOfFile: url.path)?.preparingThumbnail(of: CGSize(width: 260, height: 260))
            }
            .fullScreenCover(isPresented: Binding(get: { viewing != nil }, set: { if !$0 { viewing = nil } })) {
                if let viewing { ImageViewerScreen(image: viewing) }
            }
            .fullScreenCover(isPresented: Binding(get: { playing != nil }, set: { if !$0 { playing = nil } })) {
                if let playing { VideoPlayerScreen(url: playing) }
            }
    }

    private func open() async {
        guard !loading else { return }
        Safir.tap()
        loading = true
        defer { loading = false }
        guard let url = await MediaService.shared.resolve(message) else { return }
        if message.type == "video" {
            playing = url
        } else {
            viewing = UIImage(contentsOfFile: url.path)
        }
    }
}
