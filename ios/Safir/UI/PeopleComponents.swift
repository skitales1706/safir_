import SwiftUI

extension APIUser {
    var displayName: String {
        if let name = fullName, !name.isEmpty { return name }
        return username
    }

    /// "в сети" / "был(а) вчера" / "@username" under a name.
    var statusText: String {
        if isOnline == true { return "в сети" }
        if lastSeen != nil { return TimeText.lastSeen(lastSeen) }
        return "@\(username)"
    }
}

/// GET /users?query= - people on the server by name or @username (min. 2 characters).
@MainActor
enum PeopleSearch {
    static func find(_ raw: String) async throws -> [APIUser] {
        let q = raw.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard q.count >= 2 else { return [] }
        let me = ChatService.shared.myUserId
        let found = try await Session.shared.api.get("users", query: ["query": q], as: [APIUser].self)
        return found.filter { $0.id.lowercased() != me && $0.isBot != true }
    }
}

/// Big rounded title of a tab (as on the chat list), optional subtitle and pill buttons.
struct TabHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(Safir.text)
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(Safir.muted)
                        .contentTransition(.numericText())
                }
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
    }
}

/// The search capsule of the chat list, reusable.
struct SearchCapsule: View {
    @Binding var text: String
    var prompt = "Поиск"
    var busy = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Safir.muted)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if busy {
                ProgressView().controlSize(.small).tint(Safir.accent)
            }
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Safir.muted) }
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14).frame(height: 42)
        .background(Capsule().fill(Safir.pill))
        .padding(.horizontal, 16)
        .animation(Safir.spring, value: text.isEmpty)
    }
}

/// Telegram's action rows ("New group", "New channel"...): icon and label in the accent colour.
struct ActionRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionRowLabel(icon: icon, title: title)
        }
        .buttonStyle(.plain)
    }
}

struct ActionRowLabel: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(Safir.accent)
                .frame(width: 42, height: 42)
            Text(title).font(.body).foregroundStyle(Safir.accent)
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

/// Avatar with the online dot, name and status line.
struct ContactRow<Trailing: View>: View {
    let user: APIUser
    var size: CGFloat = 46
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(name: user.displayName, path: user.avatarUrl, size: size)
                .overlay(alignment: .bottomTrailing) {
                    if user.isOnline == true {
                        Circle().fill(Safir.online).frame(width: 13, height: 13)
                            .overlay(Circle().stroke(Safir.background, lineWidth: 2.5))
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName).font(.body.weight(.semibold)).foregroundStyle(Safir.text).lineLimit(1)
                Text(user.statusText).font(.subheadline)
                    .foregroundStyle(user.isOnline == true ? Safir.accent : Safir.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

extension ContactRow where Trailing == EmptyView {
    init(user: APIUser, size: CGFloat = 46) {
        self.init(user: user, size: size) { EmptyView() }
    }
}

/// Round check mark of the member pickers.
struct SelectionMark: View {
    let selected: Bool

    var body: some View {
        ZStack {
            Circle().stroke(selected ? Color.clear : Safir.muted.opacity(0.6), lineWidth: 1.5)
            if selected {
                Circle().fill(Safir.accent)
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: selected)
    }
}

/// Icon, title and hint in the middle of an empty list.
struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String?

    @State private var shown = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Safir.accent)
                .frame(width: 96, height: 96)
                .background(Circle().fill(Safir.accent.opacity(0.12)))
                .scaleEffect(shown ? 1 : 0.7)
            Text(title).font(.headline).foregroundStyle(Safir.text)
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(Safir.muted).multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { shown = true } }
    }
}

/// Section caption in accent colour ("Контакты", "Глобальный поиск").
struct SectionCaption: View {
    let text: String

    var body: some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(Safir.accent)
            .textCase(nil)
    }
}
