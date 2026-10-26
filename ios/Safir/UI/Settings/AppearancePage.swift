import SwiftUI

/// Chat look (Android ChatSettingsPage): live preview, themes with wallpapers, colour themes,
/// light/dark, bubble colour, wallpaper gallery, text size, haptics.
struct AppearancePage: View {
    @State private var settings = AppSettings.shared
    @State private var theme = ThemeRuntime.shared
    @Namespace private var ns
    @State private var previewPreset: ThemePreset?

    var body: some View {
        SettingsPage(title: "Оформление") {
            ChatPreviewCard(fontSize: settings.fontSize)
                .appearIn(0)

            SettingsGroup(header: "Темы с обоями") {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(Array(ThemePreset.all.enumerated()), id: \.element.id) { index, preset in
                            PresetCard(preset: preset, selected: isCurrent(preset), index: index)
                                .onTapGesture {
                                    Safir.tap()
                                    previewPreset = preset
                                }
                        }
                    }
                    .padding(12)
                }
            }
            .appearIn(1)
            .fullScreenCover(item: $previewPreset) { preset in
                ChatThemePreview(preset: preset, current: theme.wallpaper) { raw, picked in
                    let p = picked ?? preset
                    ThemeSwitcher.applyNow(theme: p.theme, bubble: p.bubble, wallpaper: raw)
                }
            }

            SettingsGroup {
                LinkRow(route: .appIcon, icon: "app.badge.fill", color: Safir.accent, title: "Иконка приложения")
            }
            .appearIn(1)

            SettingsGroup(header: "Цветовая тема") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(ThemePalette.all) { palette in
                            PaletteCard(palette: palette, bubble: theme.bubble, selected: theme.themeId == palette.id, ns: ns)
                                .onTapGesture(coordinateSpace: .global) { point in
                                    guard palette.id != theme.themeId else { return }
                                    Safir.tap()
                                    ThemeSwitcher.apply(theme: palette.id, from: point)
                                }
                        }
                    }
                    .padding(12)
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: theme.themeId)
                }
                // Light/dark/system only matters for Classic - every other theme fixes its own.
                if theme.palette.scheme == nil {
                    SettingsDivider(inset: 16)
                    HStack(spacing: 10) {
                        ForEach(ThemeMode.allCases) { mode in
                            ModeCard(mode: mode, selected: settings.theme == mode)
                                .onTapGesture(coordinateSpace: .global) { point in
                                    Safir.tap()
                                    ThemeSwitcher.apply(mode, from: point)
                                }
                        }
                    }
                    .padding(12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(Safir.spring, value: theme.palette.scheme == nil)
            .appearIn(2)

            SettingsGroup(header: "Цвет сообщений") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(BubbleStyle.all) { style in
                            BubbleSwatch(style: style, selected: theme.bubbleId == style.id) {
                                Safir.tap()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { theme.bubbleId = style.id }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                }
            }
            .appearIn(3)

            SettingsGroup {
                LinkRow(route: .wallpapers, icon: "photo.on.rectangle.angled", color: Tile.green, title: "Обои",
                        value: wallpaperName)
            }
            .appearIn(4)

            SettingsGroup(header: "Размер текста", footer: "\(Int(settings.fontSize)) pt — так будут выглядеть сообщения во всех чатах.") {
                HStack(spacing: 12) {
                    Text("A").font(.system(size: 13, weight: .bold)).foregroundStyle(Safir.muted)
                    Slider(value: Binding(get: { settings.fontSize }, set: { new in
                        let rounded = new.rounded()
                        if rounded != settings.fontSize {
                            Safir.tap(.soft)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { settings.fontSize = rounded }
                        }
                    }), in: AppSettings.fontRange, step: 1)
                    .tint(Safir.accent)
                    Text("A").font(.system(size: 23, weight: .bold)).foregroundStyle(Safir.text)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
            }
            .appearIn(5)

            SettingsGroup(footer: "Лёгкий отклик на нажатия, свайпы и реакции.") {
                SwitchRow(icon: "iphone.radiowaves.left.and.right", color: Tile.pink, title: "Вибрация при нажатии",
                          isOn: $settings.haptics)
            }
            .appearIn(6)

            SettingsGroup(footer: "Без декоративных анимаций — дольше держит батарея. Включается и сам, когда на iPhone режим энергосбережения.") {
                SwitchRow(icon: "battery.75percent", color: Tile.green, title: "Экономия энергии", isOn: $settings.powerSaving)
            }
            .appearIn(7)
        }
    }

    private func isCurrent(_ preset: ThemePreset) -> Bool {
        theme.themeId == preset.theme && theme.bubbleId == preset.bubble
            && WallpaperChoice(theme.wallpaper).imageKey == preset.imageKey
    }

    private var wallpaperName: String {
        switch WallpaperChoice(theme.wallpaper) {
        case .classic: return "Классика"
        case .none: return "Нет"
        case .photo: return "Своё фото"
        case .image(let spec): return spec.theme.name
        }
    }
}

