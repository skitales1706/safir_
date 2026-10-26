import PhotosUI
import SwiftUI

enum SettingsRoute: Hashable {
    case editProfile, notifications, privacy, privacyChoice(PrivacyField), blocked, data, appearance, wallpapers, language,
         devices, log, premium, saved, bots, bot(String), changePassword, folders,
         accounts, deleteAccount, accountTTL, appIcon
}

/// Settings tab - the Android/Telegram layout: profile card, then sections that open their own pages.
struct SettingsView: View {
    let user: UserDTO
    @Environment(Session.self) private var session
    @State private var router = TabRouter.shared
    @State private var profile = ProfileStore.shared
    @State private var settings = AppSettings.shared
    @State private var security = AppSecurity.shared
    @State private var toast: String?
    @State private var confirmLogout = false
    @State private var sheet: InfoSheet?

    private var me: MyProfile {
        profile.me ?? MyProfile(id: user.id, username: user.username, email: user.email, fullName: user.fullName)
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        NavigationStack(path: $router.settingsPath) {
            VStack(spacing: 0) {
                TabHeader(title: "Настройки") {
                    PillCircleButton(systemImage: "pencil") {
                        Safir.tap()
                        router.settingsPath.append(.editProfile)
                    }
                    .accessibilityIdentifier("settings-edit")
                }
                .padding(.vertical, 6)
                ScrollView { content }
                    .scrollIndicators(.hidden)
                    .tabBarClearance()
            }
            .onAppear { router.settingsRootShown = true }
            .onDisappear { router.settingsRootShown = false }
            .background(Safir.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SettingsRoute.self) { destination($0) }
            .settingsToast($toast)
        }
        .task { await profile.load(fallback: user) }
        .confirmationDialog("Выйти из аккаунта на этом iPhone?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) { Task { await session.logout() } }
        } message: {
            Text("Переписка останется на ваших других устройствах.")
        }
        .sheet(item: $sheet) { InfoSheetView(kind: $0) }
        .alert("Не получилось", isPresented: Binding(get: { profile.error != nil }, set: { if !$0 { profile.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(profile.error ?? "")
        }
    }

    private var content: some View {
        VStack(spacing: 24) {
            ProfileCard(me: me, uploading: profile.uploadingAvatar) {
                UIPasteboard.general.string = "@\(me.username)"
                toast = "Имя пользователя скопировано"
            }
            .appearIn(0)
            .scrollTransition(.interactive, axis: .vertical) { view, phase in
                view.scaleEffect(phase == .topLeading ? 0.9 : 1, anchor: .bottom)
                    .opacity(phase == .topLeading ? 0.3 : 1)
            }

            SettingsGroup(header: "Аккаунт") {
                LinkRow(route: .editProfile, icon: "person.fill", color: Tile.blue, title: me.displayName, subtitle: "Имя")
                SettingsDivider()
                LinkRow(route: .editProfile, icon: "info.circle.fill", color: Tile.violet,
                        title: (me.bio ?? "").isEmpty ? "Расскажите о себе" : me.bio ?? "", subtitle: "О себе")
                SettingsDivider()
                ActionSettingsRow(icon: "at", color: Tile.teal, title: "@\(me.username)", subtitle: "Имя пользователя") {
                    UIPasteboard.general.string = "@\(me.username)"
                    toast = "Имя пользователя скопировано"
                }
                if let email = me.email, !email.isEmpty {
                    SettingsDivider()
                    ActionSettingsRow(icon: "envelope.fill", color: Tile.orange, title: email, subtitle: "Email") {
                        toast = "Email изменить нельзя"
                    }
                }
                SettingsDivider()
                // Several accounts on this phone (Core/Accounts.swift, UI/Settings/AccountPages.swift).
                LinkRow(route: .accounts, icon: "person.2.fill", color: Tile.indigo, title: "Аккаунты",
                        value: "\(Accounts.shared.list.count)")
            }
            .appearIn(1)

            SettingsGroup {
                LinkRow(route: .saved, icon: "bookmark.fill", color: Tile.cyan, title: "Избранное",
                        subtitle: "Заметки и мысли для себя")
            }
            .appearIn(2)

            SettingsGroup {
                LinkRow(route: .notifications, icon: "bell.badge.fill", color: Tile.red, title: "Уведомления и звуки")
                SettingsDivider()
                LinkRow(route: .privacy, icon: "lock.fill", color: Tile.green, title: "Конфиденциальность",
                        value: Passcode.shared.isOn ? "Код-пароль" : (security.lockEnabled ? "Face ID" : nil))
                SettingsDivider()
                LinkRow(route: .data, icon: "chart.pie.fill", color: Tile.blue, title: "Данные и память")
                SettingsDivider()
                LinkRow(route: .appearance, icon: "paintbrush.pointed.fill", color: Tile.cyan, title: "Оформление",
                        value: settings.theme.title)
                SettingsDivider()
                LinkRow(route: .folders, icon: "folder.fill", color: Tile.blue, title: "Папки с чатами")
                SettingsDivider()
                LinkRow(route: .devices, icon: "laptopcomputer.and.iphone", color: Tile.orange, title: "Устройства")
                SettingsDivider()
                LinkRow(route: .language, icon: "globe", color: Tile.violet, title: "Язык", value: L10n.shared.name)
            }
            .appearIn(3)

            SettingsGroup {
                LinkRow(route: .premium, icon: "star.fill", color: Tile.orange, title: "Safir Premium",
                        value: me.isPremium == true ? tr("Активен") : nil)
                SettingsDivider()
                LinkRow(route: .bots, icon: "cpu.fill", color: Tile.indigo, title: "Мои боты")
            }
            .appearIn(4)

            SettingsGroup {
                ShareLink(item: "Пиши мне в Safir — защищённом мессенджере: @\(me.username)") {
                    SettingsRow(icon: "person.badge.plus", color: Tile.green, title: "Пригласить друзей",
                                subtitle: "Отправьте ссылку и ваше имя в Safir") { RowValue(chevron: false) }
                }
                .buttonStyle(RowPressStyle())
                SettingsDivider()
                ActionSettingsRow(icon: "questionmark.circle.fill", color: Tile.indigo, title: "О приложении", chevron: true) {
                    sheet = .about
                }
                SettingsDivider()
                ActionSettingsRow(icon: "doc.text.fill", color: Tile.slate, title: "Лицензии", chevron: true) {
                    sheet = .licenses
                }
                SettingsDivider()
                LinkRow(route: .log, icon: "list.bullet.rectangle.portrait.fill", color: Tile.slate, title: "Журнал")
                SettingsDivider()
                SettingsRow(icon: "sparkles", color: Tile.pink, title: "Версия") {
                    RowValue(value: Self.version, chevron: false)
                }
            }
            .appearIn(3)

            Button {
                Safir.tap(.medium)
                confirmLogout = true
            } label: {
                Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Safir.danger)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Safir.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Safir.danger.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .appearIn(4)

            Text("Safir для iOS · версия \(Self.version)")
                .font(.caption2)
                .foregroundStyle(Safir.muted)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private func destination(_ route: SettingsRoute) -> some View {
        switch route {
        case .editProfile: EditProfilePage()
        case .notifications: NotificationsPage()
        case .privacy: PrivacyPage()
        case .privacyChoice(let field): PrivacyChoicePage(field: field)
        case .blocked: BlockedPage()
        case .data: DataStoragePage()
        case .appearance: AppearancePage()
        case .appIcon: AppIconPage()
        case .wallpapers: WallpaperPage()
        case .language: LanguagePage()
        case .premium: PremiumPage()
        case .folders: FoldersPage()
        case .saved: SavedMessagesView()
        case .bots: MyBotsPage()
        case .bot(let id): BotDetailPage(botId: id)
        case .changePassword: ChangePasswordPage(email: profile.me?.email ?? user.email ?? "")
        case .devices: DevicesPage()
        case .log: LogView()
        case .accounts: AccountsPage()
        case .deleteAccount: DeleteAccountPage()
        case .accountTTL: AccountTTLPage()
        }
    }
}

/// Gradient card with the avatar (tap = new photo), name, @username and the E2E chip.
private struct ProfileCard: View {
    let me: MyProfile
    let uploading: Bool
    let onCopyUsername: () -> Void
    @State private var spin = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            AvatarPicker {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(name: me.displayName, path: me.avatarUrl, size: 96)
                        .padding(4)
                        .background(
                            Circle()
                                .stroke(AngularGradient(colors: [Color(hex: 0x1ECFEF), Safir.online, Color(hex: 0x0E7A90), Color(hex: 0x1ECFEF)],
                                                        center: .center), lineWidth: 3)
                                .rotationEffect(.degrees(spin ? 360 : 0))
                        )
                        .overlay {
                            if uploading {
                                ZStack {
                                    Circle().fill(.black.opacity(0.4)).padding(4)
                                    ProgressView().tint(.white)
                                }
                                .transition(.opacity)
                            }
                        }
                    Image(systemName: "camera.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Safir.accent))
                        .overlay(Circle().stroke(Safir.card, lineWidth: 3))
                }
            }
            .padding(.top, 22)

            HStack(spacing: 6) {
                Text(me.displayName)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Safir.text)
                    .lineLimit(1)
                if me.isPremium == true {
                    Image(systemName: "star.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFD45A), Color(hex: 0xF59A23)],
                                                        startPoint: .top, endPoint: .bottom))
                        .symbolEffect(.bounce, value: appeared)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .contentTransition(.opacity)

            Button(action: onCopyUsername) {
                Text("@\(me.username)").font(.subheadline.weight(.semibold)).foregroundStyle(Safir.accent)
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 2)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .symbolEffect(.pulse, options: .repeating, isActive: !DemoData.active)
                Text("Сквозное шифрование")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Safir.online)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Safir.online.opacity(0.14)))
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Safir.accent.opacity(0.3), Safir.card], startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Safir.separator, lineWidth: 0.5))
        .animation(Safir.spring, value: uploading)
        .onAppear {
            appeared = true
            // A forever animation keeps UI tests from going idle - still in screenshot mode.
            guard !DemoData.active, !AppSettings.shared.reduceAnimations else { return }
            withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

/// Wraps any label in a photo picker; the chosen picture becomes my avatar.
struct AvatarPicker<Label: View>: View {
    @ViewBuilder let label: () -> Label
    @State private var item: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) { label() }
            .buttonStyle(PressableStyle())
            .onChange(of: item) { _, picked in
                guard let picked else { return }
                Task {
                    if let data = try? await picked.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        await ProfileStore.shared.uploadAvatar(image)
                    }
                    item = nil
                }
            }
    }
}

