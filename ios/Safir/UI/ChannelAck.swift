import SwiftUI

/// GET /channels/{id}/posts/{message_id}/acks (backend routers/channels.py).
struct AckReport: Decodable {
    struct Person: Decodable, Identifiable {
        let userId: String
        let username: String
        let fullName: String?
        let position: String?
        let department: String?
        let ackedAt: String?
        var id: String { userId }
    }
    let total: Int
    let ackedCount: Int
    let acked: [Person]
    let pending: [Person]
}

/// "Ознакомлен" channel posts, like Android's ChannelAck.kt: an order/notice every subscriber
/// confirms; the admin (or the author) sees how many did and opens the list of who has not.
struct ChannelAckBar: View {
    let message: MessageItem
    let chat: ChatItem?
    @State private var busy = false
    @State private var showReport = false

    private var isAdmin: Bool { chat?.myRole == "admin" || chat?.myRole == "owner" }

    var body: some View {
        if chat?.isChannel == true, message.requiresAck, !message.isPending {
            Group {
                if isAdmin || message.isMe {
                    chip("checkmark.circle", "Ознакомились: \(message.acks)", filled: false) { showReport = true }
                } else if message.acked {
                    chip("checkmark.seal", "Вы ознакомились", filled: false, action: nil)
                } else {
                    chip("checkmark.seal.fill", "Ознакомлен", filled: true) {
                        busy = true
                        Task {
                            if await ChatService.shared.ackPost(message) { Safir.tap(.medium) }
                            busy = false
                        }
                    }
                    .disabled(busy)
                }
            }
            .padding(.top, 2)
            .sheet(isPresented: $showReport) { AckReportView(message: message) }
        }
    }

    private func chip(_ icon: String, _ text: String, filled: Bool, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            Label(text, systemImage: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(filled ? Color.white : (action == nil ? Safir.muted : Safir.accent))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(filled ? AnyShapeStyle(Safir.brandGradient) : AnyShapeStyle(Safir.surface)))
        }
        .buttonStyle(PressableStyle())
        .allowsHitTesting(action != nil)
    }
}

/// Who confirmed (and when) and who has not yet.
struct AckReportView: View {
    let message: MessageItem
    @Environment(\.dismiss) private var dismiss
    @State private var report: AckReport?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if let report {
                    List {
                        Section {
                            Text("Ознакомились: \(report.ackedCount) из \(report.total)").font(.headline)
                        }
                        if !report.pending.isEmpty {
                            Section("Ещё не ознакомились") {
                                ForEach(report.pending) { AckPersonRow(person: $0) }
                            }
                        }
                        if !report.acked.isEmpty {
                            Section("Ознакомились") {
                                ForEach(report.acked) { AckPersonRow(person: $0) }
                            }
                        }
                    }
                } else if failed {
                    ContentUnavailableView("Ошибка сети", systemImage: "wifi.exclamationmark")
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Ознакомление")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
            .task {
                report = await ChatService.shared.ackReport(message)
                failed = report == nil
            }
        }
    }
}

private struct AckPersonRow: View {
    let person: AckReport.Person

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).lineLimit(1)
                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(Safir.muted).lineLimit(1) }
            }
            Spacer()
            if let at = person.ackedAt.flatMap(Self.time) {
                Text(at).font(.caption).foregroundStyle(Safir.muted)
            }
        }
    }

    private var name: String {
        if let full = person.fullName, !full.isEmpty { return full }
        return "@\(person.username)"
    }

    private var subtitle: String {
        [person.position, person.department].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Server time is ISO-8601 UTC ("2026-10-21T09:15:00.123456Z") -> local "dd.MM HH:mm".
    private static func time(_ iso: String) -> String? {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        guard let date = parser.date(from: String(iso.prefix(19))) else { return nil }
        let out = DateFormatter()
        out.dateFormat = "dd.MM HH:mm"
        return out.string(from: date)
    }
}
