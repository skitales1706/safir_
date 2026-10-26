import LocalAuthentication
import SwiftUI
import UserNotifications

// MARK: - Notifications

struct NotificationsPage: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = AppSettings.shared
    @State private var status: UNAuthorizationStatus?
    @State private var toast: String?

    private var allowed: Bool { status == .authorized || status == .provisional || status == .ephemeral }

    var body: some View {
        SettingsPage(title: "Уведомления") {
            systemCard.appearIn(0)

            SettingsGroup(header: "Сообщения",
                          footer: "Без текста в уведомлении видно только «Новое сообщение» — удобно, если телефон лежит на виду.") {
                SwitchRow(icon: "text.bubble.fill", color: Tile.blue, title: "Показывать текст", isOn: $settings.notifPreview)
                SettingsDivider()
                SwitchRow(icon: "speaker.wave.2.fill", color: Tile.orange, title: "Звук", isOn: $settings.notifSound)
                SettingsDivider()
                SwitchRow(icon: "app.badge.fill", color: Tile.violet, title: "В приложении",
                          subtitle: "Баннер, когда открыт другой чат", isOn: $settings.notifInApp)
            }
            .appearIn(1)

            SettingsGroup(header: "Чаты", footer: "Выключенный тип чатов приходит без звука и не включает экран.") {
                SwitchRow(icon: "person.fill", color: Tile.blue, title: "Личные чаты", isOn: $settings.notifPrivate)
                SettingsDivider()
                SwitchRow(icon: "person.3.fill", color: Tile.green, title: "Группы", isOn: $settings.notifGroups)
                SettingsDivider()
                SwitchRow(icon: "megaphone.fill", color: Tile.orange, title: "Каналы", isOn: $settings.notifChannels)
            }
            .appearIn(2)

            SettingsGroup(footer: "Отдельный чат можно сделать беззвучным свайпом по нему в списке чатов.") {
                ActionSettingsRow(icon: "arrow.counterclockwise", color: Safir.danger, title: "Сбросить настройки уведомлений",
                                  titleColor: Safir.danger) {
                    withAnimation(Safir.spring) { settings.resetNotifications() }
                    toast = "Настройки уведомлений сброшены"
                }
            }
            .appearIn(2)
        }
        .settingsToast($toast)
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
    }

    /// iOS owns the master switch - show its state and a way there.
    private var systemCard: some View {
        HStack(spacing: 14) {
            IconTile(symbol: allowed ? "bell.fill" : "bell.slash.fill", color: allowed ? Tile.green : Tile.red, size: 44)
                .symbolEffect(.bounce, value: allowed)
            VStack(alignment: .leading, spacing: 2) {
                Text(allowed ? "Уведомления включены" : "Уведомления выключены").font(.subheadline.weight(.bold))
                Text(allowed ? "Сообщения приходят, даже когда Safir закрыт." : "Включите их в настройках iPhone, чтобы не пропускать сообщения.")
                    .font(.footnote).foregroundStyle(Safir.muted)
            }
            Spacer(minLength: 4)
            Button(allowed ? "Изменить" : "Включить") { Task { await openSystemSettings() } }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(allowed ? Safir.accent : Safir.danger)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [(allowed ? Safir.online : Safir.danger).opacity(0.18), Safir.card],
                                     startPoint: .leading, endPoint: .trailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke((allowed ? Safir.online : Safir.danger).opacity(0.3), lineWidth: 1))
        .animation(Safir.spring, value: allowed)
        .opacity(status == nil ? 0 : 1)
    }

    private func refresh() async {
        let current = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        withAnimation(Safir.spring) { status = current }
    }

    private func openSystemSettings() async {
        if status == .notDetermined {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await refresh()
            return
        }
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            await UIApplication.shared.open(url)
        }
    }
}

// MARK: - Privacy & security

enum PrivacyField: String, Hashable {
    case lastSeen, avatar, messages

    var title: String {
        switch self {
        case .lastSeen: return "Время захода"
        case .avatar: return "Фото профиля"
        case .messages: return "Сообщения"
        }
    }

    var question: String {
        switch self {
        case .lastSeen: return "Кто видит время моего последнего захода"
        case .avatar: return "Кто видит моё фото профиля"
        case .messages: return "Кто может мне писать"
        }
    }

