import SwiftUI

/// First launch (Android OnboardingActivity): two welcome slides, then the login screen. Shown
/// once per install; screenshot/demo runs skip it.
struct OnboardingView: View {
    static var seen: Bool {
        get { DemoData.active || UserDefaults.standard.bool(forKey: "onboarding_seen") }
        set { UserDefaults.standard.set(newValue, forKey: "onboarding_seen") }
    }

    let onFinish: () -> Void
    @State private var page = 0
    @State private var appeared = false

    private struct Slide {
        let icon: String?
        let title: String
        let text: String
        let chips: [(icon: String, title: String)]
    }

    private let slides = [
        Slide(icon: nil, title: "Добро пожаловать в Safir",
              text: "Современный таджикский мессенджер — быстрый, удобный и созданный с любовью к нашей культуре.",
              chips: []),
        Slide(icon: "lock.fill", title: "Безопасно и всё в одном",
              text: "Сообщения защищены сквозным шифрованием. Создавайте группы, звоните и пользуйтесь ИИ-помощником.",
              chips: [("lock.fill", "Шифрование"), ("phone.fill", "Звонки"), ("sparkles", "Ёвар AI")]),
    ]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x05080F), Color(hex: 0x0B1D33), Color(hex: 0x06303A)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if page < slides.count - 1 {
                        Button(tr("Пропустить")) { finish() }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 20).padding(.top, 8)
                            .transition(.opacity)
                    }
                }
                .frame(height: 44)
                TabView(selection: $page) {
                    ForEach(slides.indices, id: \.self) { i in
                        slide(slides[i]).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                HStack(spacing: 8) {
                    ForEach(slides.indices, id: \.self) { i in
                        Capsule().fill(i == page ? Safir.accent : .white.opacity(0.3))
                            .frame(width: i == page ? 24 : 8, height: 8)
                    }
                }
                .padding(.bottom, 24)
                Button {
                    Safir.tap(.medium)
                    if page < slides.count - 1 {
                        withAnimation(Safir.spring) { page += 1 }
                    } else {
                        finish()
                    }
                } label: {
                    Text(tr(page < slides.count - 1 ? "Продолжить" : "Начать"))
                        .font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Capsule().fill(Safir.brandGradient))
                        .contentTransition(.opacity)
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("onboarding-next")
                .padding(.horizontal, 24).padding(.bottom, 20)
            }
        }
        .animation(Safir.spring, value: page)
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) { appeared = true } }
    }

    private func slide(_ s: Slide) -> some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().fill(Safir.accent.opacity(0.18)).frame(width: 190, height: 190).blur(radius: 30)
                if let icon = s.icon {
                    Image(systemName: icon)
                        .font(.system(size: 64, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 140, height: 140)
                        .background(Circle().fill(Safir.brandGradient))
                } else {
                    Image("IconPreview-default")
                        .resizable().scaledToFit().frame(width: 140, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                }
            }
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
            Text(tr(s.title))
                .font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(tr(s.text))
                .font(.body).foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            if !s.chips.isEmpty {
                HStack(spacing: 8) {
                    ForEach(s.chips, id: \.title) { chip in
                        Label(tr(chip.title), systemImage: chip.icon)
                            .font(.footnote.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(.white.opacity(0.12)))
                    }
                }
            }
            Spacer()
        }
    }

    private func finish() {
        Self.seen = true
        withAnimation(.easeOut(duration: 0.3)) { onFinish() }
    }
}
