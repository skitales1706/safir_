import Foundation
import Observation

/// The message pipeline - a port of Android's ChatRepository + WebSocketManager:
/// receive (WebSocket / history / sync) -> decrypt exactly once -> local database, and
/// send (encrypt per device or with the group sender key -> POST). The UI reads the database
/// and redraws when `revision` changes.
@MainActor
@Observable
final class ChatService {
    static let shared = ChatService()

    private(set) var revision = 0
    private(set) var connected = false
    /// chat id -> "typing" until this moment.
    private(set) var typing: [String: Date] = [:]
    private(set) var activeChatId: String?
    private(set) var myUserId = ""
    private(set) var installId = ""

    @ObservationIgnored private let store = ChatStore.shared
    @ObservationIgnored private let ws = WebSocketClient()
    @ObservationIgnored private var receiveChain: Task<Void, Never>?
    @ObservationIgnored private var sendChain: Task<Void, Never>?
    @ObservationIgnored private var mediaChain: Task<Void, Never>?
    @ObservationIgnored private var lastReadPost: [String: Date] = [:]
    @ObservationIgnored private var expiryTimer: Timer?
    @ObservationIgnored private var processor: MessageProcessor?
    @ObservationIgnored private var pendingSignals: [[String: Any]] = []

    private var signal: SignalService { SignalService.shared }
    private var api: APIClient { Session.shared.api }

    // MARK: Lifecycle

