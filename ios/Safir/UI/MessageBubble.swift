import AVKit
import SwiftUI

struct MessageBubble: View {
    let message: MessageItem
    let chat: ChatItem?
    let replied: MessageItem?
    /// Last message of a run from the same sender: gets the tail (Telegram grouping).
    var tail = true
    /// First message of a run in a group: shows the sender's name.
    var showName = true
    let onReply: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onReact: (String) -> Void
    let onRetry: () -> Void
    /// Selection mode ("Выбрать"): a check circle instead of the menu.
    var selecting = false
    var selected = false
    var onAction: (BubbleAction) -> Void = { _ in }
    /// Tap on the sender's avatar or name in a group: open their profile (Telegram).
    var onOpenSender: () -> Void = {}
    /// Long press: the chat shows the Telegram-style menu (MessageMenu.swift).
    var onMenu: (MessageMenuRequest) -> Void = { _ in }

    @State private var dragX: CGFloat = 0
    /// Emoji just reacted with: ReactionBurst plays once over the bubble.
    @State private var burst: String?
    @State private var frame = BubbleFrame()

    private var isMedia: Bool { message.type == "image" || message.type == "video" }
    private var showsAvatar: Bool { !message.isMe && chat?.isGroup == true && chat?.isChannel != true }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if selecting {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? Safir.accent : Safir.muted)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            if message.isMe { Spacer(minLength: 56) }
            if showsAvatar {
                // Avatar only next to the last message of a run, the space is kept otherwise.
                ZStack {
                    if tail {
                        AvatarView(name: ChatStore.shared.displayName(message.senderId),
                                   path: ChatStore.shared.user(message.senderId)?.avatarUrl, size: 30)
                            .onTapGesture { if !selecting { onOpenSender() } }
                    }
                }
                .frame(width: 30, height: 30)
            }
            VStack(alignment: message.isMe ? .trailing : .leading, spacing: 3) {
                mainBody
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame.rect = $0 }
                    .onLongPressGesture(minimumDuration: 0.3, maximumDistance: 10) { openMenu() }
                .overlay {
                    if let burst, !AppSettings.shared.reduceAnimations {
                        ReactionBurst(emoji: burst)
                            .id(burst)
                            .task {
                                // Long enough for the Lottie effect to finish.
                                try? await Task.sleep(nanoseconds: 2_200_000_000)
                                self.burst = nil
                            }
                    }
                }
                ChannelAckBar(message: message, chat: chat)
                if !message.isMe && (chat?.isBot == true || chat?.isChannel == true) { BotButtons(message: message) }
                if !message.reactions.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(reactionCounts, id: \.emoji) { pair in
                            // Animated like Telegram's reactions; plays again when the count changes.
                            HStack(spacing: 3) {
                                AnimatedEmojiView(emoji: pair.emoji, size: 20, replay: pair.count)
                                if pair.count > 1 {
                                    Text("\(pair.count)").font(.footnote.weight(.semibold))
                                        .foregroundStyle(pair.mine ? Safir.accent : Safir.text)
                                        .contentTransition(.numericText())
                                }
                            }
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(pair.mine ? Safir.accent.opacity(0.16) : Safir.surface))
                            .overlay(Capsule().stroke(Safir.accent.opacity(pair.mine ? 0.9 : 0), lineWidth: 1.2))
                            .onTapGesture {
                                guard !selecting, !message.isPending else { return }
                                Safir.tap()
                                onReact(pair.emoji)
                                if !pair.mine { burst = pair.emoji }
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: message.reactions)
                }
            }
            if !message.isMe { Spacer(minLength: 56) }
        }
        // Swipe left to reply, like Telegram.
        .offset(x: dragX)
        .overlay(alignment: .trailing) {
            if dragX < -20 {
                Image(systemName: "arrowshape.turn.up.left.circle.fill")
                    .font(.title2).foregroundStyle(Safir.accent)
                    .opacity(min(1, Double(-dragX) / 60))
                    .offset(x: 34 + dragX / 2)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height), value.translation.width < 0,
                          !message.isPending else { return }
                    dragX = max(value.translation.width, -70)
                }
                .onEnded { _ in
                    if dragX <= -60 {
                        Safir.tap(.medium)
                        onReply()
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { dragX = 0 }
                }
        )
    }

    @ViewBuilder
    private var mainBody: some View {
        if message.type == "text", let sticker = StickerDef.from(content: message.content) {
            StickerView(sticker: sticker)
        } else if message.type == "text", message.replyToId == nil,
                  let big = AnimatedEmoji.bigEmoji(in: message.content) {
            // Only emoji: big and animated, no bubble (Telegram); the time in a small pill.
            VStack(alignment: message.isMe ? .trailing : .leading, spacing: 2) {
                BigEmojiMessage(emoji: big)
                footer
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.25)))
            }
        } else {
            bubble
        }
    }

    private func openMenu() {
        guard !selecting else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onMenu(MessageMenuRequest(
            message: message, frame: frame.rect, preview: AnyView(mainBody),
            myReaction: message.reactions[ChatService.shared.myUserId.lowercased()],
            onReact: message.isPending ? nil : { emoji in
                onReact(emoji)
                // After the menu closes, so the burst plays over the bubble.
                if !emoji.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { burst = emoji } }
            },
            items: menuItems))
    }

    private var reactionCounts: [(emoji: String, count: Int, mine: Bool)] {
        var counts: [String: Int] = [:]
        for emoji in message.reactions.values { counts[emoji, default: 0] += 1 }
        let mine = message.reactions[ChatService.shared.myUserId]
        return counts.sorted { $0.key < $1.key }.map { (emoji: $0.key, count: $0.value, mine: $0.key == mine) }
    }

    private var meta: Color { message.isMe ? Safir.metaOut : Safir.metaIn }

    private var footer: some View {
        HStack(spacing: 3) {
            if message.ttlSeconds > 0 { Image(systemName: "timer") }
            if message.isEdited { Text("изм.") }
            if chat?.isChannel == true && message.views > 0 {
                Image(systemName: "eye")
                Text("\(message.views)")
            }
            Text(TimeText.clock(message.timestamp))
            if message.isMe {
                TicksView(status: message.deliveryStatus, isDelivered: message.isDelivered, isRead: message.isRead)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(isMedia ? Color.white : meta)
        .padding(.horizontal, isMedia ? 6 : 0).padding(.vertical, isMedia ? 2 : 0)
        .background(Capsule().fill(Color.black.opacity(isMedia ? 0.35 : 0)))
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 3) {
            if showName && showsAvatar {
                Text(ChatStore.shared.displayName(message.senderId))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AvatarView.color(for: ChatStore.shared.displayName(message.senderId)))
                    .onTapGesture { if !selecting { onOpenSender() } }
            }
            if message.isForwarded {
                Label("Переслано", systemImage: "arrowshape.turn.up.right").font(.caption).foregroundStyle(Safir.accent)
            }
            if let replied {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1.5).fill(Safir.accent).frame(width: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(replied.isMe ? "Вы" : ChatStore.shared.displayName(replied.senderId))
                            .font(.caption.weight(.semibold)).foregroundStyle(Safir.accent)
                        Text(ChatStore.preview(replied)).font(.caption).lineLimit(1).foregroundStyle(Safir.text.opacity(0.75))
                    }
                }
                .padding(.vertical, 4).padding(.trailing, 8).padding(.leading, 2)
                .background(RoundedRectangle(cornerRadius: 6).fill(Safir.accent.opacity(0.1)))
                .fixedSize(horizontal: false, vertical: true)
            }
            if message.unverifiedDevice {
                Label("С нового, не подтверждённого устройства", systemImage: "exclamationmark.shield")
                    .font(.caption2).foregroundStyle(.orange)
            }
            if message.type == "text", let contact = SharedContact.parse(message.content) {
                ZStack(alignment: .bottomTrailing) {
                    SharedContactCard(contact: contact) { if !selecting { onAction(.openContact) } }
                    footer
                }
            } else if message.type == "text" {
                // Time sits inline after the last line, like Telegram.
                ZStack(alignment: .bottomTrailing) {
                    textContent
                    footer
                }
            } else {
                ZStack(alignment: .bottomTrailing) {
                    content
                    footer.padding(isMedia ? 6 : 0)
                }
            }
        }
        .padding(.horizontal, isMedia ? 3 : 11).padding(.vertical, isMedia ? 3 : 7)
        .foregroundStyle(Safir.text)
        .background(
            BubbleShape(isMe: message.isMe, tail: tail)
                .fill(message.isMe
                      ? AnyShapeStyle(LinearGradient(colors: [AppSettings.shared.bubble.top, AppSettings.shared.bubble.bottom],
                                                     startPoint: .top, endPoint: .bottom))
                      : AnyShapeStyle(Safir.bubbleIn))
                .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
        )
        .opacity(message.deliveryStatus == DeliveryStatus.sending ? 0.85 : 1)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Telegram's trick: an invisible copy of the time/ticks at the end of the text reserves
    /// exactly the room the real footer (drawn over it) needs - on the last line when it fits,
    /// on a new line when it doesn't. Fixed padding overlapped short messages.
    private var spacer: String {
        var s = "\u{2004}" + TimeText.clock(message.timestamp)
        if message.isEdited { s = "\u{2004}изм." + s }
        if message.ttlSeconds > 0 { s = "\u{2004}\u{2004}\u{2004}" + s }
        if message.isMe { s += "\u{2004}\u{2004}\u{2004}\u{2004}" }
        return s
    }

    private var composedText: Text {
        Text(message.content).font(.system(size: AppSettings.shared.fontSize))
            + Text(spacer).font(.system(size: 13)).foregroundColor(.clear)
    }

    /// No system text selection: its long press would beat the message menu (copy is in the menu).
    private var textContent: some View { composedText }

    @ViewBuilder
    private var content: some View {
        switch message.type {
        case "image", "video":
            VisualMediaView(message: message)
        case "audio":
            AudioMessageView(message: message)
        case "file":
            FileMessageView(message: message)
        default:
            if AppSecurity.shared.policy.blockCopy {
                Text(message.content)
            } else {
                Text(message.content).textSelection(.enabled)
            }
        }
    }
}

