import SwiftUI

/// Inline keyboard under a bot message, like Android: rows of buttons; a callback button goes to
/// the bot (POST /bots/callback), a url button opens the link. Once one is pressed it lights up
/// and the rest dim - the question has been answered.
struct BotButtons: View {
    let message: MessageItem
    @State private var markup: BotMarkup?
    @State private var pressed: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if let markup, !markup.inlineKeyboard.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(markup.inlineKeyboard.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 4) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, button in
                                buttonView(button)
                            }
                        }
                    }
                }
                .frame(maxWidth: 300)
                .padding(.top, 2)
            }
        }
        .task(id: message.serverId) { markup = ChatStore.shared.replyMarkup(message.serverId) }
    }

    private func key(_ b: BotMarkup.Button) -> String { b.callbackData ?? b.url ?? b.text }

    private func buttonView(_ b: BotMarkup.Button) -> some View {
        let isPressed = pressed == key(b)
        let dimmed = pressed != nil && !isPressed
        return Button {
            press(b)
        } label: {
            HStack(spacing: 4) {
                Text(b.text).lineLimit(2).multilineTextAlignment(.center)
                if b.url != nil { Image(systemName: "arrow.up.right").font(.caption2) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isPressed ? Color.white : Safir.accent)
            .frame(maxWidth: .infinity, minHeight: 36)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(isPressed ? AnyShapeStyle(Safir.brandGradient) : AnyShapeStyle(Safir.surface)))
            .opacity(dimmed ? 0.45 : 1)
        }
        .buttonStyle(PressableStyle())
        .disabled(message.isPending)
    }

    private func press(_ b: BotMarkup.Button) {
        Safir.tap()
        if let link = b.url, let url = URL(string: link), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            openURL(url)
            return
        }
        guard let data = b.callbackData else { return }
        withAnimation(Safir.spring) { pressed = key(b) }
        Task {
            if !(await ChatService.shared.pressBotButton(message, data: data)) {
                withAnimation(Safir.spring) { pressed = nil }
            }
        }
    }
}