/// A tiny chat on the current wallpaper with both bubble kinds at the chosen size and colour.
private struct ChatPreviewCard: View {
    let fontSize: Double

    var body: some View {
        VStack(spacing: 8) {
            bubbleView("Салом! Как тебе новая тема? 🙂", time: "10:41", isMe: false)
            bubbleView("Очень красиво, как в Telegram!", time: "10:42", isMe: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 190)
        .background(ChatWallpaper())
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Safir.separator, lineWidth: 0.5))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: fontSize)
    }

    private func bubbleView(_ text: String, time: String, isMe: Bool) -> some View {
        HStack {
            if isMe { Spacer(minLength: 40) }
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(text).font(.system(size: fontSize)).foregroundStyle(Safir.text)
                HStack(spacing: 2) {
                    Text(time)
                    if isMe { DoubleTick().foregroundStyle(Safir.accent) }
                }
                .font(.system(size: 11))
                .foregroundStyle(isMe ? Safir.metaOut : Safir.metaIn)
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(
                BubbleShape(isMe: isMe, tail: true)
                    .fill(isMe
                          ? AnyShapeStyle(LinearGradient(colors: [Safir.bubbleOut, Safir.bubbleOutDeep], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Safir.bubbleIn))
                    .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
            )
            .transition(.opacity)
            if !isMe { Spacer(minLength: 40) }
        }
    }
}

/// Telegram's theme-with-wallpaper card (Android PresetCard): the picture, a miniature chat in the
/// theme's own bubble colours, the emoji at the bottom; cards cascade in when the page opens.
private struct PresetCard: View {
    let preset: ThemePreset
    let selected: Bool
    let index: Int
    @State private var shown = false

    var body: some View {
        let palette = ThemePalette.find(preset.theme)
        let bubble = BubbleStyle.style(preset.bubble)
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(spacing: 6) {
            ZStack {
                ImageThemeWallpaper(spec: ImageThemeSpec(theme: preset.image), thumbnail: true)
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 7).fill(Color(hex: palette.preview[2])).frame(width: 64, height: 17)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: bubble.swatch, startPoint: .top, endPoint: .bottom))
                        .frame(width: 56, height: 17)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    RoundedRectangle(cornerRadius: 8).fill(Color(hex: palette.preview[2])).frame(width: 46, height: 17)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9).padding(.top, 16)
                Text(preset.emoji).font(.system(size: 32))
                    .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color(hex: palette.preview[3])))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(5)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }
            }
            .frame(width: 118, height: 176)
            .clipShape(shape)
            .overlay(shape.stroke(selected ? Color(hex: palette.preview[3]) : .clear, lineWidth: 2.5))
            .shadow(color: Color(hex: palette.preview[3]).opacity(selected ? 0.45 : 0.12), radius: selected ? 10 : 3, y: 2)
            .scaleEffect(selected ? 1 : 0.95)
            Text(tr(preset.name))
                .font(.caption.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Safir.text : Safir.muted)
                .lineLimit(1)
                .frame(width: 118)
        }
        .scaleEffect(shown ? 1 : 0.8)
        .opacity(shown ? 1 : 0)
        .onAppear {
            guard !shown else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.03 * Double(min(index, 8)))) { shown = true }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: selected)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Mini screen in a colour theme's colours; the accent ring slides to the chosen one.
