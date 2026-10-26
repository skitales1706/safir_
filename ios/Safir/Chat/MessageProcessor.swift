import Foundation

/// Cross-process lock (the app and the Notification Service Extension share one database and
/// one set of Signal sessions). A message key is single-use: without this, both processes could
/// decrypt the same message at once and one of them would fail. flock on a file in the App Group.
final class ProcessLock {
    static let shared = ProcessLock()
    private let fd: Int32

    private init() {
        let path = ((try? Database.defaultURL())?.deletingLastPathComponent().appendingPathComponent("process.lock").path)
            ?? (NSTemporaryDirectory() + "safir-process.lock")
        fd = open(path, O_CREAT | O_RDWR, 0o600)
    }

    func withLock<T>(_ body: () async throws -> T) async rethrows -> T {
        if fd >= 0 {
            while flock(fd, LOCK_EX | LOCK_NB) != 0 {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        defer { if fd >= 0 { flock(fd, LOCK_UN) } }
        return try await body()
    }
}

/// Decrypt-and-store for one incoming message - a port of Android's ChatRepository.insertMessage.
/// Shared by the app (ChatService) and the Notification Service Extension.
final class MessageProcessor {
    struct Result {
        /// The row inserted, nil when nothing new was stored (known id, echo, reaction...).
        var inserted: MessageItem?
        var chat: ChatItem?
        /// Something changed in the database (the UI should redraw).
        var changed: Bool
    }

    let myUserId: String
    let installId: String
    private let store = ChatStore.shared
    private let signal = SignalService.shared
    /// Called when a message arrives for a chat this device doesn't know yet (new group etc.).
    private let refreshChats: () async -> Void

    init(myUserId: String, installId: String, refreshChats: @escaping () async -> Void) {
        self.myUserId = myUserId.lowercased()
        self.installId = installId
        self.refreshChats = refreshChats
    }

    func incoming(from m: APIMessage, isGroup: Bool, partnerId: String?) -> IncomingMessage {
        let isMe = m.senderId.lowercased() == myUserId
        return IncomingMessage(
            id: m.id, clientMessageId: m.clientMessageId, serverChatId: m.chatId.lowercased(), isGroup: isGroup,
            partnerId: partnerId, senderId: m.senderId.lowercased(), content: m.content, encryptedKey: m.encryptedKey,
            ratchetContents: m.ratchetContents, senderDeviceId: m.senderDeviceId,
            protocolVersion: (isMe ? m.protocolVersionSender : m.protocolVersion) ?? 5, type: m.type,
            timestamp: Dates.millis(m.createdAt), isDelivered: m.isDelivered ?? false, isRead: m.isRead ?? false,
            replyToId: m.replyToId, isForwarded: m.isForwarded ?? false, editVersion: m.editVersion ?? 0,
            ttlSeconds: m.ttlSeconds ?? 0, expiresAt: m.expiresAt.map { Dates.millis($0) } ?? 0,
            thumbnail: m.thumbnail, requiresAck: m.requiresAck ?? false, acks: m.acks ?? 0, views: m.views ?? 0,
            replyMarkup: m.replyMarkup)
    }

    /// /sync response -> incoming messages, oldest first (a PreKey message must establish its
    /// session before the messages that depend on it).
    func incoming(from sync: SyncResponse) -> [IncomingMessage] {
        var items: [IncomingMessage] = []
        for m in sync.messages {
            guard let info = sync.chats[m.chatId] else { continue }
            let partner = info.isGroup ? nil : info.memberIds.map { $0.lowercased() }.first { $0 != myUserId }
            items.append(incoming(from: m, isGroup: info.isGroup, partnerId: partner))
        }
        return items.sorted { $0.timestamp < $1.timestamp }
    }

    /// The single place a Signal message is ever decrypted (message keys are single-use).
    func process(_ m: IncomingMessage, activeChatId: String?) async -> Result {
        await ProcessLock.shared.withLock {
            await processLocked(m, activeChatId: activeChatId)
        }
    }

    private func processLocked(_ m: IncomingMessage, activeChatId: String?) async -> Result {
        let me = myUserId
        let isMe = m.senderId == me
        let partner = isMe ? (m.partnerId ?? "") : m.senderId
        guard m.isGroup || !partner.isEmpty else { return Result(inserted: nil, chat: nil, changed: false) }
        let chatId = m.isGroup ? m.serverChatId : ChatIds.direct(me, partner)

        if let existing = store.message(m.id) {
            var changed = false
            if m.editVersion > existing.editVersion {
                changed = await applyEditLocked(messageId: m.id, content: m.content, ratchetContents: m.ratchetContents,
                                                senderDeviceId: m.senderDeviceId, editVersion: m.editVersion,
                                                senderId: m.senderId, isGroup: m.isGroup, serverChatId: m.serverChatId)
            }
            if existing.type != "text" && existing.content.isEmpty && !m.content.isEmpty {
                store.attachMedia(m.id, url: m.content)
                changed = true
            }
            if existing.isMe && m.isRead && !existing.isRead {
                store.markMineRead(chatId: chatId)
                changed = true
            } else if existing.isMe && m.isDelivered && !existing.isDelivered {
                store.markDelivered(m.id)
                changed = true
            }
            return Result(inserted: nil, chat: nil, changed: changed)
        }

        // Echo of my own send from THIS device: the pending row already holds the plaintext.
        if isMe, let cid = m.clientMessageId, let pending = store.message(clientId: cid) {
            if pending.isPending && m.type != "text" && m.content.isEmpty {
                return Result(inserted: nil, chat: nil, changed: false)  // media still uploading here
            }
            store.confirmSent(tempId: pending.serverId, serverId: m.id, isDelivered: m.isDelivered, isRead: m.isRead,
                              ttlSeconds: m.ttlSeconds, expiresAt: m.expiresAt)
            return Result(inserted: nil, chat: nil, changed: true)
        }

        if store.chat(chatId) == nil {
            await refreshChats()
        }
        let chat = store.chat(chatId)
        let cloud = m.protocolVersion == 0 && (chat?.isCloud ?? false)
        let myDevice = await signal.myDeviceId()
        let fromMyOtherDevice = isMe && m.senderDeviceId != nil && m.senderDeviceId != myDevice
        let deviceId = m.senderDeviceId ?? 1
        let isText = m.type == "text" || m.type == "reaction"
        var content = m.content
        var fileKey: String?
        var unverified = false

        if cloud {
            fileKey = isText ? nil : m.encryptedKey
        } else if m.protocolVersion == SignalService.protocolVersion {
            if isMe && !fromMyOtherDevice {
                // Sent from this install but not held locally (reinstall) - nothing decrypts it.
                if isText { content = Placeholder.undecryptable }
            } else {
                do {
                    let plain: String
                    if m.isGroup {
                        let wire = isText ? m.content : (m.encryptedKey ?? "")
                        plain = wire.isEmpty ? "" : try await signal.decryptGroup(
                            installId: installId, chatId: m.serverChatId, senderId: m.senderId, deviceId: deviceId, wire: wire)
                    } else {
                        let fallback = isText ? m.content : (m.encryptedKey ?? "")
                        let wire = myDevice.flatMap { m.ratchetContents?[String($0)] } ?? fallback
                        let from = fromMyOtherDevice ? me : m.senderId
                        plain = wire.isEmpty ? "" : try await signal.decrypt(from: from, deviceId: deviceId, wire: wire)
                    }
                    if isText {
                        content = plain
                    } else {
                        fileKey = plain.isEmpty ? nil : plain
                    }
                } catch {
                    AppLog.write("Decrypt failed for a message: \(error)")
                    if isText { content = Placeholder.undecryptable }
                }
                unverified = (try? await signal.isDeviceUnconfirmed(m.senderId, deviceId: deviceId)) ?? false
            }
        } else if isText {
            // No Signal envelope where one is required: server-injected, or legacy RSA.
            content = m.protocolVersion == 5 ? Placeholder.legacy : Placeholder.undecryptable
        }

        // A reaction is an ordinary Signal text "<target id>|<emoji>" folded into its target.
        if m.type == "reaction" {
            guard !(isMe && !fromMyOtherDevice), let sep = content.firstIndex(of: "|") else {
                return Result(inserted: nil, chat: chat, changed: false)
            }
            store.setReaction(String(content[..<sep]), userId: m.senderId, emoji: String(content[content.index(after: sep)...]))
            return Result(inserted: nil, chat: chat, changed: true)
        }

        let item = MessageItem(
            serverId: m.id, clientMessageId: m.clientMessageId, chatId: chatId, senderId: m.senderId, type: m.type,
            content: content, fileKey: fileKey, localPath: nil, thumbnail: m.thumbnail, protocolVersion: m.protocolVersion,
            timestamp: m.timestamp, isMe: isMe, deliveryStatus: DeliveryStatus.sent,
            isDelivered: isMe ? m.isDelivered : true, isRead: m.isRead, replyToId: m.replyToId,
            isForwarded: m.isForwarded, isEdited: m.editVersion > 0, editVersion: m.editVersion,
            ttlSeconds: m.ttlSeconds, expiresAt: m.expiresAt, unverifiedDevice: unverified, reactions: [:],
            requiresAck: m.requiresAck, acks: m.acks, acked: false, views: m.views)
        store.insert(item)
        if let markup = m.replyMarkup { store.setReplyMarkup(item.serverId, markup) }
        store.setPreview(chatId: chatId, text: ChatStore.preview(item), time: item.timestamp, senderId: item.senderId,
                         status: DeliveryStatus.sent, isRead: item.isRead, incrementUnread: !isMe && activeChatId != chatId)
        return Result(inserted: item, chat: chat, changed: true)
    }

    func applyEdit(messageId: String, content: String, ratchetContents: [String: String]?, senderDeviceId: Int?,
                   editVersion: Int, senderId: String, isGroup: Bool, serverChatId: String) async -> Bool {
        await ProcessLock.shared.withLock {
            await applyEditLocked(messageId: messageId, content: content, ratchetContents: ratchetContents,
                                  senderDeviceId: senderDeviceId, editVersion: editVersion, senderId: senderId,
                                  isGroup: isGroup, serverChatId: serverChatId)
        }
    }

    private func applyEditLocked(messageId: String, content: String, ratchetContents: [String: String]?,
                                 senderDeviceId: Int?, editVersion: Int, senderId: String, isGroup: Bool,
                                 serverChatId: String) async -> Bool {
        guard let existing = store.message(messageId), editVersion > existing.editVersion else { return false }
        let deviceId = senderDeviceId ?? 1
        let myDevice = await signal.myDeviceId()
        if existing.protocolVersion == 0 {
            store.applyEdit(messageId, content: content, editVersion: editVersion)
        } else if existing.isMe && deviceId == myDevice {
            return false  // my own edit from this device, already applied locally
        } else {
            do {
                let text: String
                if isGroup {
                    text = try await signal.decryptGroup(installId: installId, chatId: serverChatId, senderId: senderId,
                                                         deviceId: deviceId, wire: content)
                } else {
                    let wire = myDevice.flatMap { ratchetContents?[String($0)] } ?? content
                    let from = existing.isMe ? myUserId : senderId
                    text = try await signal.decrypt(from: from, deviceId: deviceId, wire: wire)
                }
                store.applyEdit(messageId, content: text, editVersion: editVersion)
            } catch {
                AppLog.write("Edit decrypt failed: \(error)")
                return false
            }
        }
        store.refreshPreview(chatId: existing.chatId)
        return true
    }
}