    var footer: String {
        switch self {
        case .lastSeen: return "Если скрыть время захода, вы тоже не увидите его у других — как в Telegram."
        case .avatar: return "Остальные увидят цветной кружок с вашими инициалами."
        case .messages: return "Работает с Safir Premium. Люди не из контактов не смогут начать с вами чат."
        }
    }

    var icon: String {
        switch self {
        case .lastSeen: return "clock.fill"
        case .avatar: return "person.crop.circle.fill"
        case .messages: return "bubble.left.and.text.bubble.right.fill"
        }
    }

    var color: Color {
        switch self {
        case .lastSeen: return Tile.blue
        case .avatar: return Tile.violet
        case .messages: return Tile.teal
        }
    }

    /// Server values (schemas.UserUpdate validators) and their labels.
    var options: [(value: String, title: String)] {
        switch self {
        case .lastSeen, .avatar: return [("everyone", "Все"), ("nobody", "Никто")]
        case .messages: return [("everyone", "Все"), ("contacts", "Только контакты")]
        }
    }

    func value(_ me: MyProfile?) -> String {
        switch self {
        case .lastSeen: return me?.privacyLastSeen ?? "everyone"
        case .avatar: return me?.privacyAvatar ?? "everyone"
        case .messages: return me?.privacyMessages ?? "everyone"
        }
    }

    func label(_ me: MyProfile?) -> String {
        let v = value(me)
        return options.first { $0.value == v }?.title ?? "Все"
    }

    func update(_ value: String) -> ProfileUpdate {
        switch self {
        case .lastSeen: return ProfileUpdate(privacyLastSeen: value)
        case .avatar: return ProfileUpdate(privacyAvatar: value)
        case .messages: return ProfileUpdate(privacyMessages: value)
        }
    }
}

struct PrivacyPage: View {
    @State private var profile = ProfileStore.shared
    @State private var security = AppSecurity.shared
    @State private var passcode = Passcode.shared
    @State private var setup: PasscodeSetupMode?

    private var biometry: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "код iPhone"
        }
    }

    var body: some View {
        SettingsPage(title: "Конфиденциальность") {
            EncryptionCard().appearIn(0)

            SettingsGroup(header: "Конфиденциальность",
                          footer: profile.me?.isPremium == true ? nil : "«Сообщения» и отключение отчётов о прочтении работают с Safir Premium.") {
                ForEach([PrivacyField.lastSeen, .avatar, .messages], id: \.self) { field in
                    if field != .lastSeen { SettingsDivider() }
                    LinkRow(route: .privacyChoice(field), icon: field.icon, color: field.color,
                            title: field.title, value: field.label(profile.me))
                }
                SettingsDivider()
                SwitchRow(icon: "checkmark.message.fill", color: Tile.green, title: "Отчёты о прочтении",
                          subtitle: "Собеседники видят ✓✓, когда вы прочитали",
                          isOn: Binding(get: { profile.me?.readReceipts ?? true },
                                        set: { on in Task { await profile.update(ProfileUpdate(readReceipts: on)) } }))
                SettingsDivider()
                LinkRow(route: .blocked, icon: "hand.raised.fill", color: Tile.red, title: "Заблокированные",
                        value: profile.blocked.isEmpty ? nil : "\(profile.blocked.count)")
            }
            .appearIn(1)

            SettingsGroup(header: "Безопасность", footer: securityFooter) {
                SwitchRow(icon: "lock.fill", color: Tile.green, title: "Код-пароль",
                          subtitle: passcode.isOn ? nil : "4 цифры, чтобы открыть Safir",
                          isOn: Binding(get: { passcode.isOn }, set: { setup = $0 ? .set : .disable }))
                if passcode.isOn {
                    SettingsDivider()
                    ActionSettingsRow(icon: "key.fill", color: Tile.blue, title: "Сменить код-пароль", chevron: true) {
                        setup = .change
                    }
                    SettingsDivider()
                    SettingsRow(icon: "timer", color: Tile.orange, title: "Автоблокировка") {
                        Menu {
                            Picker("Автоблокировка", selection: $passcode.autoLockMinutes) {
                                ForEach(Passcode.autoLockOptions, id: \.self) { Text(Passcode.label($0)).tag($0) }
                            }
                        } label: {
                            RowValue(value: Passcode.label(passcode.autoLockMinutes))
                        }
                    }
                    if let name = passcode.biometryName {
                        SettingsDivider()
                        SwitchRow(icon: name == "Face ID" ? "faceid" : "touchid", color: Tile.violet,
                                  title: "Открывать через \(name)", isOn: $passcode.biometrics)
                    }
                } else {
                    SettingsDivider()
                    SwitchRow(icon: "faceid", color: Tile.violet, title: "Блокировка через \(biometry)",
                              subtitle: "Без своего кода — как на iPhone",
                              isOn: Binding(get: { security.lockEnabled }, set: { security.lockEnabled = $0 }))
                }
                if let email = profile.me?.email, !email.isEmpty {
                    SettingsDivider()
                    LinkRow(route: .changePassword, icon: "key.horizontal.fill", color: Tile.red, title: "Сменить пароль",
                            subtitle: "Через код на email")
                }
                SettingsDivider()
                LinkRow(route: .devices, icon: "laptopcomputer.and.iphone", color: Tile.orange, title: "Активные сеансы")
            }
            .animation(Safir.spring, value: passcode.isOn)
            .appearIn(2)

            // Telegram's "Delete my account" / "If away for" (UI/Settings/AccountPages.swift).
            SettingsGroup(header: "Удаление аккаунта") {
                LinkRow(route: .accountTTL, icon: "hourglass", color: Tile.orange, title: "Удалить автоматически",
                        subtitle: "Если я не захожу")
                SettingsDivider()
                LinkRow(route: .deleteAccount, icon: "trash.fill", color: Tile.red, title: "Удалить аккаунт")
            }
            .appearIn(3)
        }
        .task { await profile.loadBlocked() }
        .sheet(item: $setup) { PasscodeSetupView(mode: $0) }
    }

    private var securityFooter: String? {
        if passcode.isOn {
            return "Если выйти из Safir, код спросят \(Passcode.label(passcode.autoLockMinutes).lowercased()). Забыли код — переустановите приложение и войдите заново."
        }
        return security.lockEnabled ? "Safir попросит \(biometry), когда вы вернётесь в приложение." : nil
    }
}