    func start(myUserId: String, installId: String) {
        self.myUserId = myUserId.lowercased()
        self.installId = installId
        processor = MessageProcessor(myUserId: myUserId, installId: installId) { [weak self] in
            await self?.refreshChats()
        }
        ws.onEvent = { [weak self] event in self?.handle(event) }
        ws.onConnected = { [weak self] in
            guard let self else { return }
            self.connected = true
            self.flushSignals()
            self.enqueue { await self.catchUp() }
        }
        ws.onDisconnected = { [weak self] in self?.connected = false }
        ws.connect(userId: self.myUserId)
        enqueue { await self.catchUp() }
        expiryTimer?.invalidate()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.purgeExpired() }
        }
    }

    /// Screenshot mode (DemoData): no server, one chat shows "typing".
    func startDemo(myUserId: String) {
        self.myUserId = myUserId.lowercased()
        connected = true
        typing[ChatIds.direct(myUserId, "u-amina")] = Date().addingTimeInterval(3600)
        bump()
    }

    func stop() {
        ws.disconnect()
        expiryTimer?.invalidate()
        expiryTimer = nil
        connected = false
        activeChatId = nil
        myUserId = ""
        bump()
    }

    /// Foreground again: iOS dropped the socket while suspended.
    func appBecameActive() {
        guard !myUserId.isEmpty else { return }
        if !ws.isConnected { ws.connect(userId: myUserId) }
        enqueue { await self.catchUp() }
    }

    func appEnteredBackground() {
        // A call keeps running in the background (audio mode) and still needs its signaling.
        guard !myUserId.isEmpty, !CallService.shared.inCall else { return }
        if let activeChatId { setFocus(nil, previous: activeChatId) }
        ws.disconnect()
    }

    private func bump() { revision &+= 1 }

    /// Incoming work runs strictly in order - a PreKey message must establish its session before
    /// the messages that depend on it.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = receiveChain
        receiveChain = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    private func enqueueSend(_ work: @escaping @MainActor () async -> Void) {
        let previous = sendChain
        sendChain = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    /// Attachments have their own queue: text overtakes a heavy upload in progress.
    private func enqueueMedia(_ work: @escaping @MainActor () async -> Void) {
        let previous = mediaChain
        mediaChain = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    private func catchUp() async {
        await refreshChats()
        await syncMessages()
        await retryPending()
    }

    // MARK: Chats

    func refreshChats() async {
        do {
            let chats = try await api.get("chats", as: [APIChat].self)
            store.sync(chats: chats, myUserId: myUserId)
            bump()
            // Membership changed somewhere -> my sender key may be due (cheap no-op otherwise).
            for c in chats where c.isGroup && c.isChannel != true {
                let members = (c.members ?? []).map { $0.id.lowercased() }
                if (try? await signal.groupSupportsSignal(myUserId: myUserId, memberIds: members)) == true {
                    _ = await signal.ensureOwnSenderKeyCurrent(myUserId: myUserId, installId: installId, chatId: c.id,
                                                               keyVersion: c.groupKeyVersion ?? 1, memberIds: members)
                }
            }
        } catch {
            AppLog.write("Chats refresh failed: \(error.localizedDescription)")
        }
    }

    // MARK: Receive

    /// Catch-up after reconnect: every message missed across all chats since the last sync.
    func syncMessages() async {
        do {
            let since = Database.shared.string("last_sync_at")
            let body = try await api.send("POST", "sync", body: SyncRequest(since: since))
            let response = try api.decode(SyncResponse.self, from: body)
            for item in processor?.incoming(from: response) ?? [] {
                await process(item, live: false)
            }
            Database.shared.set(response.serverTime, for: "last_sync_at")
            bump()
        } catch {
            AppLog.write("Sync failed: \(error.localizedDescription)")
        }
    }

    func fetchHistory(_ chatId: String) async {
        guard let chat = store.chat(chatId) else { return }
        let target = chat.isGroup ? chat.id : (chat.partnerId ?? ChatIds.apiTarget(chat.id, myUserId: myUserId))
        do {
            let body = try await api.send("POST", "chats/\(target)/messages/history", body: nil)
            let messages = try api.decode([APIMessage].self, from: body)
            guard let processor else { return }
            let items = messages.map { processor.incoming(from: $0, isGroup: chat.isGroup, partnerId: chat.partnerId) }
            for item in items.sorted(by: { $0.timestamp < $1.timestamp }) {
                await process(item, live: false)
            }
            bump()
        } catch {
            AppLog.write("History failed: \(error.localizedDescription)")
        }
    }

    /// Decrypt + store (shared with the Notification Service Extension), then the UI side:
    /// redraw, delivery ack, read receipt or banner.
    private func process(_ m: IncomingMessage, live: Bool) async {
        guard let processor else { return }
        let result = await processor.process(m, activeChatId: activeChatId)
        if result.changed { bump() }
        guard let item = result.inserted, !item.isMe, live else { return }
        ws.send(["type": "delivery_status", "message_id": item.serverId, "chat_id": item.chatId])
        if activeChatId == item.chatId {
            markRead(item.chatId)
        } else if let chat = result.chat ?? store.chat(item.chatId) {
            Notifier.shared.incoming(chat: chat, senderName: chat.isGroup ? store.displayName(item.senderId) : nil,
                                     preview: ChatStore.preview(item))
        }
    }

    private func applyRemoteEdit(messageId: String, content: String, ratchetContents: [String: String]?,
                                 senderDeviceId: Int?, editVersion: Int, senderId: String, isGroup: Bool,
                                 serverChatId: String) async {
        guard let processor else { return }
        if await processor.applyEdit(messageId: messageId, content: content, ratchetContents: ratchetContents,
                                     senderDeviceId: senderDeviceId, editVersion: editVersion, senderId: senderId,
                                     isGroup: isGroup, serverChatId: serverChatId) {
            bump()
        }
    }

    // MARK: WebSocket events

    private func handle(_ e: [String: Any]) {
        let type = e["type"] as? String ?? ""
        // The server's relay stamps `from_id` on everything another USER sent; server-originated
        // control events never carry it - one that does was forged by another account.
        let fromPeer = e["from_id"] != nil
        if type == "call" || e["call_type"] != nil {
            CallService.shared.handleSignal(e)
            return
        }
        switch type {
        case "new_message", "message":
            guard let item = incoming(fromSocket: e) else { return }
            enqueue { await self.process(item, live: true) }
        case "edit_message":
            let id = str(e["message_id"])
            let content = str(e["content"])
            let ratchet = e["ratchet_contents"] as? [String: String]
            let device = int(e["sender_device_id"])
            let version = int(e["edit_version"]) ?? 0
            let sender = str(e["sender_id"]).lowercased()
            let isGroup = e["is_group"] as? Bool ?? false
            let chat = str(e["chat_id"]).lowercased()
            enqueue {
                await self.applyRemoteEdit(messageId: id, content: content, ratchetContents: ratchet, senderDeviceId: device,
                                           editVersion: version, senderId: sender, isGroup: isGroup, serverChatId: chat)
            }
        case "delete_message":
            let id = str(e["message_id"])
            if let m = store.message(id) {
                store.delete(id)
                MediaCache.remove(messageId: id)
                store.refreshPreview(chatId: m.chatId)
                bump()
            }
        case "delivery_status" where !fromPeer:
            store.markDelivered(str(e["message_id"]))
            bump()
        case "read_status" where !fromPeer:
            let reader = str(e["reader_id"]).lowercased()
            let isGroup = e["is_group"] as? Bool ?? false
            let chatId = isGroup ? str(e["chat_id"]).lowercased() : ChatIds.direct(myUserId, reader)
            if reader != myUserId {
                store.markMineRead(chatId: chatId)
                bump()
            }
        case "typing":
            let from = str(e["from_id"]).lowercased()
            guard !from.isEmpty else { return }
            let chatId = ChatIds.direct(myUserId, from)
            typing[chatId] = (e["is_typing"] as? Bool ?? false) ? Date().addingTimeInterval(6) : nil
        case "user_status" where !fromPeer:
            store.setOnline(str(e["user_id"]), online: e["online"] as? Bool ?? false, lastSeen: e["last_seen"] as? String)
            bump()
        case "chat_updated" where !fromPeer:
            enqueue { await self.refreshChats() }
        case "user_keys_changed" where !fromPeer:
            let user = str(e["user_id"])
            Task { await self.signal.forgetDevices(of: user) }
        case "removed_from_group" where !fromPeer:
            store.deleteChat(str(e["chat_id"]).lowercased())
            bump()
        case "messages_expired" where !fromPeer:
            for id in (e["message_ids"] as? [String]) ?? [] {
                store.delete(id)
                MediaCache.remove(messageId: id)
            }
            if let chat = e["chat_id"] as? String { store.refreshPreview(chatId: chat.lowercased()) }
            bump()
        case "meeting_started" where !fromPeer:
            MeetingService.shared.started(e)
        case "media_ready" where !fromPeer:
            store.attachMedia(str(e["message_id"]), url: str(e["content"]))
            bump()
        case "chat_cleared" where !fromPeer:
            let isGroup = e["is_group"] as? Bool ?? false
            let partner = (e["partner_id"] as? String) ?? ""
            let chatId = isGroup ? str(e["chat_id"]).lowercased() : (partner.isEmpty ? "" : ChatIds.direct(myUserId, partner))
            if !chatId.isEmpty {
                store.clearMessages(chatId)
                bump()
            }
        default:
            break
        }
    }

    private func incoming(fromSocket e: [String: Any]) -> IncomingMessage? {
        let senderRaw = str(e["sender_id"]).isEmpty ? str(e["from_id"]) : str(e["sender_id"])
        let sender = senderRaw.lowercased()
        let chatId = str(e["chat_id"]).lowercased()
        guard !chatId.isEmpty, !sender.isEmpty else { return nil }
        let isMe = sender == myUserId
        let partner = isMe ? str(e["to_id"]).lowercased() : sender
        let id = str(e["id"])
        let key = (e["encrypted_key"] as? String) ?? ""
        return IncomingMessage(
            id: id.isEmpty ? "WS_\(Clock.nowMs)" : id, clientMessageId: e["client_message_id"] as? String,
            serverChatId: chatId, isGroup: e["is_group"] as? Bool ?? false, partnerId: partner.isEmpty ? nil : partner,
            senderId: sender, content: str(e["content"]), encryptedKey: key.isEmpty ? nil : key,
            ratchetContents: e["ratchet_contents"] as? [String: String], senderDeviceId: int(e["sender_device_id"]),
            protocolVersion: int(isMe ? e["protocol_version_sender"] : e["protocol_version"]) ?? 5,
            type: (e["msg_type"] as? String) ?? "text", timestamp: int64(e["timestamp"]) ?? Clock.nowMs,
            isDelivered: e["is_delivered"] as? Bool ?? false, isRead: e["is_read"] as? Bool ?? false,
            replyToId: e["reply_to_id"] as? String, isForwarded: e["is_forwarded"] as? Bool ?? false,
            editVersion: 0, ttlSeconds: int(e["ttl_seconds"]) ?? 0, expiresAt: int64(e["expires_at"]) ?? 0,
            thumbnail: e["thumbnail"] as? String, requiresAck: e["requires_ack"] as? Bool ?? false,
            acks: int(e["acks"]) ?? 0, views: int(e["views"]) ?? 0, replyMarkup: BotMarkup.from(wire: e["reply_markup"]))
    }

    private func str(_ v: Any?) -> String { (v as? String) ?? "" }
    private func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue }
    private func int64(_ v: Any?) -> Int64? { (v as? NSNumber)?.int64Value }

    // MARK: Open / read / typing

    func openChat(_ chatId: String) {
        let previous = activeChatId
        activeChatId = chatId
        setFocus(chatId, previous: previous)
        markRead(chatId)
        Notifier.shared.clear(chatId: chatId)
        enqueue { await self.fetchHistory(chatId) }
    }

    func closeChat(_ chatId: String) {
        guard activeChatId == chatId else { return }
        activeChatId = nil
        setFocus(nil, previous: chatId)
    }

    /// POST /chats/focus - the server marks messages in the focused chat read on delivery.
    private func setFocus(_ chatId: String?, previous: String?) {
        var target: String?
        if let chatId, let chat = store.chat(chatId) {
            target = chat.isGroup ? chat.id : chat.partnerId
        }
        Task {
            _ = try? await api.send("POST", "chats/focus", body: ChatFocusRequest(targetId: target))
        }
    }

    func markRead(_ chatId: String) {
        store.resetUnread(chatId)
        store.markTheirsRead(chatId: chatId)
        bump()
        if let last = lastReadPost[chatId], Date().timeIntervalSince(last) < 1 { return }
        lastReadPost[chatId] = Date()
        guard let chat = store.chat(chatId) else { return }
        let target = chat.isGroup ? chat.id : (chat.partnerId ?? "")
        guard !target.isEmpty else { return }
        Task { _ = try? await api.send("POST", "chats/\(target)/read", body: nil) }
    }

    /// Call signaling over the socket. Queued while it is down (a call answered from the lock
    /// screen sends `call_accepted` before the app has reconnected) and flushed on connect.
    func sendSignal(_ payload: [String: Any]) {
        if ws.isConnected {
            ws.send(payload)
        } else {
            pendingSignals.append(payload)
            if !myUserId.isEmpty { ws.connect(userId: myUserId) }
        }
    }

    private func flushSignals() {
        let queued = pendingSignals
        pendingSignals.removeAll()
        for payload in queued { ws.send(payload) }
    }

    func sendTyping(chatId: String, isTyping: Bool) {
        guard let chat = store.chat(chatId), !chat.isGroup, let partner = chat.partnerId else { return }
        ws.send(["type": "typing", "to_id": partner, "chat_id": chatId, "is_typing": isTyping])
    }

    func isTyping(_ chatId: String) -> Bool {
        guard let until = typing[chatId] else { return false }
        return until > Date()
    }

    // MARK: Send

    /// "Переслать": text is sent again (encrypted for the new chat); media reuses the uploaded file
    /// and its key - only the key is wrapped again for the new recipients, nothing re-uploads.
    func forward(_ m: MessageItem, to chatId: String) {
        if m.type == "text" {
            sendText(m.content, chatId: chatId, forwarded: true)
            return
        }
        guard let chat = store.chat(chatId), !m.content.isEmpty, let keyB64 = m.fileKey else { return }
        let clientId = UUID().uuidString.lowercased()
        var item = m
        item.serverId = "TEMP_\(clientId)"
        item.clientMessageId = clientId
        item.chatId = chat.id
        item.senderId = myUserId
        item.isMe = true
        item.isForwarded = true
        item.timestamp = Clock.nowMs
        item.deliveryStatus = DeliveryStatus.sending
        item.isDelivered = false
        item.isRead = false
        item.reactions = [:]
        item.replyToId = nil
        store.insert(item)
        bump()
        enqueueMedia {
            let target = chat.isGroup ? chat.id : (chat.partnerId ?? ChatIds.apiTarget(chat.id, myUserId: self.myUserId))
            do {
                let wire = try await self.encryptPayload(keyB64, chat: chat)
                let archive = chat.isCloud ? nil : await ArchiveSealer.shared.seal(type: m.type, content: keyB64)
                let request = MessageRequest(
                    content: m.content, type: m.type, clientMessageId: clientId, encryptedKey: wire.content,
                    ratchetContents: wire.ratchetContents, senderDeviceId: wire.senderDeviceId,
                    protocolVersion: wire.protocolVersion, protocolVersionSender: wire.protocolVersion,
                    groupKeyVersion: wire.groupKeyVersion, replyToId: nil, isForwarded: true,
                    thumbnail: m.thumbnail, requiresAck: nil, archive: archive)
                let sent = try await self.post(target: target, request: request, archiveType: m.type,
                                               archiveContent: keyB64, cloud: chat.isCloud)
                self.store.confirmSent(tempId: item.serverId, serverId: sent.id, isDelivered: false, isRead: false)
                self.store.setPreview(chatId: chat.id, text: ChatStore.preview(item), time: item.timestamp,
                                      senderId: self.myUserId, status: DeliveryStatus.sent, isRead: false,
                                      incrementUnread: false)
            } catch {
                AppLog.write("Forward failed: \(error.localizedDescription)")
                self.store.setStatus(item.serverId, DeliveryStatus.failed)
            }
            self.bump()
        }
    }

    /// Inline button with callback_data under a bot message (backend POST /bots/callback).
    func pressBotButton(_ m: MessageItem, data: String) async -> Bool {
        struct Body: Encodable { let messageId: String; let data: String }
        do {
            try await api.send("POST", "bots/callback", body: Body(messageId: m.serverId, data: data))
            return true
        } catch {
            AppLog.write("Bot button failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - "Ознакомлен" channel posts (backend routers/channels.py, Android ChannelAck.kt)

    /// Subscriber confirms a post that asks for it.
    func ackPost(_ m: MessageItem) async -> Bool {
        guard m.requiresAck, !m.isPending else { return false }
        struct AckStatus: Decodable { let acks: Int?; let acked: Bool? }
        do {
            let data = try await api.send("POST", "channels/\(m.chatId)/posts/\(m.serverId)/ack", body: nil)
            let status = try api.decode(AckStatus.self, from: data)
            store.setAck(m.serverId, acks: status.acks ?? m.acks + 1, acked: true)
            bump()
            return true
        } catch {
            AppLog.write("Ack failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Counts and my own "acked" for the posts on screen - survives reinstalls and second devices.
    func refreshAcks(chatId: String) async {
        let ids = store.messages(chatId).filter { $0.requiresAck && !$0.isPending }.map(\.serverId)
        guard !ids.isEmpty else { return }
        struct Body: Encodable { let messageIds: [String] }
        struct AckStatus: Decodable { let acks: Int?; let acked: Bool? }
        do {
            let data = try await api.send("POST", "channels/\(chatId)/acks", body: Body(messageIds: ids))
            let map = try api.decode([String: AckStatus].self, from: data)
            for (id, s) in map { store.setAck(id, acks: s.acks ?? 0, acked: s.acked ?? false) }
            bump()
        } catch {
            AppLog.write("Ack refresh failed: \(error.localizedDescription)")
        }
    }

    /// Admins: who confirmed and who has not yet.
    func ackReport(_ m: MessageItem) async -> AckReport? {
        do {
            let data = try await api.send("GET", "channels/\(m.chatId)/posts/\(m.serverId)/acks", body: nil)
            return try api.decode(AckReport.self, from: data)
        } catch {
            AppLog.write("Ack report failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// "Закрепить" / "Открепить" (toggle, like Android ChatRepository.pinMessage): the pin is kept
    /// on this device and the server is told too (POST /chats/{id}/pin/{message_id}, best effort).
    func pin(_ m: MessageItem, hours: Int = 24) async -> Bool {
        guard let chat = store.chat(m.chatId), !m.isPending else { return false }
        let unpinning = chat.pinnedMessageId == m.serverId
        store.setPinnedMessage(chat.id, unpinning ? nil : m.serverId)
        bump()
        let target = chat.isGroup ? chat.id : (chat.partnerId ?? "")
        struct PinBody: Encodable { let durationHours: Int }
        do {
            try await api.send("POST", "chats/\(target)/pin/\(m.serverId)", body: PinBody(durationHours: hours))
        } catch {
            AppLog.write("Pin on server failed: \(error.localizedDescription)")
        }
        return true
    }

    func unpin(chatId: String) {
        store.setPinnedMessage(chatId, nil)
        bump()
    }

    /// "Удалить у меня": only this device's copy.
    func deleteLocally(_ m: MessageItem) {
        store.delete(m.serverId)
        MediaCache.remove(messageId: m.serverId)
        store.refreshPreview(chatId: m.chatId)
        bump()
    }

    func sendText(_ text: String, chatId: String, replyTo: String? = nil, forwarded: Bool = false, requiresAck: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let chat = store.chat(chatId) else { return }
        let clientId = UUID().uuidString.lowercased()
        let now = Clock.nowMs
        let item = MessageItem(
            serverId: "TEMP_\(clientId)", clientMessageId: clientId, chatId: chat.id, senderId: myUserId, type: "text",
            content: trimmed, fileKey: nil, localPath: nil, thumbnail: nil,
            protocolVersion: chat.isCloud ? 0 : SignalService.protocolVersion, timestamp: now, isMe: true,
            deliveryStatus: DeliveryStatus.sending, isDelivered: false, isRead: false, replyToId: replyTo,
            isForwarded: forwarded, isEdited: false, editVersion: 0, ttlSeconds: 0, expiresAt: 0, unverifiedDevice: false,
            reactions: [:], requiresAck: requiresAck && chat.isChannel, acks: 0, acked: false, views: 0)
        store.insert(item)
        store.setPreview(chatId: chat.id, text: trimmed, time: now, senderId: myUserId, status: DeliveryStatus.sending,
                         isRead: false, incrementUnread: false)
        bump()
        enqueueSend { await self.deliver(item) }
    }

    func retry(_ message: MessageItem) {
        guard message.isPending, message.type == "text" else { return }
        store.setStatus(message.serverId, DeliveryStatus.sending)
        bump()
        enqueueSend { await self.deliver(message) }
    }

    private func retryPending() async {
        for m in store.pendingMessages() {
            if m.type == "text" {
                enqueueSend { await self.deliver(m) }
            } else {
                enqueueMedia { await self.deliverMedia(m) }
            }
        }
    }

    /// Encrypts (Signal fan-out, group sender key, or readable for a cloud chat) and posts.
    /// Never falls back to plaintext: a failure keeps the clock (network) or shows "!" (crypto).
    private func deliver(_ m: MessageItem) async {
        guard store.message(m.serverId) != nil else { return }  // already confirmed by an echo
        guard let chat = store.chat(m.chatId), let clientId = m.clientMessageId else { return }
        let target = chat.isGroup ? chat.id : (chat.partnerId ?? ChatIds.apiTarget(chat.id, myUserId: myUserId))
        do {
            let wire = try await encryptPayload(m.content, chat: chat)
            var request = MessageRequest(
                content: wire.content, type: "text", clientMessageId: clientId, encryptedKey: nil,
                ratchetContents: wire.ratchetContents, senderDeviceId: wire.senderDeviceId,
                protocolVersion: wire.protocolVersion, protocolVersionSender: wire.protocolVersion,
                groupKeyVersion: wire.groupKeyVersion, replyToId: m.replyToId, isForwarded: m.isForwarded,
                thumbnail: nil, requiresAck: m.requiresAck ? true : nil, archive: nil)
            if !chat.isCloud {
                request.archive = await ArchiveSealer.shared.seal(type: "text", content: m.content)
            }
            let response = try await post(target: target, request: request, archiveType: "text",
                                          archiveContent: m.content, cloud: chat.isCloud)
            store.confirmSent(tempId: m.serverId, serverId: response.id, isDelivered: response.isDelivered ?? false,
                              isRead: response.isRead ?? false, ttlSeconds: response.ttlSeconds ?? 0,
                              expiresAt: response.expiresAt.map { Dates.millis($0) } ?? 0)
            store.setPreview(chatId: chat.id, text: m.content, time: m.timestamp, senderId: myUserId,
                             status: DeliveryStatus.sent, isRead: response.isRead ?? false, incrementUnread: false)
        } catch {
            let transient = Self.isTransient(error)
            AppLog.write("Send failed (\(transient ? "will retry" : "refused")): \(error.localizedDescription)")
            store.setStatus(m.serverId, transient ? DeliveryStatus.sending : DeliveryStatus.failed)
        }
        bump()
    }

    struct WirePayload {
        var content: String
        var ratchetContents: [String: String]?
        var senderDeviceId: Int?
        var protocolVersion: Int
        var groupKeyVersion: Int?
    }

    /// Text, or a media file key, encrypted for this chat.
    func encryptPayload(_ plaintext: String, chat: ChatItem) async throws -> WirePayload {
        let myDevice = await signal.myDeviceId()
        if chat.isCloud {
            return WirePayload(content: plaintext, ratchetContents: nil, senderDeviceId: myDevice ?? 1,
                               protocolVersion: 0, groupKeyVersion: nil)
        }
        guard let myDevice else { throw SignalServiceError(message: "Signal keys are not registered yet") }
        if chat.isGroup {
            let members = store.members(chat.id) + [myUserId]
            guard try await signal.groupSupportsSignal(myUserId: myUserId, memberIds: members) else {
                throw SignalServiceError(message: "Not every group member has a Signal device")
            }
            guard let distribution = await signal.ensureOwnSenderKeyCurrent(
                myUserId: myUserId, installId: installId, chatId: chat.id, keyVersion: chat.groupKeyVersion, memberIds: members)
            else { throw URLError(.cannotConnectToHost) }  // distribution is retried on the next attempt
            let wire = try await signal.encryptForGroup(myUserId: myUserId, distributionId: distribution, plaintext: plaintext)
            return WirePayload(content: wire, ratchetContents: nil, senderDeviceId: myDevice,
                               protocolVersion: SignalService.protocolVersion, groupKeyVersion: chat.groupKeyVersion)
        }
        guard let partner = chat.partnerId else { throw SignalServiceError(message: "No partner") }
        guard try await signal.partnerSupportsSignal(partner) else {
            throw SignalServiceError(message: "This user has no Signal device yet")
        }
        let fan = try await signal.encryptForAllDevices(myUserId: myUserId, partnerId: partner, plaintext: plaintext)
        var perDevice: [String: String] = [:]
        for (device, wire) in fan.perDevice { perDevice[String(device)] = wire }
        return WirePayload(content: fan.legacy ?? fan.perDevice.values.first ?? "", ratchetContents: perDevice,
                           senderDeviceId: myDevice, protocolVersion: SignalService.protocolVersion, groupKeyVersion: nil)
    }

    /// POST with two quick retries on a flaky link (same client_message_id - the server
    /// de-duplicates), and one re-seal when the archive key was just turned on/rotated (409).
    func post(target: String, request: MessageRequest, archiveType: String, archiveContent: String,
              cloud: Bool) async throws -> APIMessage {
        var request = request
        var resealed = false
        var attempt = 0
        while true {
            do {
                let data = try await api.send("POST", "chats/\(target)/messages", body: request)
                return try api.decode(APIMessage.self, from: data)
            } catch let error as APIError where error.status == 409 && !cloud && !resealed {
                resealed = true
                await ArchiveSealer.shared.invalidate()
                request.archive = await ArchiveSealer.shared.seal(type: archiveType, content: archiveContent)
            } catch {
                attempt += 1
                guard Self.isTransient(error), attempt <= 2 else { throw error }
                try? await Task.sleep(nanoseconds: UInt64(700_000_000 * attempt))
            }
        }
    }

    static func isTransient(_ error: Error) -> Bool {
        if error is URLError { return true }
        if let api = error as? APIError {
            return api.status >= 500 || api.status == 408 || api.status == 429 || api.status == 0
        }
        return false
    }

    // MARK: Edit / delete / react

    /// PATCH /messages/{id}: the new text encrypted like a new message (Signal has no "edit").
    func edit(_ m: MessageItem, newText: String) async -> Bool {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard m.isMe, m.type == "text", !m.isPending, !text.isEmpty, let chat = store.chat(m.chatId) else { return false }
        do {
            let wire = try await encryptPayload(text, chat: chat)
            let archive = chat.isCloud ? nil : await ArchiveSealer.shared.seal(type: "text", content: text)
            let body = EditMessageRequest(content: wire.content, ratchetContents: wire.ratchetContents,
                                          senderDeviceId: wire.senderDeviceId ?? 1, protocolVersion: wire.protocolVersion,
                                          protocolVersionSender: wire.protocolVersion, archive: archive)
            let data = try await api.send("PATCH", "messages/\(m.serverId)", body: body)
            let updated = try? api.decode(APIMessage.self, from: data)
            store.applyEdit(m.serverId, content: text, editVersion: updated?.editVersion ?? (m.editVersion + 1))
            store.refreshPreview(chatId: m.chatId)
            bump()
            return true
        } catch {
            AppLog.write("Edit failed: \(error.localizedDescription)")
            return false
        }
    }

    func delete(_ m: MessageItem) async {
        if !m.isPending {
            do {
                try await api.send("DELETE", "messages/\(m.serverId)", body: nil)
            } catch {
                AppLog.write("Delete failed: \(error.localizedDescription)")
                return
            }
        }
        store.delete(m.serverId)
        MediaCache.remove(messageId: m.serverId)
        store.refreshPreview(chatId: m.chatId)
        bump()
    }

    /// A reaction is an ordinary end-to-end encrypted message of type "reaction" whose plaintext
    /// is "<target id>|<emoji>" (empty emoji = take it back) - the server learns neither.
    func react(_ m: MessageItem, emoji: String) async {
        guard !m.isPending, let chat = store.chat(m.chatId) else { return }
        let before = m.reactions[myUserId] ?? ""
        let value = before == emoji ? "" : emoji
        store.setReaction(m.serverId, userId: myUserId, emoji: value)
        bump()
        let plain = "\(m.serverId)|\(value)"
        let target = chat.isGroup ? chat.id : (chat.partnerId ?? ChatIds.apiTarget(chat.id, myUserId: myUserId))
        do {
            let wire = try await encryptPayload(plain, chat: chat)
            let request = MessageRequest(
                content: wire.content, type: "reaction", clientMessageId: UUID().uuidString.lowercased(),
                encryptedKey: nil, ratchetContents: wire.ratchetContents, senderDeviceId: wire.senderDeviceId,
                protocolVersion: wire.protocolVersion, protocolVersionSender: wire.protocolVersion,
                groupKeyVersion: wire.groupKeyVersion, replyToId: nil, isForwarded: false, thumbnail: nil,
                requiresAck: nil, archive: chat.isCloud ? nil : await ArchiveSealer.shared.seal(type: "reaction", content: plain))
            _ = try await post(target: target, request: request, archiveType: "reaction", archiveContent: plain, cloud: chat.isCloud)
        } catch {
            AppLog.write("Reaction failed: \(error.localizedDescription)")
            store.setReaction(m.serverId, userId: myUserId, emoji: before)
            bump()
        }
    }

    // MARK: Media send

    /// Photos and videos go out instantly (Android parity): the message with the Signal-wrapped
    /// file key and an encrypted mini preview is posted first, the encrypted file uploads after,
    /// then POST /messages/{id}/media fills in the URL. Voice and documents upload first.
    func sendMedia(_ data: Data, type: String, chatId: String, thumbnailJPEG: Data? = nil, replyTo: String? = nil) {
        guard let chat = store.chat(chatId) else { return }
        let clientId = UUID().uuidString.lowercased()
        let local = MediaCache.outgoingDirectory.appendingPathComponent("\(clientId).\(MediaCache.ext(for: type))")
        do {
            try data.write(to: local, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            AppLog.write("Could not stage the attachment: \(error.localizedDescription)")
            return
        }
        let key = MediaCrypto.newKey()
        let keyB64 = MediaCrypto.keyBase64(key)
        let thumbnail = thumbnailJPEG.flatMap { MediaCrypto.sealThumbnail($0, key: key) }
        let now = Clock.nowMs
        let item = MessageItem(
            serverId: "TEMP_\(clientId)", clientMessageId: clientId, chatId: chat.id, senderId: myUserId, type: type,
            content: "", fileKey: keyB64, localPath: local.path, thumbnail: thumbnail,
            protocolVersion: chat.isCloud ? 0 : SignalService.protocolVersion, timestamp: now, isMe: true,
            deliveryStatus: DeliveryStatus.sending, isDelivered: false, isRead: false, replyToId: replyTo,
            isForwarded: false, isEdited: false, editVersion: 0, ttlSeconds: 0, expiresAt: 0, unverifiedDevice: false,
            reactions: [:], requiresAck: false, acks: 0, acked: false, views: 0)
        store.insert(item)
        store.setPreview(chatId: chat.id, text: ChatStore.preview(item), time: now, senderId: myUserId,
                         status: DeliveryStatus.sending, isRead: false, incrementUnread: false)
        bump()
        enqueueMedia { await self.deliverMedia(item) }
    }

    func retryMedia(_ message: MessageItem) {
        guard message.isPending, message.type != "text" else { return }
        store.setStatus(message.serverId, DeliveryStatus.sending)
        bump()
        enqueueMedia { await self.deliverMedia(message) }
    }

    private func deliverMedia(_ m: MessageItem) async {
        guard store.message(m.serverId) != nil, let chat = store.chat(m.chatId), let clientId = m.clientMessageId,
              let keyB64 = m.fileKey, let key = MediaCrypto.key(fromBase64: keyB64), let path = m.localPath else { return }
        let target = chat.isGroup ? chat.id : (chat.partnerId ?? ChatIds.apiTarget(chat.id, myUserId: myUserId))
        let instant = m.type == "image" || m.type == "video"
        do {
            let wire = try await encryptPayload(keyB64, chat: chat)
            let archive = chat.isCloud ? nil : await ArchiveSealer.shared.seal(type: m.type, content: keyB64)
            func request(content: String, thumbnail: String?) -> MessageRequest {
                MessageRequest(content: content, type: m.type, clientMessageId: clientId, encryptedKey: wire.content,
                               ratchetContents: wire.ratchetContents, senderDeviceId: wire.senderDeviceId,
                               protocolVersion: wire.protocolVersion, protocolVersionSender: wire.protocolVersion,
                               groupKeyVersion: wire.groupKeyVersion, replyToId: m.replyToId, isForwarded: m.isForwarded,
                               thumbnail: thumbnail, requiresAck: nil, archive: archive)
            }
            var announced: APIMessage?
            if instant {
                announced = try await post(target: target, request: request(content: "", thumbnail: m.thumbnail),
                                           archiveType: m.type, archiveContent: keyB64, cloud: chat.isCloud)
            }
            var url = announced?.content ?? ""
            if url.isEmpty {
                let sealed = try MediaCrypto.encrypt(try Data(contentsOf: URL(fileURLWithPath: path)), key: key)
                url = try await MediaService.shared.upload(sealed)
            }
            let final: APIMessage
            if let announced {
                if announced.content.isEmpty {
                    do {
                        try await api.send("POST", "messages/\(announced.id)/media", body: AttachMediaRequest(content: url))
                    } catch let error as APIError where error.status == 409 {
                        // Already attached by an earlier attempt whose answer got lost.
                    }
                }
                final = announced
            } else {
                final = try await post(target: target, request: request(content: url, thumbnail: nil),
                                       archiveType: m.type, archiveContent: keyB64, cloud: chat.isCloud)
            }
            store.confirmSent(tempId: m.serverId, serverId: final.id, isDelivered: final.isDelivered ?? false,
                              isRead: final.isRead ?? false, ttlSeconds: final.ttlSeconds ?? 0,
                              expiresAt: final.expiresAt.map { Dates.millis($0) } ?? 0, content: url)
            store.setPreview(chatId: chat.id, text: ChatStore.preview(m), time: m.timestamp, senderId: myUserId,
                             status: DeliveryStatus.sent, isRead: false, incrementUnread: false)
        } catch {
            let transient = Self.isTransient(error)
            AppLog.write("Media send failed (\(transient ? "will retry" : "refused")): \(error.localizedDescription)")
            store.setStatus(m.serverId, transient ? DeliveryStatus.sending : DeliveryStatus.failed)
        }
        bump()
    }

    // MARK: Disappearing messages

    private func purgeExpired() {
        let expired = store.expiredMessages(now: Clock.nowMs)
        guard !expired.isEmpty else { return }
        for m in expired {
            store.delete(m.serverId)
            MediaCache.remove(messageId: m.serverId)
        }
        for chatId in Set(expired.map { $0.chatId }) { store.refreshPreview(chatId: chatId) }
        bump()
    }
}