/// Photo / video: the encrypted mini preview first (blurred), the real file once decrypted.
struct VisualMediaView: View {
    let message: MessageItem
    @State private var fileURL: URL?
    @State private var image: UIImage?
    @State private var showPlayer = false
    @State private var showViewer = false
    /// Auto-download is off for this network (Settings → Данные и память): wait for a tap.
    @State private var waiting = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let data = MediaCrypto.openThumbnail(message.thumbnail, keyBase64: message.fileKey),
                      let preview = UIImage(data: data) {
                Image(uiImage: preview).resizable().scaledToFill().blur(radius: 6)
            } else {
                Rectangle().fill(Color(.tertiarySystemFill))
            }
            if waiting && fileURL == nil {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white, .black.opacity(0.45))
                    .transition(.scale.combined(with: .opacity))
            } else if fileURL == nil || message.isPending {
                ProgressView()
            } else if message.type == "video" {
                Image(systemName: "play.circle.fill").font(.system(size: 44)).foregroundStyle(.white).shadow(radius: 4)
            }
        }
        .frame(width: 230, height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture {
            if waiting && fileURL == nil {
                Safir.tap()
                withAnimation(Safir.spring) { waiting = false }
                Task { await load() }
                return
            }
            guard fileURL != nil else { return }
            if message.type == "video" {
                showPlayer = true
            } else {
                showViewer = true
            }
        }
        .task(id: "\(message.serverId)|\(message.content)") {
            if message.isMe || MediaAutoload.isLocal(message) || MediaAutoload.shared.allows(message.type) {
                await load()
            } else {
                waiting = true
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            if let fileURL { VideoPlayerScreen(url: fileURL) }
        }
        .fullScreenCover(isPresented: $showViewer) {
            if let image { ImageViewerScreen(image: image) }
        }
    }

    private func load() async {
        guard let url = await MediaService.shared.resolve(message) else { return }
        fileURL = url
        if message.type == "image" {
            image = UIImage(contentsOfFile: url.path)
        } else {
            image = await MediaPrep.videoThumbnail(url)
        }
    }
}

