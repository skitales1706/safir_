import SwiftUI

/// Android's Ёвар colours (EvvarAIScreen.kt).
private enum AiColors {
    static let blue = Color(hex: 0x3B82F6)
    static let violet = Color(hex: 0x8B5CF6)
    static let cyan = Color(hex: 0x22D3EE)
    static let warning = Color(hex: 0xFFB020)
    static let gradient = LinearGradient(colors: [blue, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Ёвар AI chat, like Android's EvvarAIScreen: robot in the title bar, privacy notice, welcome
/// screen with the big interactive robot and one-tap suggestions, then the conversation over a
/// faint robot that thinks while a reply is coming and waves when it arrives. POST /ai/chat runs
/// on the organisation's own server.
struct AssistantView: View {
    private struct Line: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let mine: Bool
        let time = Date()
    }

    /// Sends `prompt` right away, or puts it in the field for the user to finish.
    private struct Suggestion {
        let icon: String
        let title: String
        let prompt: String
        let sendNow: Bool
    }

    private struct Ask: Encodable { let question: String }
    private struct Answer: Decodable { let answer: String }

    private static let suggestions = [
        Suggestion(icon: "doc.plaintext", title: "Краткий пересказ", prompt: "Кратко перескажи этот текст: ", sendNow: false),
        Suggestion(icon: "character.bubble", title: "Перевод", prompt: "Переведи на таджикский: ", sendNow: false),
        Suggestion(icon: "lightbulb", title: "Совет", prompt: "Дай мне полезный совет на сегодня", sendNow: true),
        Suggestion(icon: "calendar", title: "План дня", prompt: "Составь мне план рабочего дня", sendNow: true),
    ]

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    @State private var lines: [Line] = []
    @State private var draft = ""
    @State private var thinking = false
    @FocusState private var focused: Bool

    /// Every new answer makes the robot wave.
    private var replies: Int { lines.filter { !$0.mine }.count }
    private var started: Bool { !lines.isEmpty || thinking }

    var body: some View {
        ZStack {
            Safir.background.ignoresSafeArea()
            AmbientGlow().ignoresSafeArea()
            VStack(spacing: 0) {
                privacyNotice
                ZStack {
                    if started {
                        conversation.transition(.opacity)
                    } else {
                        welcome.transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .frame(maxHeight: .infinity)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: started)
                composer
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    EvvarRobot(interactive: false, thinking: thinking, waveKey: replies)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Ёвар AI").font(.headline).foregroundStyle(Safir.text)
                        Text(thinking ? "пишет…" : "ИИ-помощник")
                            .font(.caption)
                            .foregroundStyle(thinking ? AiColors.cyan : Safir.muted)
                            .id(thinking)
                            .transition(.push(from: .bottom))
                    }
                    .animation(.easeInOut(duration: 0.25), value: thinking)
                }
            }
            if started {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(Safir.spring) { lines = [] }
                    } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("Новый разговор")
                }
            }
        }
    }

    /// Ёвар is the one feature without end-to-end encryption - always said so (as on Android).
    private var privacyNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.open").font(.caption)
            Text("У Ёвар нет сквозного шифрования — вопросы обрабатываются на сервере")
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(AiColors.warning)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AiColors.warning.opacity(0.12)))
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: Welcome

    private var welcome: some View {
        ScrollView {
            VStack(spacing: 0) {
                EvvarRobot(interactive: true)
                    .frame(width: 240, height: 240)
                    .padding(.top, 8)
                Text("Нажмите на Ёвар или проведите пальцем")
                    .font(.caption).foregroundStyle(Safir.muted.opacity(0.8))
                Text("Привет! Я Ёвар")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Safir.text)
                    .padding(.top, 10)
                    .appearIn(0)
                Text("Задайте вопрос, переведите текст или получите совет — я помогу.")
                    .font(.subheadline).foregroundStyle(Safir.muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                    .appearIn(1)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Self.suggestions.indices, id: \.self) { i in
                        suggestionCard(Self.suggestions[i]).appearIn(i + 2)
                    }
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func suggestionCard(_ s: Suggestion) -> some View {
        Button {
            Safir.tap()
            if s.sendNow {
                send(s.prompt)
            } else {
                draft = s.prompt
                focused = true
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: s.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AiColors.gradient))
                Text(s.title).font(.subheadline.weight(.semibold)).foregroundStyle(Safir.text).padding(.top, 10)
                Text(s.sendNow ? "Спросить" : "Добавьте текст").font(.caption2).foregroundStyle(Safir.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Safir.card))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(LinearGradient(colors: [AiColors.blue.opacity(0.5), Safir.separator],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        }
        .buttonStyle(CardPressStyle())
    }

    // MARK: Conversation

    private var conversation: some View {
        ZStack {
            // The robot lives behind the conversation: thinks while a reply is coming, waves on arrival.
            EvvarRobot(interactive: false, thinking: thinking, waveKey: replies)
                .frame(width: 300, height: 300)
                .opacity(0.22)
                .allowsHitTesting(false)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(lines) { line in
                            bubble(line)
                                .id(line.id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: line.mine ? .trailing : .leading)
                                        .combined(with: .opacity).combined(with: .scale(scale: 0.9)),
                                    removal: .opacity))
                        }
                        if thinking {
                            typingBubble.id("typing").transition(.move(edge: .leading).combined(with: .opacity))
                        }
                    }
                    .padding(12)
                    .animation(.spring(response: 0.4, dampingFraction: 0.78), value: lines)
                    .animation(.spring(response: 0.4, dampingFraction: 0.78), value: thinking)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: lines.count) { _, _ in
                    if let last = lines.last?.id {
                        withAnimation(Safir.spring) { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
                .onChange(of: thinking) { _, now in
                    if now { withAnimation(Safir.spring) { proxy.scrollTo("typing", anchor: .bottom) } }
                }
            }
        }
    }

    @ViewBuilder
    private func bubble(_ line: Line) -> some View {
        let time = Self.clock.string(from: line.time)
        if line.mine {
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(line.text).font(.body).foregroundStyle(.white).textSelection(.enabled)
                    HStack(spacing: 4) {
                        Text(time)
                        Image(systemName: "checkmark")
                    }
                    .font(.caption2).foregroundStyle(.white.opacity(0.75))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18,
                                                   bottomTrailingRadius: 4, topTrailingRadius: 18, style: .continuous)
                    .fill(AiColors.gradient))
                .contextMenu { copyButton(line.text) }
            }
        } else {
            HStack(alignment: .bottom, spacing: 8) {
                AssistantOrb(size: 28)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(line.text).font(.body).foregroundStyle(Safir.text).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(time).font(.caption2).foregroundStyle(Safir.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(aiBubbleShape.fill(Safir.card))
                .overlay(aiBubbleShape.stroke(Safir.separator, lineWidth: 1))
                .contextMenu { copyButton(line.text) }
                Spacer(minLength: 32)
            }
        }
    }

    private var aiBubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 4, bottomTrailingRadius: 18,
                               topTrailingRadius: 18, style: .continuous)
    }

    private func copyButton(_ text: String) -> some View {
        Button {
            UIPasteboard.general.string = text
        } label: {
            Label("Копировать", systemImage: "doc.on.doc")
        }
    }

    private var typingBubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            AssistantOrb(size: 28)
            BouncingDots()
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(aiBubbleShape.fill(Safir.card))
            Spacer()
        }
    }

    // MARK: Composer

    private var composer: some View {
        HStack(spacing: 6) {
            TextField("Спросите Ёвар…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.vertical, 8)
            Button { send(draft) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(canSend ? .white : Safir.muted)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(canSend ? AnyShapeStyle(AiColors.gradient) : AnyShapeStyle(Safir.pill)))
            }
            .buttonStyle(PressableStyle())
            .disabled(!canSend)
            .scaleEffect(canSend ? 1 : 0.75)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: canSend)
            .accessibilityLabel("Отправить")
        }
        .padding(.leading, 18).padding(.trailing, 6).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Safir.card))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .stroke(focused ? AiColors.blue : Safir.separator, lineWidth: 1))
        .animation(.easeInOut(duration: 0.2), value: focused)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        // Above the floating tab bar; with the keyboard up the bar is hidden behind it.
        .padding(.bottom, focused ? 10 : SafirTabBar.clearance)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !thinking
    }

    private func send(_ raw: String) {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !thinking else { return }
        Safir.tap()
        draft = ""
        lines.append(Line(text: question, mine: true))
        thinking = true
        Task {
            let answer = await ask(question)
            thinking = false
            Safir.tap(.soft)
            lines.append(Line(text: answer, mine: false))
        }
    }

    private func ask(_ question: String) async -> String {
        if DemoData.active {
            try? await Task.sleep(nanoseconds: 900_000_000)
            return ServicesDemo.assistantAnswer
        }
        do {
            return try await Session.shared.api.post("ai/chat", body: Ask(question: question), as: Answer.self).answer
        } catch {
            return "Не удалось связаться с Ёвар: \(error.localizedDescription)"
        }
    }
}

