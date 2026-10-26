import SwiftUI
import UIKit

/// Telegram's passcode pad: four dots that fill as you type and shake on a wrong code.
struct PasscodeEntry: View {
    let title: String
    var subtitle: String?
    var biometry: String?
    var onBiometry: (() -> Void)?
    /// Returns false for a wrong code - the dots shake and clear.
    let onComplete: (String) -> Bool

    @State private var code = ""
    @State private var shakes: CGFloat = 0
    @State private var bounce = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            Image(systemName: "lock.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Safir.brandGradient))
                .shadow(color: Safir.accent.opacity(0.35), radius: 14, y: 6)
                .symbolEffect(.bounce, value: bounce)
            Text(title)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(Safir.text)
                .padding(.top, 20)
                .contentTransition(.opacity)
            Text(subtitle ?? " ")
                .font(.footnote)
                .foregroundStyle(subtitle == nil ? .clear : Safir.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
                .padding(.horizontal, 32)
            HStack(spacing: 18) {
                ForEach(0..<Passcode.length, id: \.self) { i in
                    Circle()
                        .fill(i < code.count ? Safir.text : Color.clear)
                        .overlay(Circle().stroke(Safir.text.opacity(0.6), lineWidth: 1.5))
                        .frame(width: 14, height: 14)
                        .scaleEffect(i < code.count ? 1.15 : 1)
                        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: code.count)
                }
            }
            .modifier(Shake(animatableData: shakes))
            .padding(.top, 26)
            Spacer(minLength: 24)
            keypad
                .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity)
    }

    private var keypad: some View {
        let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]
        let letters = ["1": " ", "2": "ABC", "3": "DEF", "4": "GHI", "5": "JKL", "6": "MNO", "7": "PQRS", "8": "TUV", "9": "WXYZ"]
        return VStack(spacing: 16) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 26) {
                    ForEach(row, id: \.self) { digit in
                        KeyButton(main: digit, sub: letters[digit]) { type(digit) }
                    }
                }
            }
            HStack(spacing: 26) {
                if let biometry, let onBiometry {
                    Button(action: onBiometry) {
                        Image(systemName: biometry == "Face ID" ? "faceid" : "touchid")
                            .font(.system(size: 28))
                            .foregroundStyle(Safir.accent)
                            .frame(width: 76, height: 76)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(biometry)
                } else {
                    Color.clear.frame(width: 76, height: 76)
                }
                KeyButton(main: "0", sub: "+") { type("0") }
                Button {
                    guard !code.isEmpty else { return }
                    Safir.tap()
                    code.removeLast()
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 24))
                        .foregroundStyle(Safir.text)
                        .frame(width: 76, height: 76)
                        .opacity(code.isEmpty ? 0 : 1)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Стереть")
            }
        }
    }

    private func type(_ digit: String) {
        guard code.count < Passcode.length else { return }
        Safir.tap()
        code += digit
        guard code.count == Passcode.length else { return }
        let entered = code
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if onComplete(entered) {
                bounce += 1
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                withAnimation(.linear(duration: 0.4)) { shakes += 1 }
                code = ""
            }
        }
    }
}

private struct KeyButton: View {
    let main: String
    let sub: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(main).font(.system(size: 32, weight: .regular, design: .rounded))
                if let sub {
                    Text(sub).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(Safir.muted)
                }
            }
            .foregroundStyle(Safir.text)
            .frame(width: 76, height: 76)
            .background(Circle().fill(Safir.pill))
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(main)
    }
}

/// Keys light up while pressed, like the iOS lock screen.
private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(Circle().fill(Safir.accent.opacity(configuration.isPressed ? 0.25 : 0)))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: configuration.isPressed ? 0.05 : 0.25), value: configuration.isPressed)
    }
}

/// Side-to-side wobble for a wrong code.
private struct Shake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 12 * sin(animatableData * .pi * 4), y: 0))
    }
}

/// Covers the app until the code (or Face ID) is given.
struct PasscodeLockView: View {
    @State private var passcode = Passcode.shared
    @State private var now = Date()

    private var frozenFor: Int? {
        guard let until = passcode.lockedUntil, until > now else { return nil }
        return Int(until.timeIntervalSince(now).rounded(.up))
    }

    var body: some View {
        ZStack {
            Safir.background.ignoresSafeArea()
            PasscodeEntry(
                title: "Введите код-пароль",
                subtitle: frozenFor.map { "Слишком много попыток. Подождите \($0) с" },
                biometry: passcode.biometrics ? passcode.biometryName : nil,
                onBiometry: { Task { await AppSecurity.shared.unlock() } }
            ) { code in
                guard passcode.check(code) else {
                    now = Date()
                    return false
                }
                withAnimation(.easeOut(duration: 0.25)) { AppSecurity.shared.unlockedByPasscode() }
                return true
            }
        }
        .task {
            // Keep the "wait N s" line counting down while the pad is frozen.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                now = Date()
            }
        }
    }
}

enum PasscodeSetupMode: String, Identifiable {
    case set, change, disable
    var id: String { rawValue }
}

/// Turn on (enter + repeat), change (old, new, repeat) or turn off (old) the passcode.
struct PasscodeSetupView: View {
    let mode: PasscodeSetupMode
    @Environment(\.dismiss) private var dismiss
    @State private var stage: Stage
    @State private var first = ""
    @State private var mismatch = false

    private enum Stage { case verify, enter, confirm }

    init(mode: PasscodeSetupMode) {
        self.mode = mode
        _stage = State(initialValue: mode == .set ? .enter : .verify)
    }

    var body: some View {
        NavigationStack {
            PasscodeEntry(title: title, subtitle: subtitle) { code in
                switch stage {
                case .verify:
                    guard Passcode.shared.check(code) else { return false }
                    if mode == .disable {
                        Passcode.shared.disable()
                        Safir.tap(.medium)
                        dismiss()
                    } else {
                        advance(to: .enter)
                    }
                case .enter:
                    first = code
                    mismatch = false
                    advance(to: .confirm)
                case .confirm:
                    guard code == first else {
                        mismatch = true
                        advance(to: .enter)
                        return false
                    }
                    Passcode.shared.set(code)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
                return true
            }
            .id(stage)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .background(Safir.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
        }
        .interactiveDismissDisabled(stage == .confirm)
    }

    private func advance(to next: Stage) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { stage = next }
    }

    private var title: String {
        switch stage {
        case .verify: return "Введите текущий код"
        case .enter: return mode == .change ? "Введите новый код" : "Придумайте код-пароль"
        case .confirm: return "Повторите код-пароль"
        }
    }

    private var subtitle: String? {
        if mismatch && stage == .enter { return "Коды не совпали. Попробуйте ещё раз." }
        if stage == .enter { return "Код будет нужен, чтобы открыть Safir на этом iPhone." }
        return nil
    }
}
