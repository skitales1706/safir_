import SwiftUI

/// Telegram's settings icon colours (Android TileBlue, TileRed...).
enum Tile {
    static let blue = Color(hex: 0x3A8EF6)
    static let red = Color(hex: 0xF2555A)
    static let green = Color(hex: 0x34C759)
    static let orange = Color(hex: 0xF59A23)
    static let violet = Color(hex: 0x8E6CEF)
    static let cyan = Color(hex: 0x1EB6D6)
    static let teal = Color(hex: 0x20B2AA)
    static let pink = Color(hex: 0xEC5A9A)
    static let indigo = Color(hex: 0x5E5CE6)
    static let slate = Color(hex: 0x8E99A8)
}

/// Rounded square with the symbol. Every settings icon glows in the one Safir accent of the
/// current theme (owner's choice, 2026-10-23: not Telegram's rainbow); `color` stays only so call
/// sites keep their meaning should per-row colours ever come back.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(Safir.accent)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(Safir.accent.opacity(0.14))
            )
    }
}

/// A card of rows with an optional caps header and a footer hint (Android SettingsGroup).
struct SettingsGroup<Content: View>: View {
    var header: String?
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let header {
                Text(tr(header).uppercased())
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Safir.muted)
                    .padding(.leading, 16)
            }
            VStack(spacing: 0) { content }
                .background(Safir.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Safir.separator, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if let footer {
                Text(tr(footer))
                    .font(.footnote)
                    .foregroundStyle(Safir.muted)
                    .padding(.horizontal, 16)
            }
        }
    }
}

struct SettingsDivider: View {
    var inset: CGFloat = 58

    var body: some View {
        Rectangle().fill(Safir.separator).frame(height: 0.5).padding(.leading, inset)
    }
}

/// Icon, title (+ subtitle) and whatever goes on the right.
struct SettingsRow<Trailing: View>: View {
    let icon: String
    let color: Color
    let title: String
    var subtitle: String?
    var titleColor: Color = Safir.text
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: icon, color: color)
            VStack(alignment: .leading, spacing: 1) {
                Text(tr(title)).font(.body).foregroundStyle(titleColor).lineLimit(1)
                if let subtitle {
                    Text(tr(subtitle)).font(.footnote).foregroundStyle(Safir.muted).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

/// Grey value + chevron on the right of a row.
struct RowValue: View {
    var value: String?
    var chevron = true

    var body: some View {
        HStack(spacing: 6) {
            if let value {
                Text(tr(value)).font(.callout).foregroundStyle(Safir.muted).lineLimit(1)
                    .contentTransition(.opacity)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Safir.muted.opacity(0.6))
            }
        }
    }
}

/// Rows highlight while pressed, like table cells.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Safir.pill : Color.clear)
            .animation(.easeOut(duration: configuration.isPressed ? 0.05 : 0.3), value: configuration.isPressed)
    }
}

/// A row that opens another settings page.
struct LinkRow: View {
    let route: SettingsRoute
    let icon: String
    let color: Color
    let title: String
    var subtitle: String?
    var value: String?

    var body: some View {
        NavigationLink(value: route) {
            SettingsRow(icon: icon, color: color, title: title, subtitle: subtitle) {
                RowValue(value: value)
            }
        }
        .buttonStyle(RowPressStyle())
        .simultaneousGesture(TapGesture().onEnded { Safir.tap() })
    }
}

/// A row that runs an action.
struct ActionSettingsRow: View {
    let icon: String
    let color: Color
    let title: String
    var subtitle: String?
    var value: String?
    var chevron = false
    var titleColor: Color = Safir.text
    let action: () -> Void

    var body: some View {
        Button {
            Safir.tap()
            action()
        } label: {
            SettingsRow(icon: icon, color: color, title: title, subtitle: subtitle, titleColor: titleColor) {
                RowValue(value: value, chevron: chevron)
            }
        }
        .buttonStyle(RowPressStyle())
    }
}

struct SwitchRow: View {
    let icon: String
    let color: Color
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var enabled = true

    var body: some View {
        SettingsRow(icon: icon, color: color, title: title, subtitle: subtitle) {
            Toggle("", isOn: Binding(get: { isOn }, set: { new in
                Safir.tap()
                withAnimation(Safir.spring) { isOn = new }
            }))
            .labelsHidden()
            .tint(Safir.accent)
            .disabled(!enabled)
        }
        .opacity(enabled ? 1 : 0.5)
    }
}

/// Telegram's option list: title (+ subtitle) and a checkmark that pops in on the chosen one.
struct RadioRow: View {
    let title: String
    var subtitle: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Safir.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { action() }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(tr(title)).font(.body).foregroundStyle(Safir.text)
                    if let subtitle {
                        Text(tr(subtitle)).font(.footnote).foregroundStyle(Safir.muted)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Safir.accent)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }
}

/// A pushed settings page: scrolling cards on the app background, inline title.
struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 24) { content }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 32)
        }
        .background(Safir.background.ignoresSafeArea())
        .navigationTitle(tr(title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Safir.background, for: .navigationBar)
    }
}

/// Cards slide up and fade in one after another when a page opens.
private struct AppearIn: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 22)
            .onAppear {
                guard !shown else { return }
                if AppSettings.shared.reduceAnimations {
                    shown = true
                    return
                }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.84).delay(Double(index) * 0.05)) { shown = true }
            }
    }
}

extension View {
    func appearIn(_ index: Int) -> some View { modifier(AppearIn(index: index)) }
}

/// Short confirmation capsule that drops in from the top ("Скопировано").
struct SettingsToast: View {
    let text: String
    var icon = "checkmark.circle.fill"

    var body: some View {
        Label(tr(text), systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Safir.text)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassCapsule()
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

extension View {
    /// Shows `text` as a toast for ~1.6 s whenever it becomes non-nil.
    func settingsToast(_ text: Binding<String?>) -> some View {
        overlay(alignment: .top) {
            if let value = text.wrappedValue {
                SettingsToast(text: value)
                    .padding(.top, 6)
                    .task(id: value) {
                        try? await Task.sleep(nanoseconds: 1_600_000_000)
                        withAnimation(Safir.spring) { text.wrappedValue = nil }
                    }
            }
        }
        .animation(Safir.spring, value: text.wrappedValue)
    }
}