/// Three cyan dots hopping one after another (Android TypingBubble).
private struct BouncingDots: View {
    @State private var up = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(AiColors.cyan).frame(width: 8, height: 8)
                    .offset(y: up ? -6 : 0)
                    .animation(.easeInOut(duration: 0.35).repeatForever().delay(Double(i) * 0.15), value: up)
            }
        }
        .onAppear { up = true }
    }
}

/// Two soft violet / cyan glows drifting behind the screen.
private struct AmbientGlow: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: DemoData.active)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let p = (sin(t * .pi / 9) + 1) / 2
            Canvas { g, size in
                let r = size.width * 0.7
                let a = CGPoint(x: size.width * (0.15 + 0.3 * p), y: size.height * 0.18)
                let b = CGPoint(x: size.width * (0.9 - 0.3 * p), y: size.height * 0.55)
                g.fill(Path(ellipseIn: CGRect(x: a.x - r, y: a.y - r, width: r * 2, height: r * 2)),
                       with: .radialGradient(Gradient(colors: [AiColors.violet.opacity(0.14), .clear]),
                                             center: a, startRadius: 0, endRadius: r))
                g.fill(Path(ellipseIn: CGRect(x: b.x - r, y: b.y - r, width: r * 2, height: r * 2)),
                       with: .radialGradient(Gradient(colors: [AiColors.cyan.opacity(0.10), .clear]),
                                             center: b, startRadius: 0, endRadius: r))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Ёвар's small avatar (Android AiOrb): a cyan / blue / violet sphere that turns and breathes.
struct AssistantOrb: View {
    var size: CGFloat = 64

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: DemoData.active)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = 0.985 + 0.065 * sin(t * .pi / 1.8)
            ZStack {
                Circle()
                    .fill(AngularGradient(colors: [AiColors.cyan, AiColors.blue, AiColors.violet, AiColors.cyan],
                                          center: .center, angle: .degrees(t * 60)))
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.55), .clear],
                                         center: UnitPoint(x: 0.35, y: 0.32), startRadius: 0, endRadius: size * 0.4))
            }
            .frame(width: size * pulse, height: size * pulse)
            .frame(width: size, height: size)
            .shadow(color: AiColors.blue.opacity(0.4), radius: size * 0.15, y: size * 0.05)
        }
    }
}