/// Name and bio (PATCH /users/me), photo on top.
struct EditProfilePage: View {
    @Environment(\.dismiss) private var dismiss
    @State private var profile = ProfileStore.shared
    @State private var name = ""
    @State private var bio = ""
    @State private var saving = false
    private let maxBio = 500

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var changed: Bool {
        trimmedName != (profile.me?.fullName ?? "") || bio.trimmingCharacters(in: .whitespacesAndNewlines) != (profile.me?.bio ?? "")
    }

    var body: some View {
        SettingsPage(title: "Профиль") {
            VStack(spacing: 10) {
                AvatarPicker {
                    AvatarView(name: profile.me?.displayName ?? name, path: profile.me?.avatarUrl, size: 110)
                        .overlay {
                            if profile.uploadingAvatar {
                                ZStack {
                                    Circle().fill(.black.opacity(0.4))
                                    ProgressView().tint(.white)
                                }
                            }
                        }
                }
                AvatarPicker {
                    Text("Выбрать фотографию").font(.subheadline.weight(.semibold)).foregroundStyle(Safir.accent)
                }
            }
            .appearIn(0)

            SettingsGroup(header: "Имя", footer: "Имя видят все, кому вы пишете.") {
                TextField("Имя и фамилия", text: $name)
                    .textContentType(.name)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 50)
            }
            .appearIn(1)

            SettingsGroup(header: "О себе", footer: "Пара слов о себе: работа, город. \(bio.count)/\(maxBio)") {
                TextField("Например: учитель информатики, Исфара", text: $bio, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(16)
                    .onChange(of: bio) { _, new in
                        if new.count > maxBio { bio = String(new.prefix(maxBio)) }
                    }
            }
            .appearIn(2)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if saving {
                    ProgressView()
                } else {
                    Button("Готово") { save() }
                        .fontWeight(.semibold)
                        .disabled(!changed || trimmedName.isEmpty)
                }
            }
        }
        .onAppear {
            name = profile.me?.fullName ?? ""
            bio = profile.me?.bio ?? ""
        }
    }

    private func save() {
        saving = true
        Task {
            let ok = await profile.update(ProfileUpdate(fullName: trimmedName,
                                                        bio: bio.trimmingCharacters(in: .whitespacesAndNewlines)))
            saving = false
            if ok {
                Safir.tap(.medium)
                dismiss()
            }
        }
    }
}