/// Green card that explains the end-to-end encryption.
private struct EncryptionCard: View {
    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: "lock.shield.fill", color: Safir.online, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("Сквозное шифрование").font(.subheadline.weight(.bold))
                Text("Личные чаты и группы шифруются на вашем устройстве протоколом Signal. Ключи не покидают телефон — сервер видит только шифр.")
                    .font(.footnote).foregroundStyle(Safir.muted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Safir.online.opacity(0.2), Safir.card], startPoint: .leading, endPoint: .trailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Safir.online.opacity(0.3), lineWidth: 1))
    }
}

struct PrivacyChoicePage: View {
    let field: PrivacyField
    @State private var profile = ProfileStore.shared

    var body: some View {
        let current = field.value(profile.me)
        SettingsPage(title: field.title) {
            IconTile(symbol: field.icon, color: field.color, size: 72)
                .symbolEffect(.bounce, value: current)
                .padding(.top, 8)
                .appearIn(0)

            SettingsGroup(header: field.question, footer: field.footer) {
                ForEach(Array(field.options.enumerated()), id: \.offset) { index, option in
                    if index > 0 { SettingsDivider(inset: 16) }
                    RadioRow(title: option.title, selected: current == option.value) {
                        Task { await profile.update(field.update(option.value)) }
                    }
                }
            }
            .appearIn(1)
        }
    }
}

struct BlockedPage: View {
    @State private var profile = ProfileStore.shared

    var body: some View {
        SettingsPage(title: "Заблокированные") {
            if profile.blocked.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "hand.raised.slash.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(Safir.accent.gradient)
                        .symbolEffect(.bounce, value: profile.blocked.isEmpty)
                    Text("Никого нет").font(.headline)
                    Text("Заблокированные не смогут писать и звонить вам. Заблокировать можно в профиле человека.")
                        .font(.footnote).foregroundStyle(Safir.muted).multilineTextAlignment(.center)
                }
                .padding(.top, 60)
                .padding(.horizontal, 24)
                .appearIn(0)
            } else {
                SettingsGroup(footer: "Заблокированные не могут писать и звонить вам.") {
                    ForEach(Array(profile.blocked.enumerated()), id: \.element.id) { index, user in
                        if index > 0 { SettingsDivider(inset: 66) }
                        HStack(spacing: 12) {
                            AvatarView(name: user.displayName, path: user.avatarUrl, size: 40)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(user.displayName).font(.body).lineLimit(1)
                                Text("@\(user.username)").font(.footnote).foregroundStyle(Safir.muted)
                            }
                            Spacer()
                            Button("Разблокировать") {
                                Safir.tap()
                                Task { await profile.unblock(user) }
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Safir.accent)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 60)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .appearIn(0)
            }
        }
        .task { await profile.loadBlocked() }
    }
}