private struct PaletteCard: View {
    let palette: ThemePalette
    let bubble: BubbleStyle
    let selected: Bool
    let ns: Namespace.ID

    var body: some View {
        let p = palette.preview
        VStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle().fill(Color(hex: p[1])).frame(height: 16)
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(Color(hex: p[2])).frame(width: 40, height: 12)
                    Capsule().fill(LinearGradient(colors: bubble.swatch, startPoint: .top, endPoint: .bottom))
                        .frame(width: 34, height: 12)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Capsule().fill(Color(hex: p[2])).frame(width: 28, height: 12)
                }
                .padding(8)
                Spacer(minLength: 0)
            }
            .frame(width: 78, height: 100)
            .background(Color(hex: p[0]))
            .overlay(alignment: .bottomTrailing) {
                Circle().fill(Color(hex: p[3])).frame(width: 14, height: 14).padding(7)
            }
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .padding(3)
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Safir.accent, lineWidth: 2.5)
                        .matchedGeometryEffect(id: "palette-ring", in: ns)
                } else {
                    RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Safir.separator, lineWidth: 1)
                }
            }
            .scaleEffect(selected ? 1 : 0.94)
            Text(tr(palette.name))
                .font(.caption.weight(selected ? .bold : .medium))
                .foregroundStyle(selected ? Safir.accent : Safir.muted)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Системная / Светлая / Тёмная for the Classic theme.
private struct ModeCard: View {
    let mode: ThemeMode
    let selected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if mode == .system {
                    HStack(spacing: 0) {
                        preview(dark: false)
                        preview(dark: true)
                    }
                } else {
                    preview(dark: mode == .dark)
                }
            }
            .frame(height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(selected ? Safir.accent : Safir.separator, lineWidth: selected ? 2.5 : 1))
            .scaleEffect(selected ? 1 : 0.95)
            HStack(spacing: 4) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").transition(.scale.combined(with: .opacity))
                }
                Text(tr(mode.title))
            }
            .font(.caption.weight(selected ? .bold : .medium))
            .foregroundStyle(selected ? Safir.accent : Safir.muted)
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: selected)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func preview(dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Capsule().fill(Color(hex: dark ? 0x172A40 : 0xFFFFFF)).frame(width: 30, height: 10)
            Capsule().fill(Color(hex: dark ? 0x14566A : 0xD5F3F8)).frame(width: 26, height: 10)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: dark ? 0x050E1D : 0xF4F7FA))
    }
}

private struct BubbleSwatch: View {
    let style: BubbleStyle
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Circle()
                    .fill(LinearGradient(colors: style.swatch, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 42, height: 42)
                    .overlay {
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .transition(.scale(scale: 0.2).combined(with: .opacity))
                        }
                    }
                    .padding(4)
                    .overlay(Circle().stroke(selected ? style.swatch[0] : .clear, lineWidth: 2.5))
                    .scaleEffect(selected ? 1 : 0.86)
                Text(tr(style.name))
                    .font(.caption2.weight(selected ? .bold : .regular))
                    .foregroundStyle(selected ? Safir.text : Safir.muted)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr(style.name))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Telegram's language list: the native name, the English one under it; applies in place.
struct LanguagePage: View {
    @State private var l10n = L10n.shared

    var body: some View {
        SettingsPage(title: "Язык") {
            IconTile(symbol: "globe", color: Tile.violet, size: 72)
                .symbolEffect(.bounce, value: l10n.lang)
                .padding(.top, 8)
                .appearIn(0)

            SettingsGroup(header: "Язык приложения", footer: "Системные окна iOS сменят язык после перезапуска Safir.") {
                ForEach(Array(L10n.languages.enumerated()), id: \.offset) { index, language in
                    if index > 0 { SettingsDivider(inset: 16) }
                    RadioRow(title: language.name, subtitle: language.english, selected: l10n.lang == language.code) {
                        l10n.lang = language.code
                    }
                }
            }
            .appearIn(1)
        }
    }
}