struct VideoPlayerScreen: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VideoPlayer(player: AVPlayer(url: url))
                .ignoresSafeArea()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
    }
}

struct ImageViewerScreen: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        NavigationStack {
            Image(uiImage: image)
                .resizable().scaledToFit()
                .scaleEffect(scale)
                .gesture(MagnificationGesture()
                    .onChanged { scale = max(1, $0) }
                    .onEnded { _ in withAnimation { scale = max(1, min(scale, 4)) } })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                    if !AppSecurity.shared.policy.blockMediaSave {
                        ToolbarItem(placement: .primaryAction) {
                            ShareLink(item: Image(uiImage: image), preview: SharePreview("Фото", image: Image(uiImage: image)))
                        }
                    }
                }
        }
    }
}

struct AudioMessageView: View {
    let message: MessageItem
    @State private var player: AVAudioPlayer?
    @State private var playing = false
    @State private var url: URL?

    var body: some View {
        HStack(spacing: 10) {
            Button {
                toggle()
            } label: {
                Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 34))
            }
            .disabled(url == nil)
            if url == nil { ProgressView() }
            Image(systemName: "waveform").font(.title2).foregroundStyle(.secondary)
            if let duration = player?.duration {
                Text(String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)).font(.caption).monospacedDigit()
            }
        }
        .task(id: "\(message.serverId)|\(message.content)") {
            url = await MediaService.shared.resolve(message)
            if let url { player = try? AVAudioPlayer(contentsOf: url) }
        }
    }

    private func toggle() {
        guard let player else { return }
        if playing {
            player.pause()
            playing = false
            return
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        playing = true
        let remaining = max(player.duration - player.currentTime, 0)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000) + 200_000_000)
            if player.isPlaying == false { playing = false }
        }
    }
}

struct FileMessageView: View {
    let message: MessageItem
    @State private var url: URL?
    @State private var loading = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill").font(.title2).foregroundStyle(.blue)
            VStack(alignment: .leading) {
                Text("Файл").font(.subheadline)
                if loading { ProgressView().controlSize(.small) }
            }
            if let url {
                if !AppSecurity.shared.policy.blockMediaSave {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                }
            } else {
                Button {
                    Task {
                        loading = true
                        url = await MediaService.shared.resolve(message)
                        loading = false
                    }
                } label: { Image(systemName: "arrow.down.circle") }
                .disabled(message.content.isEmpty)
            }
        }
    }
}
