import SwiftUI

/// Actions from a message's long-press menu that ChatView handles (Android QuickActions).
enum BubbleAction {
    case forward, pin, select, translate, transcribe, delete, openContact
}

/// "Переслать…" (Android ForwardSheet): search a chat, optional comment, send.
struct ForwardSheet: View {
    let messages: [MessageItem]
    /// Chat the messages come from - shown on items saved to Избранное.
    var sourceTitle = ""
    let onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var comment = ""
    @State private var picked: String?

    private var chats: [ChatItem] {
        let q = query.lowercased()
        return ChatStore.shared.chats().filter { !($0.isChannel && $0.myRole == "member") }
            .filter { q.isEmpty || $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    // Избранное first, like Android's forward picker: kept on this phone only.
                    if query.isEmpty {
                        Button {
                            Safir.tap(.medium)
                            Task {
                                let ok = await SavedStore.shared.save(messages, source: sourceTitle)
                                let note = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !note.isEmpty { SavedStore.shared.addNote(note) }
                                if ok { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                                dismiss()
                                onDone("")
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "bookmark.fill").font(.system(size: 19)).foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Circle().fill(Safir.brandGradient))
                                VStack(alignment: .leading) {
                                    Text("Избранное").font(.body.weight(.semibold)).foregroundStyle(Safir.text)
                                    Text("Только на этом телефоне").font(.caption).foregroundStyle(Safir.muted)
                                }
                            }
                        }
                        .listRowBackground(Safir.background)
                    }
                    ForEach(chats) { chat in
                    Button {
                        Safir.tap()
                        withAnimation(Safir.spring) { picked = picked == chat.id ? nil : chat.id }
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(name: chat.name, path: chat.avatarUrl, size: 44)
                            VStack(alignment: .leading) {
                                Text(chat.name).font(.body.weight(.semibold)).foregroundStyle(Safir.text)
                                Text(chat.isChannel ? "Канал" : chat.isGroup ? "Группа" : "Личный чат")
                                    .font(.caption).foregroundStyle(Safir.muted)
                            }
                            Spacer()
                            Image(systemName: picked == chat.id ? "checkmark.circle.fill" : "circle")
                                .font(.title3).foregroundStyle(picked == chat.id ? Safir.accent : Safir.muted)
                        }
                    }
                    .listRowBackground(Safir.background)
                    }
                }
                .listStyle(.plain)
                .searchable(text: $query, prompt: "Поиск…")
                if let picked {
                    HStack(spacing: 8) {
                        TextField("Добавьте комментарий…", text: $comment)
                            .padding(.horizontal, 14).frame(height: 42)
                            .background(Capsule().fill(Safir.pill))
                        Button {
                            send(to: picked)
                        } label: {
                            Image(systemName: "paperplane.fill").foregroundStyle(.white)
                                .frame(width: 42, height: 42).background(Circle().fill(Safir.brandGradient))
                        }
                        .buttonStyle(PressableStyle())
                    }
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .background(Safir.background)
            .navigationTitle("Переслать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
        }
    }

    private func send(to chatId: String) {
        let service = ChatService.shared
        for m in messages.sorted(by: { $0.timestamp < $1.timestamp }) {
            service.forward(m, to: chatId)
        }
        let note = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { service.sendText(note, chatId: chatId) }
        Safir.tap(.medium)
        dismiss()
        onDone(chatId)
    }
}

/// Pinned message under the header (glass capsule); tap jumps to it.
struct PinnedBar: View {
    let message: MessageItem
    let onTap: () -> Void
    var onUnpin: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 1.5).fill(Safir.accent).frame(width: 3, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Закреплённое сообщение").font(.caption.weight(.semibold)).foregroundStyle(Safir.accent)
                        Text(ChatStore.preview(message)).font(.caption).lineLimit(1).foregroundStyle(Safir.text)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let onUnpin {
                Button {
                    Safir.tap(.medium)
                    onUnpin()
                } label: {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Safir.muted)
                        .frame(width: 30, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(Text("Открепить"))
            } else {
                Image(systemName: "pin.fill").font(.caption).foregroundStyle(Safir.muted)
            }
        }
        .padding(.leading, 14).padding(.trailing, 8).frame(height: 46)
        .safirGlass(in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
        .padding(.horizontal, 10)
    }
}

/// Voice-to-text and chat summary (backend /ai/transcribe, /ai/summarize; on-prem models). Like
/// translate, the decrypted audio/text leaves the phone only when the user asks.
enum AiTools {
    private struct Transcript: Decodable { let text: String }
    private struct SummaryLine: Encodable { let sender: String; let text: String }
    private struct SummaryRequest: Encodable { let messages: [SummaryLine]; let target: String }
    private struct Summary: Decodable { let summary: String }

    /// The app's language for AI answers: tg / ru / en.
    @MainActor
    static var target: String {
        let id = L10n.shared.locale.identifier
        return id.hasPrefix("tg") ? "tg" : id.hasPrefix("en") ? "en" : "ru"
    }

    @MainActor
    static func transcribe(_ file: URL) async -> String? {
        guard let audio = try? Data(contentsOf: file) else { return nil }
        let api = Session.shared.api
        let boundary = "safir-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"language\"\r\n\r\nauto\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"voice.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        var request = URLRequest(url: api.url("ai/transcribe"))
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        do {
            return try api.decode(Transcript.self, from: try await api.perform(request)).text
        } catch {
            AppLog.write("Transcribe failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// The last text messages of a chat (stickers and media left out), oldest first.
    @MainActor
    static func summarize(chatId: String) async -> String? {
        let me = ChatService.shared.myUserId
        let lines = ChatStore.shared.messages(chatId, limit: 300)
            .filter { $0.type == "text" && !$0.content.isEmpty && StickerDef.from(content: $0.content) == nil }
            .suffix(300)
            .map { SummaryLine(sender: $0.senderId == me ? "Я" : ChatStore.shared.displayName($0.senderId),
                               text: String($0.content.prefix(4000))) }
        guard !lines.isEmpty else { return nil }
        do {
            return try await Session.shared.api.post("ai/summarize", body: SummaryRequest(messages: Array(lines), target: target),
                                                     as: Summary.self).summary
        } catch {
            AppLog.write("Summary failed: \(error.localizedDescription)")
            return nil
        }
    }
}

/// "Тарҷума" - backend /ai/translate (on-prem model); the text leaves the phone only on request.
enum Translator {
    private struct Request: Encodable { let text: String; let target: String }
    private struct Response: Decodable { let translation: String }

    @MainActor
    static func translate(_ text: String, to target: String = "ru") async -> String? {
        try? await Session.shared.api.post("ai/translate", body: Request(text: text, target: target), as: Response.self).translation
    }
}