/// Floating Ёвар orb above the Settings tab (Android AiFloatingButton, WhatsApp's Meta AI):
/// a gradient orb with a sparkle that pops in, turns once and breathes, then rests.
struct AiFloatingButton: View {
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var shown = DemoData.active
    @State private var spin = 0.0
    @State private var glow = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0x00C2FF).opacity(glow ? 0.4 : 0.18), .clear],
                                         center: .center, startRadius: 0, endRadius: 32))
                    .frame(width: 64, height: 64)
                Circle()
                    .fill(AngularGradient(colors: [Color(hex: 0x00C2FF), Color(hex: 0x4A5BFF),
                                                   Color(hex: 0x9B5BFF), Color(hex: 0x00C2FF)],
                                          center: .center, angle: .degrees(spin)))
                    .frame(width: 46, height: 46)
                Image(systemName: "sparkles")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)
            .background(Circle().fill(scheme == .dark ? Color(hex: 0x12223B) : .white))
            .overlay(Circle().stroke(Safir.separator, lineWidth: 0.5))
            .shadow(color: Color(hex: 0x4A5BFF).opacity(0.35), radius: 12, y: 4)
        }
        .buttonStyle(PressableStyle())
        .scaleEffect(shown ? 1 : 0.2)
        .opacity(shown ? 1 : 0)
        .onAppear {
            guard !DemoData.active else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.5)) { shown = true }
            withAnimation(.easeInOut(duration: 6)) { spin += 360 }
            withAnimation(.easeInOut(duration: 2).repeatCount(3, autoreverses: true)) { glow = true }
        }
        .accessibilityLabel("Ёвар AI")
    }
}