enum InfoSheet: String, Identifiable {
    case about, licenses
    var id: String { rawValue }
}

/// "О приложении" and the AGPL notices (copyright, no warranty, licence, where the source is).
private struct InfoSheetView: View {
    let kind: InfoSheet
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if kind == .about {
                        SafirLogo(size: 84).padding(.top, 12)
                        Text("Safir").font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("Версия \(SettingsView.version)").font(.footnote).foregroundStyle(Safir.muted)
                        Text("Национальный мессенджер для безопасного общения. Личные чаты и группы зашифрованы сквозным шифрованием Signal — сервер не может прочитать переписку.\n\n✓ — отправлено\n✓✓ — доставлено\n✓✓ синим — прочитано")
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Создатель: Маллаев Муртазохон").font(.footnote).foregroundStyle(Safir.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(Self.licenses).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            }
            .background(Safir.background.ignoresSafeArea())
            .navigationTitle(kind == .about ? "О приложении" : "Лицензии")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
        }
        .presentationDetents(kind == .about ? [.medium, .large] : [.large])
        .presentationDragIndicator(.visible)
    }

    private static let licenses = """
    Safir — клиентское приложение. © 2026 Murtazo.

    Приложение распространяется по лицензии GNU Affero General Public License версии 3 (AGPL-3.0-only). Вы можете использовать, изучать, изменять и распространять его на условиях этой лицензии.

    Программа предоставляется «как есть», без каких-либо гарантий.

    Исходный код этой версии передаётся вместе с приложением; получить его можно у администратора вашей организации или у правообладателя.

    Текст лицензии: https://www.gnu.org/licenses/agpl-3.0.html

    Использует libsignal © Signal Messenger, LLC (AGPL-3.0-only). Signal — товарный знак Signal Messenger, LLC; Safir не связан с Signal.
    """
}
