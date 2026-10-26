import SwiftUI

/// One row of the message menu.
struct MessageMenuItem: Identifiable {
    let title: String
    let icon: String
    var destructive = false
    let action: () -> Void

    var id: String { title }
}

/// What a long press on a bubble hands to the chat screen (Android MessageActionMenu).
struct MessageMenuRequest: Identifiable {
    let message: MessageItem
    /// The bubble's frame in global coordinates when it was pressed.
    let frame: CGRect
    /// A copy of the bubble, drawn lifted above the blurred chat.
    let preview: AnyView
    let myReaction: String?
    /// nil = no reactions for this message (still sending).
    let onReact: ((String) -> Void)?
    let items: [MessageMenuItem]

    var id: String { message.serverId }
}

/// Telegram-style message menu over the chat: the chat dims and blurs, the pressed bubble stays
/// in place (shifted only to make room), a reaction bar grows from its side with a pinned
/// chevron that opens every emoji in place, and the actions sit under it in a glass card.
struct MessageMenuOverlay: View {
    let request: MessageMenuRequest
    let onClose: () -> Void
    @State private var shown = false
    @State private var expanded = false

    static let quickReactions = ["👍", "❤️", "😂", "😮", "😢", "🙏", "🔥"]
    private let barHeight: CGFloat = 52
    private let gridHeight: CGFloat = 300
    private let rowHeight: CGFloat = 44
    private let gap: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let bubble = request.frame.offsetBy(dx: -origin.x, dy: -origin.y)
            let isMe = request.message.isMe
            let menuWidth = min(250, geo.size.width - 24)
            let topSpace = request.onReact == nil ? 0 : (expanded ? gridHeight : barHeight) + gap
            let listHeight = expanded ? 0 : CGFloat(request.items.count) * rowHeight + gap
            // The bubble keeps its place unless the bar or the list would leave the screen;
            // a very tall bubble is cut so the menu still fits (Telegram).
            let maxBubble = max(80, geo.size.height - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom - topSpace - listHeight - 24)
            let bubbleHeight = min(bubble.height, maxBubble)
            let minTop = geo.safeAreaInsets.top + 12 + topSpace
            let maxTop = geo.size.height - geo.safeAreaInsets.bottom - 12 - listHeight - bubbleHeight
            let top = shown ? min(max(bubble.minY, minTop), max(minTop, maxTop)) : bubble.minY
            let edgeX = isMe ? bubble.maxX : bubble.minX
            let listX = isMe ? min(edgeX, geo.size.width - 12) - menuWidth / 2 : max(edgeX, 12) + menuWidth / 2

            ZStack(alignment: .topLeading) {
                // Tap anywhere outside closes it.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.22))
                    .opacity(shown ? 1 : 0)
                    .ignoresSafeArea()
                    .onTapGesture { close() }

                request.preview
                    .frame(width: bubble.width, height: bubble.height, alignment: .top)
                    .frame(height: bubbleHeight, alignment: .top)
                    .clipped()
                    .allowsHitTesting(false)
                    .position(x: bubble.midX, y: top + bubbleHeight / 2)

                if let onReact = request.onReact {
                    reactionPanel(onReact, maxWidth: geo.size.width - 24)
                        .scaleEffect(shown ? 1 : 0.35, anchor: isMe ? .bottomTrailing : .bottomLeading)
                        .opacity(shown ? 1 : 0)
                        .position(x: panelX(isMe: isMe, edge: edgeX, width: geo.size.width),
                                  y: top - gap - (expanded ? gridHeight : barHeight) / 2)
                }

                if !expanded {
                    actionList
                        .frame(width: menuWidth)
                        .scaleEffect(shown ? 1 : 0.4, anchor: isMe ? .topTrailing : .topLeading)
                        .opacity(shown ? 1 : 0)
                        .position(x: listX, y: top + bubbleHeight + gap + CGFloat(request.items.count) * rowHeight / 2)
                        .transition(.opacity)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { shown = true }
        }
    }

    private var barWidth: CGFloat { CGFloat(Self.quickReactions.count) * 40 + 12 + 38 }

    /// The bar grows from the bubble's side and stays on screen.
    private func panelX(isMe: Bool, edge: CGFloat, width: CGFloat) -> CGFloat {
        let half = (expanded ? min(width - 24, 352) : min(barWidth, width - 24)) / 2
        let x = isMe ? edge - half : edge + half
        return min(max(x, 12 + half), width - 12 - half)
    }

