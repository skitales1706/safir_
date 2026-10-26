import SwiftUI

/// Telegram / WhatsApp-style preview (Android ChatThemePreview.kt): the picture full screen behind
/// a sample chat, a glass panel with the other choices, brightness (dimming) and blur, then
/// Отмена / Применить. Nothing is saved until Применить. With a preset it previews whole themes:
/// the sample chat is drawn in that theme's own colours and bubbles, and the strip lists themes.
struct ChatThemePreview: View {
    /// The picked raw wallpaper ("theme:<key>?dim=..&blur=..") and, for a whole theme, its preset.
    let onApply: (String, ThemePreset?) -> Void
    private let presetMode: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemScheme
    @State private var picture: ImageChatTheme
    @State private var preset: ThemePreset?
    @State private var dim: Double
    @State private var blur: Bool
    @State private var lastStep = -1

    init(picture: ImageChatTheme, current: String, onApply: @escaping (String, ThemePreset?) -> Void) {
        self.init(picture: picture, preset: nil, current: current, onApply: onApply)
    }

    init(preset: ThemePreset, current: String, onApply: @escaping (String, ThemePreset?) -> Void) {
        self.init(picture: preset.image, preset: preset, current: current, onApply: onApply)
    }

    private init(picture: ImageChatTheme, preset: ThemePreset?, current: String, onApply: @escaping (String, ThemePreset?) -> Void) {
        self.onApply = onApply
        presetMode = preset != nil
        _picture = State(initialValue: picture)
        _preset = State(initialValue: preset)
        // Keep the dimming / blur when re-opening the picture already in use.
        let saved = ImageThemeSpec(raw: current)
        let same = saved?.theme.key == picture.key
        _dim = State(initialValue: same ? saved?.dim ?? 0 : 0)
        _blur = State(initialValue: same && saved?.blur == true)
    }

    private var spec: ImageThemeSpec { ImageThemeSpec(theme: preset?.image ?? picture, dim: dim, blur: blur) }
    private var palette: ThemePalette { preset.map { ThemePalette.find($0.theme) } ?? Safir.palette }
    private var bubble: BubbleStyle { preset.map { BubbleStyle.style($0.bubble) } ?? ThemeRuntime.shared.bubble }

    var body: some View {
        ZStack {
            ImageThemeWallpaper(spec: spec)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.25), value: spec)
            VStack(spacing: 12) {
                topBar
                Spacer(minLength: 0)
                SampleChat(palette: palette, bubble: bubble)
                panel
            }
        }
        .environment(\.colorScheme, preset.flatMap { ThemePalette.find($0.theme).scheme } ?? systemScheme)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                Safir.tap()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .frame(width: 44, height: 44)
                    .safirGlass(in: Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(tr("Назад"))
            VStack(alignment: .leading, spacing: 1) {
                Text(tr("Предпросмотр")).font(.subheadline.weight(.semibold)).foregroundStyle(palette.text)
                Text((preset.map { $0.emoji + "  " } ?? "") + tr(spec.theme.name))
                    .font(.caption).foregroundStyle(palette.muted).lineLimit(1)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .safirGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var panel: some View {
        VStack(spacing: 10) {
            strip
            // Brightness: 100% = the picture as is, lower = darker (dimming).
            HStack(spacing: 10) {
                Image(systemName: "sun.min").foregroundStyle(palette.muted)
                Slider(value: Binding(get: { 1 - dim / ImageThemeSpec.maxDim }, set: { b in
                    dim = min(max((1 - b) * ImageThemeSpec.maxDim, 0), ImageThemeSpec.maxDim)
                    let step = Int(b * 10)
                    if step != lastStep {
                        lastStep = step
                        Safir.tap(.soft)
                    }
                }))
                .tint(palette.accent)
                Image(systemName: "sun.max.fill").foregroundStyle(palette.text)
            }
            .font(.system(size: 18))
            .padding(.horizontal, 16)
            Toggle(isOn: Binding(get: { blur }, set: { on in
                Safir.tap()
                withAnimation(.easeInOut(duration: 0.25)) { blur = on }
            })) {
                Label(tr("Размытие"), systemImage: "aqi.medium").foregroundStyle(palette.text)
            }
            .tint(palette.accent)
            .padding(.horizontal, 16)
            HStack(spacing: 10) {
                Button {
                    Safir.tap()
                    dismiss()
                } label: {
                    Text(tr("Отмена")).font(.headline).foregroundStyle(palette.text)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(palette.muted.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
                Button {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onApply(spec.raw, preset)
                    dismiss()
                } label: {
                    Text(tr("Применить")).font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient(colors: [palette.accent, palette.accentDeep],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("theme-apply")
            }
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 14)
        .safirGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    /// The other pictures (or whole themes), the chosen one centred when the preview opens.
    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    if presetMode {
                        ForEach(ThemePreset.all) { p in
                            thumb(p.image, emoji: p.emoji, selected: p == preset) { preset = p }
                        }
                    } else {
                        ForEach(ImageChatTheme.all) { t in
                            thumb(t, emoji: nil, selected: t == picture) { picture = t }
                        }
                    }
                }
                .padding(.horizontal, 14)
            }
            .frame(height: 90)
            .onAppear { proxy.scrollTo(spec.theme.key, anchor: .center) }
        }
    }

    private func thumb(_ theme: ImageChatTheme, emoji: String?, selected: Bool, pick: @escaping () -> Void) -> some View {
        Button {
            Safir.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { pick() }
        } label: {
            ImageThemeWallpaper(spec: ImageThemeSpec(theme: theme), thumbnail: true)
                .frame(width: 52, height: 86)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(palette.accent))
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    } else if let emoji {
                        Text(emoji).font(.system(size: 18))
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? palette.accent : Color.white.opacity(0.12), lineWidth: selected ? 2.5 : 1))
                .scaleEffect(selected ? 1 : 0.94)
        }
        .buttonStyle(.plain)
        .id(theme.key)
        .accessibilityLabel(tr(theme.name))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A few messages both ways in the given colours, so the theme is judged in context.
private struct SampleChat: View {
    let palette: ThemePalette
    let bubble: BubbleStyle

    var body: some View {
        VStack(spacing: 6) {
            Text(tr("Сегодня"))
                .font(.caption.weight(.medium)).foregroundStyle(palette.text)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .safirGlass(in: Capsule())
                .padding(.bottom, 4)
            row("Салом! Посмотри на новую тему 😍", "10:41", mine: false)
            row("Ого, очень красиво!", "10:42", mine: true)
            row("Яркость и размытие — внизу", "10:42", mine: false)
            row("Сейчас применю ✨", "10:43", mine: true)
        }
        .padding(.horizontal, 10)
        .animation(.easeInOut(duration: 0.25), value: bubble.id)
    }

    private func row(_ text: String, _ time: String, mine: Bool) -> some View {
        HStack {
            if mine { Spacer(minLength: 60) }
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(tr(text)).font(.system(size: AppSettings.shared.fontSize)).foregroundStyle(palette.text)
                HStack(spacing: 2) {
                    Text(time)
                    if mine { DoubleTick().foregroundStyle(palette.accent) }
                }
                .font(.system(size: 11))
                .foregroundStyle(mine ? bubble.meta : palette.metaIn)
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(
                BubbleShape(isMe: mine, tail: true)
                    .fill(mine
                          ? AnyShapeStyle(LinearGradient(colors: [bubble.top, bubble.bottom], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(palette.bubbleIn))
                    .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
            )
            if !mine { Spacer(minLength: 60) }
        }
    }
}
