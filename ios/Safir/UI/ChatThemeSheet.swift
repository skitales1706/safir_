import Observation
import SwiftUI

/// Per-chat wallpaper (Android ChatThemeSheet, Telegram "Chat theme"): kept on this device,
/// chat id -> the same raw value as the app-wide setting ("classic", "none", "theme:<key>?...").
/// No entry = the app-wide wallpaper.
@MainActor
@Observable
final class ChatThemes {
    static let shared = ChatThemes()
    private static let key = "chat_wallpapers"

    private(set) var wallpapers: [String: String]

    private init() {
        wallpapers = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }

    func choice(_ chatId: String) -> WallpaperChoice? {
        wallpapers[chatId].map(WallpaperChoice.init)
    }

    func set(_ chatId: String, _ raw: String?) {
        wallpapers[chatId] = raw
        UserDefaults.standard.set(wallpapers, forKey: Self.key)
    }
}

/// Live preview with two sample bubbles over the picked wallpaper, the cards under it, "Применить".
struct ChatThemeSheet: View {
    let chatId: String
    @Environment(\.dismiss) private var dismiss
    @State private var picked: String?

    /// nil = "По умолчанию" (the app-wide wallpaper).
    private let options: [String?] = [nil, "classic", "none"] + ImageChatTheme.all.map { ImageThemeSpec(theme: $0).raw }

    init(chatId: String) {
        self.chatId = chatId
        _picked = State(initialValue: ChatThemes.shared.wallpapers[chatId])
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                preview
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 16)
                    .animation(Safir.spring, value: picked)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(options, id: \.self) { raw in card(raw) }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 4)
                }
                Spacer(minLength: 0)
                Button {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    ChatThemes.shared.set(chatId, picked)
                    dismiss()
                } label: {
                    Text(tr("Применить")).font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Capsule().fill(Safir.brandGradient))
                }
                .buttonStyle(PressableStyle())
                .padding(.horizontal, 16).padding(.bottom, 12)
            }
            .padding(.top, 8)
            .background(Safir.background.ignoresSafeArea())
            .navigationTitle(tr("Обои чата"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Отмена")) { dismiss() } }
            }
        }
    }

    private var preview: some View {
        ZStack {
            ChatWallpaper(choice: picked.map(WallpaperChoice.init), scale: 0.8)
            VStack(spacing: 8) {
                sample(tr("Привет! Как дела?"), mine: false)
                sample(tr("Отлично, спасибо 🙂"), mine: true)
            }
            .padding(16)
        }
    }

    private func sample(_ text: String, mine: Bool) -> some View {
        HStack {
            if mine { Spacer() }
            Text(text).font(.subheadline)
                .foregroundStyle(Safir.text)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(
                    BubbleShape(isMe: mine, tail: true)
                        .fill(mine
                              ? AnyShapeStyle(LinearGradient(colors: [AppSettings.shared.bubble.top, AppSettings.shared.bubble.bottom],
                                                             startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(Safir.bubbleIn))
                )
            if !mine { Spacer() }
        }
    }

    private func card(_ raw: String?) -> some View {
        let on = picked == raw
        return Button {
            Safir.tap()
            withAnimation(Safir.spring) { picked = raw }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    ChatWallpaper(choice: raw.map(WallpaperChoice.init), scale: 0.35)
                    if raw == nil {
                        Image(systemName: "sparkles").font(.title3).foregroundStyle(Safir.accent)
                    }
                }
                .frame(width: 72, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(on ? Safir.accent : Safir.separator, lineWidth: on ? 2.5 : 0.5))
                .scaleEffect(on ? 1.04 : 1)
                Text(tr(title(raw))).font(.caption2).foregroundStyle(on ? Safir.accent : Safir.muted).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private func title(_ raw: String?) -> String {
        switch raw {
        case nil: return "По умолчанию"
        case "classic": return "Safir"
        case "none": return "Без обоев"
        default: return raw.flatMap(ImageThemeSpec.init(raw:))?.theme.name ?? "Обои"
        }
    }
}
