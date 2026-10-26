import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    let chatId: String
    private var service: ChatService { ChatService.shared }
    @State private var chat: ChatItem?
    @State private var messages: [MessageItem] = []
    @State private var draft = ""
    @State private var replyTo: MessageItem?
    @State private var editing: MessageItem?
    @State private var photoItem: PhotosPickerItem?
    @State private var showFiles = false
    @State private var showInfo = false
    @State private var senderProfile: ChatItem?
    @State private var recorder = VoiceRecorder()
    @State private var lastTypingSent = Date.distantPast
    @State private var mediaError: String?
    @State private var atBottom = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("emoji_panel_tab") private var panelTab = 0
    @State private var showCamera = false
    @State private var showContactPicker = false
    @State private var showEmoji = false
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var forwardItems: [MessageItem]?
    @State private var deleteItems: [MessageItem]?
    @State private var translation: String?
    @State private var scrollTarget: String?
    /// Long-pressed message: the Telegram-style menu over the chat (MessageMenu.swift).
    @State private var menu: MessageMenuRequest?

    private var selectedMessages: [MessageItem] { messages.filter { selection.contains($0.serverId) } }

    private func handle(_ action: BubbleAction, _ m: MessageItem) {
        switch action {
        case .forward: forwardItems = [m]
        case .delete: deleteItems = [m]
        case .select:
            Safir.tap()
            withAnimation(Safir.spring) {
                selecting = true
                selection = [m.serverId]
            }
        case .pin:
            Task { if await service.pin(m) { Safir.tap(.medium) } }
        case .openContact:
            if let contact = SharedContact.parse(m.content) { openContact(contact.userId) }
        case .translate:
            Task { translation = await Translator.translate(m.content) ?? "Перевод сейчас недоступен" }
        case .transcribe:
            Task {
                guard let file = await MediaService.shared.resolve(m) else {
                    translation = "Голосовое ещё не загружено"
                    return
                }
                translation = await AiTools.transcribe(file) ?? "Распознавание речи сейчас недоступно"
            }
        }
    }

    /// Group member's profile from their avatar / name: the 1:1 chat if there is one, else just the person.
    private func openSender(_ userId: String) {
        let me = service.myUserId
        guard userId.lowercased() != me.lowercased(), let user = ChatStore.shared.user(userId) else { return }
        Safir.tap()
        senderProfile = ChatStore.shared.chat(ChatIds.direct(me, userId)) ?? ChatItem.person(user, myUserId: me)
    }

    private func endSelection() {
        withAnimation(Safir.spring) {
            selecting = false
            selection = []
        }
    }

    /// Selection header: close, "N выбрано".
    private var selectionTop: some View {
        HStack(spacing: 8) {
            GlassCircle(action: endSelection) { Image(systemName: "xmark") }
            Text("\(selection.count) выбрано")
                .font(.headline).foregroundStyle(Safir.text)
                .contentTransition(.numericText())
                .padding(.horizontal, 18).frame(height: 44).glassCapsule()
            Spacer()
        }
        .padding(.horizontal, 10).padding(.top, 4)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Selection actions: forward, copy, delete - glass capsule like the composer.
    private var selectionBottom: some View {
        HStack(spacing: 0) {
            selectionButton("Переслать", "arrowshape.turn.up.right") { forwardItems = selectedMessages }
                .disabled(AppSecurity.shared.policy.blockForwarding)
            selectionButton("Копировать", "doc.on.doc") {
                UIPasteboard.general.string = selectedMessages.filter { $0.type == "text" }.map(\.content).joined(separator: "\n")
                endSelection()
            }
            .disabled(AppSecurity.shared.policy.blockCopy)
            selectionButton("Удалить", "trash", tint: Safir.danger) { deleteItems = selectedMessages }
        }
        .frame(height: 56)
        .glassCapsule()
        .padding(.horizontal, 12).padding(.bottom, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func selectionButton(_ title: String, _ icon: String, tint: Color = Safir.accent,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                Text(title).font(.caption2.weight(.medium))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressableStyle())
    }

    /// "Удалить у всех" only where the server allows it (own messages, admins).
    private func canDeleteForAll(_ items: [MessageItem]) -> Bool {
        items.allSatisfy { $0.isMe } || chat?.myRole == "admin" || chat?.myRole == "owner"
    }

    /// Same sender within a few minutes = one visual run (one tail, one name).
    static func sameRun(_ a: MessageItem?, _ b: MessageItem?) -> Bool {
        guard let a, let b else { return false }
        return a.senderId == b.senderId && abs(b.timestamp - a.timestamp) < 5 * 60 * 1000
    }
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(messages.enumerated()), id: \.element.serverId) { index, m in
                            let prev = index > 0 ? messages[index - 1] : nil
                            let next = index + 1 < messages.count ? messages[index + 1] : nil
                            let newDay = prev.map { !DateChip.sameDay($0.timestamp, m.timestamp) } ?? true
                            if newDay { DateChip(millis: m.timestamp) }
                            MessageBubble(message: m, chat: chat,
                                          replied: m.replyToId.flatMap { id in messages.first { $0.serverId == id } },
                                          tail: !Self.sameRun(m, next),
                                          showName: newDay || !Self.sameRun(prev, m),
                                          onReply: { replyTo = m; composerFocused = true },
                                          onEdit: { editing = m; draft = m.content; composerFocused = true },
                                          onDelete: { Task { await service.delete(m) } },
                                          onReact: { emoji in Task { await service.react(m, emoji: emoji) } },
                                          onRetry: { retry(m) },
                                          selecting: selecting,
                                          selected: selection.contains(m.serverId),
                                          onAction: { handle($0, m) },
                                          onOpenSender: { openSender(m.senderId) },
                                          onMenu: { request in
                                              composerFocused = false
                                              showEmoji = false
                                              menu = request
                                          })
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard selecting else { return }
                                    Safir.tap()
                                    if selection.contains(m.serverId) { selection.remove(m.serverId) } else { selection.insert(m.serverId) }
                                    if selection.isEmpty { withAnimation(Safir.spring) { selecting = false } }
                                }
                                .padding(.top, Self.sameRun(prev, m) && !newDay ? 2 : 8)
                                .id(m.serverId)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.92, anchor: m.isMe ? .bottomTrailing : .bottomLeading)),
                                    removal: .dust(seed: m.serverId.hashValue)))
                                .onAppear { if m.serverId == messages.last?.serverId { atBottom = true } }
                                .onDisappear { if m.serverId == messages.last?.serverId { atBottom = false } }
                        }
                        if service.isTyping(chatId) {
                            HStack {
                                TypingDots(color: Safir.muted)
                                    .padding(.horizontal, 14).padding(.vertical, 12)
                                    .background(BubbleShape(isMe: false, tail: true).fill(Safir.bubbleIn))
                                Spacer()
                            }
                            .padding(.top, 8)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .animation(Safir.spring, value: messages.count)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(ChatWallpaper(choice: ChatThemes.shared.choice(chatId)))
                .overlay(alignment: .bottomTrailing) {
                    if !atBottom, let last = messages.last?.serverId {
                        Button {
                            Safir.tap()
                            withAnimation(Safir.spring) { proxy.scrollTo(last, anchor: .bottom) }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Safir.accent)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(.regularMaterial))
                                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        }
                        .buttonStyle(PressableStyle())
                        .padding(14)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(Safir.spring, value: atBottom)
                .overlay {
                    if AppSecurity.shared.policy.watermark {
                        WatermarkOverlay(text: ChatStore.shared.displayName(service.myUserId))
                    }
                }
                .onChange(of: messages.last?.serverId) { _, last in
                    if let last { withAnimation { proxy.scrollTo(last, anchor: .bottom) } }
                }
                .onAppear {
                    if let last = messages.last?.serverId { proxy.scrollTo(last, anchor: .bottom) }
                }
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(Safir.spring) { proxy.scrollTo(target, anchor: .center) }
                    scrollTarget = nil
                }
            }
        }
        // Telegram / Safir style: no bars - separate floating glass panels over the wallpaper,
        // messages scroll underneath them.
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 6) {
                if selecting { selectionTop } else { topBar }
                if !selecting, let pinnedId = chat?.pinnedMessageId, let pinned = messages.first(where: { $0.serverId == pinnedId }) {
                    PinnedBar(message: pinned, onTap: { scrollTarget = pinned.serverId },
                              onUnpin: { withAnimation(Safir.spring) { service.unpin(chatId: chatId) } })
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if !selecting, MeetingService.shared.active.contains(chatId), MeetingService.shared.chatId != chatId {
                    meetingBanner.transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.bottom, 4)
            .animation(Safir.spring, value: selecting)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selecting {
                selectionBottom
            } else if let chat, chat.isChannel, chat.myRole == "member" {
                Text("Только администраторы публикуют в канале")
                    .font(.footnote).foregroundStyle(Safir.muted)
                    .padding(.horizontal, 16).frame(height: 40).glassCapsule().padding(8)
            } else {
                composer
            }
        }
        .overlay {
            if let menu {
                // Keeps the safe area: the menu clamps between the top capsule and the composer.
                MessageMenuOverlay(request: menu) { self.menu = nil }
                    .id(menu.id)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: Binding(get: { forwardItems != nil }, set: { if !$0 { forwardItems = nil } })) {
            ForwardSheet(messages: forwardItems ?? [], sourceTitle: chat?.name ?? "") { _ in endSelection() }
        }
        .confirmationDialog(deleteItems.map { $0.count > 1 ? "Удалить \($0.count) сообщ.?" : "Удалить сообщение?" } ?? "",
                            isPresented: Binding(get: { deleteItems != nil }, set: { if !$0 { deleteItems = nil } }),
                            titleVisibility: .visible) {
            if let items = deleteItems {
                if canDeleteForAll(items) {
                    Button("Удалить у всех", role: .destructive) {
                        Task { for m in items { await service.delete(m) } }
                        endSelection()
                    }
                }
                Button("Удалить у меня", role: .destructive) {
                    withAnimation(Safir.spring) { for m in items { service.deleteLocally(m) } }
                    endSelection()
                }
            }
        }
        .alert("Перевод", isPresented: Binding(get: { translation != nil }, set: { if !$0 { translation = nil } })) {
            Button("Копировать") { UIPasteboard.general.string = translation }
            Button("OK", role: .cancel) {}
        } message: {
            Text(translation ?? "")
        }
        .navigationDestination(isPresented: $showInfo) {
            if let chat { ChatInfoView(chat: chat, onGone: { dismiss() }) }
        }
        .navigationDestination(item: $senderProfile) { ChatInfoView(chat: $0, openedFromChat: false) }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { shot in Task { await sendShot(shot) } }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showContactPicker) {
            ContactPickerSheet { user in
                let text = SharedContact.text(userId: user.id, name: user.fullName ?? user.username, username: user.username)
                service.sendText(text, chatId: chatId, replyTo: replyTo?.serverId)
                replyTo = nil
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { sendFile(url) }
        }
        .alert("Нельзя отправить", isPresented: Binding(get: { mediaError != nil }, set: { if !$0 { mediaError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(mediaError ?? "")
        }
        .onChange(of: photoItem) { _, item in
            if let item { Task { await sendPicked(item) } }
        }
        .onAppear {
            reload()
            service.openChat(chatId)
        }
        .task {
            let opened = ChatStore.shared.chat(chatId)
            if opened?.isChannel == true { await service.refreshAcks(chatId: chatId) }
            if opened?.isGroup == true { await MeetingService.shared.refreshStatus(chatId: chatId) }
        }
        .onDisappear { service.closeChat(chatId) }
        .onChange(of: service.revision) { _, _ in reload() }
        // Secret chat: iOS can't block screenshots, so the content is hidden while the screen is
        // recorded/mirrored and in the app switcher, and a screenshot is reported to the partner.
        .overlay {
            if chat?.isSecret == true && (AppSecurity.shared.screenCaptured || scenePhase != .active) {
                PrivacyCover(showUnlock: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            guard let chat, !chat.isGroup, !chat.isCloud, let partner = chat.partnerId else { return }
            Task { _ = try? await Session.shared.api.send("POST", "chats/\(partner)/screenshot", body: nil) }
        }
    }

    /// Back circle | avatar + name + status capsule | calls capsule.
    private var topBar: some View {
        HStack(spacing: 8) {
            GlassCircle(action: { dismiss() }) { Image(systemName: "chevron.left") }
                .accessibilityIdentifier("back")
            Button { showInfo = true } label: {
                HStack(spacing: 8) {
                    AvatarView(name: chat?.name ?? "", path: chat?.avatarUrl, size: 34)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(chat?.name ?? "").font(.subheadline.weight(.semibold)).foregroundStyle(Safir.text).lineLimit(1)
                        HStack(spacing: 4) {
                            if service.isTyping(chatId) { TypingDots() }
                            Text(subtitle).font(.caption).lineLimit(1)
                                .foregroundStyle(subtitle == "в сети" || service.isTyping(chatId) ? Safir.accent : Safir.muted)
                        }
                        .animation(.easeInOut, value: subtitle)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 5).padding(.trailing, 14)
                .frame(height: 44)
                .glassCapsule()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chat-header")
            if let chat, !chat.isCloud || canStartMeeting(chat) {
                HStack(spacing: 2) {
                    if !chat.isCloud {
                        Button { CallService.shared.start(chat: chat, video: false) } label: {
                            Image(systemName: "phone.fill").frame(width: 40, height: 44)
                        }
                    }
                    // Groups/channels: a meeting on the organisation's SFU when the server has one,
                    // otherwise (groups) the peer-to-peer video call - like Android.
                    Button { startVideo(chat) } label: {
                        Image(systemName: "video.fill").frame(width: 40, height: 44)
                    }
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Safir.accent)
                .padding(.horizontal, 4)
                .glassCapsule()
            }
        }
        .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 6)
    }

    /// In a channel only admins open a meeting (backend meetings.py); subscribers join a running one.
    private func canStartMeeting(_ chat: ChatItem) -> Bool {
        chat.isChannel && (chat.myRole == "admin" || chat.myRole == "owner")
    }

    private func startVideo(_ chat: ChatItem) {
        guard chat.isGroup else {
            CallService.shared.start(chat: chat, video: true)
            return
        }
        Task {
            switch await MeetingService.shared.join(chat: chat) {
            case .joined: break
            case .unavailable:
                if chat.isChannel { mediaError = "Видеовстречи не включены на сервере" } else { CallService.shared.start(chat: chat, video: true) }
            case .failed:
                mediaError = "Не удалось подключиться к видеовстрече"
            }
        }
    }

    private var meetingBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "video.fill").foregroundStyle(Safir.accent)
            Text("Идёт видеовстреча").font(.subheadline.weight(.semibold)).foregroundStyle(Safir.text)
            Spacer()
            Button("Присоединиться") {
                guard let chat else { return }
                Task {
                    if await MeetingService.shared.join(chat: chat) == .failed {
                        mediaError = "Не удалось подключиться к видеовстрече"
                    }
                }
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 14).frame(height: 44)
        .glassCapsule()
        .padding(.horizontal, 10)
    }

    private var subtitle: String {
        guard let chat else { return "" }
        if service.isTyping(chat.id) { return "печатает…" }
        if chat.isChannel { return "\(chat.subscribersCount) подписчиков" }
        if chat.isGroup { return "\(ChatStore.shared.members(chat.id).count) участников" }
        if chat.isBot { return "бот" }
        guard let partner = chat.partnerId, let user = ChatStore.shared.user(partner) else { return "" }
        return user.isOnline == true ? "в сети" : TimeText.lastSeen(user.lastSeen)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            if let target = replyTo ?? editing {
                HStack {
                    Image(systemName: editing != nil ? "pencil" : "arrowshape.turn.up.left")
                        .foregroundStyle(Safir.accent).frame(width: 24)
                    RoundedRectangle(cornerRadius: 1.5).fill(Safir.accent).frame(width: 3)
                    VStack(alignment: .leading) {
                        Text(editing != nil ? "Редактирование" : "Ответ").font(.caption.bold()).foregroundStyle(Safir.accent)
                        Text(ChatStore.preview(target)).font(.caption).lineLimit(1).foregroundStyle(Safir.muted)
                    }
                    Spacer()
                    Button(action: cancelReplyOrEdit) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
                .frame(height: 44)
                .padding(.horizontal, 12)
                .safirGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    if CameraPicker.available {
                        Button { showCamera = true } label: { Label("Камера", systemImage: "camera") }
                    }
                    PhotosPicker(selection: $photoItem, matching: .any(of: [.images, .videos])) {
                        Label("Фото или видео", systemImage: "photo")
                    }
                    Button { showFiles = true } label: { Label("Файл", systemImage: "doc") }
                    Button { showContactPicker = true } label: { Label("Контакт", systemImage: "person.crop.circle") }
                    Button { openPanel(stickers: true) } label: { Label("Стикеры", systemImage: "face.smiling") }
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Safir.text)
                        .frame(width: 42, height: 42)
                        .safirGlass(in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                }
                TextField("Сообщение", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(.leading, 16).padding(.trailing, 40).padding(.vertical, 11)
                    // Emoji panel <-> keyboard, like Android's composer.
                    .overlay(alignment: .bottomTrailing) {
                        Button {
                            Safir.tap()
                            if showEmoji {
                                showEmoji = false
                                composerFocused = true
                            } else {
                                openPanel(stickers: nil)
                            }
                        } label: {
                            Image(systemName: showEmoji ? "keyboard" : "face.smiling")
                                .font(.system(size: 20)).foregroundStyle(Safir.muted)
                                .frame(width: 38, height: 40)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .accessibilityIdentifier("emoji-toggle")
                    }
                    .safirGlass(in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    .focused($composerFocused)
                    .onChange(of: draft) { _, _ in typingChanged() }
                ZStack {
                    if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && editing == nil {
                        VoiceButton(recorder: recorder) { data in
                            guard allowed("audio", data.count) else { return }
                            scanAndSend(data, type: "audio", name: "voice.m4a")
                        }
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                    } else {
                        Button { send() } label: {
                            Image(systemName: editing != nil ? "checkmark" : "arrow.up")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Safir.brandGradient))
                                .shadow(color: Color(hex: 0x1ECFEF).opacity(0.4), radius: 6, y: 2)
                        }
                        .buttonStyle(PressableStyle())
                        .contextMenu {
                            // Channel admins: a post every subscriber has to confirm (ChannelAck.swift).
                            if editing == nil, let chat, chat.isChannel, chat.myRole == "admin" || chat.myRole == "owner" {
                                Button { send(requiresAck: true) } label: {
                                    Label("Отправить с «Ознакомлен»", systemImage: "checkmark.seal")
                                }
                            }
                        }
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.7),
                           value: draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            if showEmoji {
                EmojiPanel(onPick: { draft += $0 },
                           onBackspace: { if !draft.isEmpty { draft.removeLast() } },
                           onSticker: { sendSticker($0) })
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(Safir.spring, value: replyTo?.serverId ?? editing?.serverId)
        .animation(Safir.spring, value: showEmoji)
        .onChange(of: composerFocused) { _, focused in
            if focused { showEmoji = false }
        }
        // The panel takes the keyboard's height, so the composer stays level when they swap.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) {
            KeyboardMetrics.record($0)
        }
    }

    /// Emoji / sticker panel in place of the keyboard; `stickers` nil keeps the last tab.
    private func openPanel(stickers: Bool?) {
        if let stickers { panelTab = stickers ? 1 : 0 }
        composerFocused = false
        withAnimation(Safir.spring) { showEmoji = true }
    }

    private func sendSticker(_ sticker: StickerDef) {
        service.sendText(StickerDef.token(sticker.id), chatId: chatId, replyTo: replyTo?.serverId)
        replyTo = nil
    }

    private func reload() {
        chat = ChatStore.shared.chat(chatId)
        messages = ChatStore.shared.messages(chatId)
    }

    private func retry(_ m: MessageItem) {
        if m.type == "text" {
            service.retry(m)
        } else {
            service.retryMedia(m)
        }
    }

    private func cancelReplyOrEdit() {
        replyTo = nil
        if editing != nil {
            editing = nil
            draft = ""
        }
    }

    private func send(requiresAck: Bool = false) {
        let text = draft
        draft = ""
        if let editing {
            self.editing = nil
            Task { _ = await service.edit(editing, newText: text) }
            return
        }
        Safir.tap()
        service.sendText(text, chatId: chatId, replyTo: replyTo?.serverId, requiresAck: requiresAck)
        replyTo = nil
        service.sendTyping(chatId: chatId, isTyping: false)
    }

    private func typingChanged() {
        guard Date().timeIntervalSince(lastTypingSent) > 3, !draft.isEmpty else { return }
        lastTypingSent = Date()
        service.sendTyping(chatId: chatId, isTyping: true)
    }

    private func sendShot(_ shot: CameraPicker.Shot) async {
        switch shot {
        case .video(let url):
            guard let prepared = await MediaPrep.video(at: url) else { return }
            guard allowed("video", prepared.data.count) else { return }
            scanAndSend(prepared.data, type: "video", name: "video.mp4", thumbnail: prepared.thumbnail)
        case .photo(let data):
            guard let prepared = MediaPrep.image(data) else { return }
            guard allowed("image", prepared.data.count) else { return }
            scanAndSend(prepared.data, type: "image", name: "photo.jpg", thumbnail: prepared.thumbnail)
        }
    }

    /// Contact card or a mention: the person's 1:1 chat if there is one, else their profile.
    private func openContact(_ userId: String) {
        let me = service.myUserId
        guard userId.lowercased() != me.lowercased() else { return }
        if let chat = ChatStore.shared.chat(ChatIds.direct(me, userId)) {
            senderProfile = chat
            return
        }
        Task {
            guard let user = try? await Session.shared.api.get("users/\(userId)", as: APIUser.self) else { return }
            ChatStore.shared.upsert(users: [user])
            senderProfile = ChatItem.person(user, myUserId: me)
        }
    }

    private func sendPicked(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            guard let movie = try? await item.loadTransferable(type: PickedMovie.self),
                  let prepared = await MediaPrep.video(at: movie.url) else { return }
            guard allowed("video", prepared.data.count) else { return }
            scanAndSend(prepared.data, type: "video", name: "video.mp4", thumbnail: prepared.thumbnail)
        } else {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let prepared = MediaPrep.image(data) else { return }
            guard allowed("image", prepared.data.count) else { return }
            scanAndSend(prepared.data, type: "image", name: "photo.jpg", thumbnail: prepared.thumbnail)
        }
    }

    /// Organisation antivirus (DLP scan_files, AvScan.swift): checked before anything is
    /// encrypted or sent; without the policy this sends straight away.
    private func scanAndSend(_ data: Data, type: String, name: String, thumbnail: Data? = nil) {
        let reply = replyTo?.serverId
        replyTo = nil
        Task {
            if let reason = await AvScan.check(data, filename: name) {
                mediaError = reason
                return
            }
            service.sendMedia(data, type: type, chatId: chatId, thumbnailJPEG: thumbnail, replyTo: reply)
        }
    }

    /// Organisation policy (dlp_policy.py): allowed types and size.
    private func allowed(_ type: String, _ bytes: Int) -> Bool {
        if let reason = AppSecurity.shared.policy.refusal(type: type, bytes: bytes) {
            mediaError = reason
            return false
        }
        return true
    }

    private func sendFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), allowed("file", data.count) else { return }
        scanAndSend(data, type: "file", name: url.lastPathComponent)
    }
}

/// A picked video, copied out of the Photos sandbox.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}
