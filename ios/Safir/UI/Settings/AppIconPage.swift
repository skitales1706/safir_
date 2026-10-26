import SwiftUI
import UIKit

/// "Иконка приложения" (Android AppIconPage.kt, Telegram/WhatsApp): the alternate icons built by
/// scripts/gen_ios_app_icons.py (AppIcon-<key> sets, IconPreview-<key> previews).
struct AppIconPage: View {
    private static let options: [(key: String, title: String)] = [
        ("default", "Классическая"), ("gold", "Золотая"), ("rose", "Розовая"), ("neon", "Неон"),
        ("steel", "Стальная"), ("emerald", "Изумрудная"), ("turquoise", "Бирюзовая"),
        ("silver", "Серебряная"), ("violet", "Фиолетовая"),
    ]

    @State private var current = UIApplication.shared.alternateIconName.map { String($0.dropFirst("AppIcon-".count)) } ?? "default"
    @State private var error: String?

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 14)]

    var body: some View {
        SettingsPage(title: "Иконка приложения") {
            SettingsGroup(footer: "Иконка меняется на главном экране сразу. iOS покажет короткое уведомление.") {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Self.options, id: \.key) { option in
                        card(option.key, option.title)
                    }
                }
                .padding(14)
            }
            .appearIn(0)
        }
        .alert(tr("Не получилось"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func card(_ key: String, _ title: String) -> some View {
        let on = current == key
        return Button {
            select(key)
        } label: {
            VStack(spacing: 8) {
                Image("IconPreview-\(key)")
                    .resizable().scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(on ? Safir.accent : Safir.separator, lineWidth: on ? 3 : 0.5)
                        .padding(on ? -4 : 0))
                    .scaleEffect(on ? 1.05 : 1)
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                Text(tr(title)).font(.caption.weight(on ? .semibold : .regular))
                    .foregroundStyle(on ? Safir.accent : Safir.text).lineLimit(1)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: on)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("app-icon-\(key)")
    }

    private func select(_ key: String) {
        guard key != current, UIApplication.shared.supportsAlternateIcons else { return }
        Safir.tap(.medium)
        let previous = current
        current = key
        UIApplication.shared.setAlternateIconName(key == "default" ? nil : "AppIcon-\(key)") { err in
            guard let err else { return }
            Task { @MainActor in
                current = previous
                error = err.localizedDescription
            }
        }
    }
}