// MARK: - Data & storage

struct DataStoragePage: View {
    @State private var autoload = MediaAutoload.shared
    @State private var cacheBytes: Int64 = 0
    @State private var dataBytes: Int64 = 0
    @State private var loaded = false
    @State private var confirmClear = false
    @State private var toast: String?

    private var total: Int64 { max(cacheBytes + dataBytes, 1) }

    var body: some View {
        SettingsPage(title: "Данные и память") {
            VStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Safir.pill, lineWidth: 18)
                    Circle()
                        .trim(from: 0, to: loaded ? CGFloat(dataBytes) / CGFloat(total) : 0)
                        .stroke(Safir.accent, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Circle()
                        .trim(from: loaded ? CGFloat(dataBytes) / CGFloat(total) : 0, to: loaded ? 1 : 0)
                        .stroke(Tile.orange, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .opacity(cacheBytes > 0 ? 1 : 0)
                    VStack(spacing: 2) {
                        Text(Self.format(cacheBytes + dataBytes))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("на iPhone").font(.footnote).foregroundStyle(Safir.muted)
                    }
                }
                .frame(width: 170, height: 170)
                .padding(.top, 10)

                VStack(spacing: 8) {
                    legend(Tile.orange, "Кэш медиа", cacheBytes)
                    legend(Safir.accent, "Сообщения и ключи", dataBytes)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
            .background(Safir.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Safir.separator, lineWidth: 0.5))
            .appearIn(0)

            SettingsGroup(header: "Автозагрузка через мобильную сеть") {
                SwitchRow(icon: "photo.fill", color: Tile.blue, title: "Фото", isOn: $autoload.photosCellular)
                SettingsDivider()
                SwitchRow(icon: "video.fill", color: Tile.blue, title: "Видео", isOn: $autoload.videosCellular)
            }
            .appearIn(1)

            SettingsGroup(header: "Автозагрузка через Wi‑Fi",
                          footer: "Выключенное не скачивается само — нажмите на превью, чтобы загрузить. Голосовые и файлы скачиваются всегда.") {
                SwitchRow(icon: "photo.fill", color: Tile.blue, title: "Фото", isOn: $autoload.photosWifi)
                SettingsDivider()
                SwitchRow(icon: "video.fill", color: Tile.blue, title: "Видео", isOn: $autoload.videosWifi)
            }
            .appearIn(2)

            SettingsGroup(footer: "Кэш — расшифрованные фото, видео и голосовые. После очистки они снова скачаются, когда вы их откроете. Сообщения и ключи не удаляются.") {
                ActionSettingsRow(icon: "trash.fill", color: Tile.orange, title: "Очистить кэш", value: Self.format(cacheBytes)) {
                    confirmClear = true
                }
                .disabled(cacheBytes == 0)
            }
            .appearIn(1)
        }
        .settingsToast($toast)
        .task { await measure() }
        .confirmationDialog("Удалить \(Self.format(cacheBytes)) кэша?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Очистить", role: .destructive) {
                try? FileManager.default.removeItem(at: MediaCache.directory)
                Safir.tap(.medium)
                toast = "Кэш очищен"
                Task { await measure() }
            }
        }
    }

    private func legend(_ color: Color, _ title: String, _ bytes: Int64) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(title).font(.subheadline).foregroundStyle(Safir.muted)
            Spacer()
            Text(Self.format(bytes)).font(.subheadline.weight(.semibold)).contentTransition(.numericText())
        }
    }

    private func measure() async {
        let sizes = await Task.detached(priority: .utility) { () -> (Int64, Int64) in
            let fm = FileManager.default
            let cache = Self.size(of: MediaCache.directory)
            var data = Self.size(of: fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
                + Self.size(of: fm.urls(for: .documentDirectory, in: .userDomainMask)[0])
            if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.tj.safir.messenger") {
                data += Self.size(of: group)
            }
            return (cache, data)
        }.value
        withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) {
            cacheBytes = sizes.0
            dataBytes = sizes.1
            loaded = true
        }
    }

    nonisolated private static func size(of dir: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var sum: Int64 = 0
        for case let url as URL in walker {
            sum += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return sum
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
