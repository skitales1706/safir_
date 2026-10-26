import SwiftUI

/// The chat's own notifications (Telegram): on/off, mute for a while, sound and preview that
/// override Settings → Notifications. Kept in the App Group, so the Notification Service
/// Extension follows them too (NotificationPrefs.apply).
struct ChatNotificationsPage: View {
    let chat: ChatItem
    @Binding var muted: Bool
    @State private var prefs: NotificationPrefs.ChatPrefs
    @State private var sound: Bool
    @State private var preview: Bool

    private static let muteOptions: [(title: String, seconds: Double)] = [
        ("1 час", 3600), ("8 часов", 8 * 3600), ("2 дня", 2 * 86_400), ("1 неделя", 7 * 86_400),
    ]

    init(chat: ChatItem, muted: Binding<Bool>) {
        self.chat = chat
        _muted = muted
        let p = NotificationPrefs.chat(chat.id)
        _prefs = State(initialValue: p)
        _sound = State(initialValue: p.sound ?? NotificationPrefs.sound)
        _preview = State(initialValue: p.preview ?? NotificationPrefs.preview)
    }

    private var mutedForTime: Bool { prefs.mutedUntil > Date().timeIntervalSince1970 }
    private var enabled: Bool { !muted && !mutedForTime }

    var body: some View {
        SettingsPage(title: "Уведомления") {
            SettingsGroup(footer: footer) {
                SwitchRow(icon: "bell.fill", color: Safir.accent, title: "Уведомления",
                          isOn: Binding(get: { enabled }, set: { on in
                              muted = !on
                              ChatStore.shared.setChatFlags(chat.id, isMuted: !on)
                              if on { prefs.mutedUntil = 0; save() }
                          }))
                if enabled {
                    SettingsDivider()
                    SettingsRow(icon: "moon.fill", color: Safir.accent, title: "Выключить на время") {
                        Menu {
                            ForEach(Self.muteOptions, id: \.seconds) { option in
                                Button(tr(option.title)) {
                                    prefs.mutedUntil = Date().timeIntervalSince1970 + option.seconds
                                    save()
                                }
                            }
                        } label: {
                            RowValue(value: tr("Выбрать"))
                        }
                    }
                }
            }
            .appearIn(0)

            SettingsGroup(header: "В этом чате", footer: "Эти настройки важнее общих в Настройки → Уведомления.") {
                SwitchRow(icon: "speaker.wave.2.fill", color: Safir.accent, title: "Звук", isOn: $sound, enabled: enabled)
                    .onChange(of: sound) { _, value in
                        prefs.sound = value == NotificationPrefs.sound ? nil : value
                        save()
                    }
                SettingsDivider()
                SwitchRow(icon: "text.bubble.fill", color: Safir.accent, title: "Текст в уведомлении",
                          subtitle: "Имя и начало сообщения", isOn: $preview, enabled: enabled)
                    .onChange(of: preview) { _, value in
                        prefs.preview = value == NotificationPrefs.preview ? nil : value
                        save()
                    }
            }
            .appearIn(1)

            if prefs.sound != nil || prefs.preview != nil || mutedForTime {
                SettingsGroup {
                    ActionSettingsRow(icon: "arrow.counterclockwise", color: Safir.accent, title: "Как в общих настройках") {
                        withAnimation(Safir.spring) {
                            prefs = NotificationPrefs.ChatPrefs()
                            sound = NotificationPrefs.sound
                            preview = NotificationPrefs.preview
                        }
                        save()
                    }
                }
                .transition(.opacity)
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .animation(Safir.spring, value: enabled)
    }

    private var footer: String {
        if muted { return tr("Уведомления из этого чата выключены.") }
        if mutedForTime {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return tr("Выключены до %@", f.string(from: Date(timeIntervalSince1970: prefs.mutedUntil)))
        }
        return tr("Сообщения из этого чата приходят как обычно.")
    }

    private func save() {
        NotificationPrefs.setChat(chat.id, prefs)
    }
}