    @ViewBuilder
    private func reactionPanel(_ onReact: @escaping (String) -> Void, maxWidth: CGFloat) -> some View {
        if expanded {
            AllReactionsGrid(current: request.myReaction) { pick($0, onReact) }
                .frame(width: min(maxWidth, 352), height: gridHeight)
                .safirGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous), rim: true)
                .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
        } else {
            HStack(spacing: 2) {
                ForEach(Array(Self.quickReactions.enumerated()), id: \.element) { index, emoji in
                    ReactionChoice(emoji: emoji, mine: emoji == request.myReaction, index: index) {
                        pick(emoji == request.myReaction ? "" : emoji, onReact)
                    }
                }
                // Pinned at the end, never scrolled away: opens every emoji in place.
                Button {
                    Safir.tap()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { expanded = true }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Safir.accent)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Safir.accent.opacity(0.18)))
                }
                .buttonStyle(PressableStyle())
                .padding(.leading, 2)
                .accessibilityLabel(tr("Все реакции"))
            }
            .padding(.horizontal, 6)
            .frame(height: barHeight)
            .safirGlass(in: Capsule(), rim: true)
            // Narrow phones: the bar shrinks a little instead of running off the screen.
            .scaleEffect(min(1, maxWidth / barWidth))
        }
    }

    private var actionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(request.items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().overlay(Safir.separator.opacity(0.5)) }
                Button {
                    Safir.tap()
                    close()
                    // After the menu is gone, so sheets and dialogs open over the chat.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { item.action() }
                } label: {
                    HStack {
                        Text(tr(item.title)).font(.body)
                        Spacer(minLength: 12)
                        Image(systemName: item.icon).font(.system(size: 17))
                    }
                    .foregroundStyle(item.destructive ? Safir.danger : Safir.text)
                    .padding(.horizontal, 16)
                    .frame(height: rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(MenuRowStyle())
            }
        }
        .safirGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), rim: true)
    }

    private func pick(_ emoji: String, _ onReact: @escaping (String) -> Void) {
        Safir.tap(.medium)
        close()
        onReact(emoji)
    }

    private func close() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { onClose() }
    }
}

/// A quick reaction: pops in one after another, grows under the finger; yours is ringed.
private struct ReactionChoice: View {
    let emoji: String
    let mine: Bool
    let index: Int
    let action: () -> Void
    @State private var appear = false

    var body: some View {
        Button(action: action) {
            AnimatedEmojiView(emoji: emoji, size: 32)
                .frame(width: 38, height: 38)
                .background(Circle().fill(mine ? Safir.accent.opacity(0.22) : .clear))
        }
        .buttonStyle(GrowStyle())
        .scaleEffect(appear ? 1 : 0.2)
        .offset(y: appear ? 0 : 10)
        .opacity(appear ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6).delay(0.03 * Double(index))) { appear = true }
        }
    }
}

/// Every emoji in a 7-column grid, the animated ones first (Telegram's expanded reactions).
struct AllReactionsGrid: View {
    let current: String?
    let onPick: (String) -> Void

    static let all: [String] = {
        let animated = AnimatedEmoji.all
        let keys = Set(animated.map(AnimatedEmoji.key))
        var seen = Set<String>()
        let rest = EmojiPanel.categories.flatMap { $0.items.map(String.init) }
            .filter { !keys.contains(AnimatedEmoji.key($0)) && seen.insert($0).inserted }
        return animated + rest
    }()

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(Self.all, id: \.self) { emoji in
                    Button { onPick(emoji == current ? "" : emoji) } label: {
                        AnimatedEmojiView(emoji: emoji, size: 34)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(Circle().fill(emoji == current ? Safir.accent.opacity(0.2) : .clear))
                    }
                    .buttonStyle(GrowStyle())
                }
            }
            .padding(8)
        }
    }
}

private struct GrowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.35 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.45), value: configuration.isPressed)
    }
}

private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Safir.text.opacity(configuration.isPressed ? 0.08 : 0))
    }
}

/// The bubble's last global frame, written on every layout change without redrawing the bubble.
final class BubbleFrame {
    var rect: CGRect = .zero
}

extension MessageBubble {
    /// The actions of the long-press menu (was the system context menu).
    var menuItems: [MessageMenuItem] {
        var items: [MessageMenuItem] = []
        if !message.isPending {
            items.append(MessageMenuItem(title: "Ответить", icon: "arrowshape.turn.up.left", action: onReply))
        }
        if message.type == "text" && !AppSecurity.shared.policy.blockCopy {
            let text = message.content
            items.append(MessageMenuItem(title: "Копировать", icon: "doc.on.doc") { UIPasteboard.general.string = text })
        }
        if message.isMe && message.type == "text" && !message.isPending {
            items.append(MessageMenuItem(title: "Изменить", icon: "pencil", action: onEdit))
        }
        if !message.isPending {
            if ChatStore.shared.chat(message.chatId)?.pinnedMessageId == message.serverId {
                items.append(MessageMenuItem(title: "Открепить", icon: "pin.slash") { onAction(.pin) })
            } else {
                items.append(MessageMenuItem(title: "Закрепить", icon: "pin") { onAction(.pin) })
            }
            if !AppSecurity.shared.policy.blockForwarding && (message.type == "text" || !message.content.isEmpty) {
                items.append(MessageMenuItem(title: "Переслать…", icon: "arrowshape.turn.up.right") { onAction(.forward) })
            }
            if message.type == "text" {
                items.append(MessageMenuItem(title: "Перевод", icon: "character.bubble") { onAction(.translate) })
            }
            if message.type == "audio" {
                items.append(MessageMenuItem(title: "Текст из голосового", icon: "text.bubble") { onAction(.transcribe) })
            }
            items.append(MessageMenuItem(title: "Выбрать", icon: "checkmark.circle") { onAction(.select) })
        }
        if message.isPending && message.deliveryStatus == DeliveryStatus.failed {
            items.append(MessageMenuItem(title: "Отправить снова", icon: "arrow.clockwise", action: onRetry))
        }
        items.append(MessageMenuItem(title: "Удалить", icon: "trash", destructive: true) { onAction(.delete) })
        return items
    }
}
