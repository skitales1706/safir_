import PhotosUI
import SwiftUI

/// Chat background: the chosen wallpaper (Settings → Оформление → Обои), classic by default.
struct ChatWallpaper: View {
    /// nil = the one stored in settings; previews pass their own.
    var choice: WallpaperChoice?
    var scale: CGFloat = 1

    var body: some View {
        let theme = ThemeRuntime.shared
        Group {
            switch choice ?? WallpaperChoice(theme.wallpaper) {
            case .classic:
                ClassicWallpaper()
            case .none:
                Safir.background
            case .image(let spec):
                // A small preview (scale < 0.6) draws the thumbnail file.
                ImageThemeWallpaper(spec: spec, thumbnail: scale < 0.6)
            case .photo:
                PhotoWallpaper(image: theme.photoImage())
            }
        }
        .ignoresSafeArea()
    }
}

/// Safir's own look: soft gradient with a faint pattern of symbols.
private struct ClassicWallpaper: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            LinearGradient(colors: scheme == .dark
                           ? [Color(hex: 0x071326), Color(hex: 0x0A1C30), Color(hex: 0x06202A)]
                           : [Color(hex: 0xDDEFF3), Color(hex: 0xE8F2F7), Color(hex: 0xD8ECEA)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            DoodleLayer(pack: .classic, color: scheme == .dark ? .white : Color(hex: 0x0E1B2A),
                        opacity: scheme == .dark ? 0.05 : 0.07, scale: 0.8)
        }
    }
}

private struct PhotoWallpaper: View {
    let image: UIImage?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let image {
            Color.clear
                .overlay {
                    Image(uiImage: image).resizable().scaledToFill()
                }
                .overlay(Color.black.opacity(scheme == .dark ? 0.25 : 0))
                .clipped()
        } else {
            Safir.background
        }
    }
}

/// Decoded theme pictures kept for the process (~3 full screens + the thumbnails), so reopening
/// a chat or scrolling the gallery never decodes again. NSCache is thread-safe.
enum ThemeImages {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 24 << 20
        return cache
    }()

    static func file(_ theme: ImageChatTheme, thumbnail: Bool) -> String {
        "wp_\(theme.key)\(thumbnail ? "_thumb" : "")"
    }

    static func cached(_ name: String) -> UIImage? { cache.object(forKey: name as NSString) }

    /// Decoded off the main thread - a 900x1600 webp takes tens of ms, a dropped frame when a chat opens.
    static func load(_ name: String) async -> UIImage? {
        if let hit = cached(name) { return hit }
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let path = Bundle.main.path(forResource: name, ofType: "webp"),
                  let decoded = UIImage(contentsOfFile: path) else { return nil }
            let image = decoded.preparingForDisplay() ?? decoded
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            ThemeImages.cache.setObject(image, forKey: name as NSString, cost: cost)
            return image
        }.value
    }
}

/// A picture theme: the image cropped to fill, optionally blurred, darkened by `spec.dim`.
struct ImageThemeWallpaper: View {
    let spec: ImageThemeSpec
    var thumbnail = false
    @State private var loaded: (name: String, image: UIImage)?

    var body: some View {
        let name = ThemeImages.file(spec.theme, thumbnail: thumbnail)
        let image = ThemeImages.cached(name) ?? (loaded?.name == name ? loaded?.image : nil)
        Color(hex: 0x0B0F14)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: spec.blur ? (thumbnail ? 3 : 14) : 0, opaque: true)
                        .transition(.opacity)
                }
            }
            .overlay(Color.black.opacity(spec.dim))
            .clipped()
            .animation(.easeOut(duration: 0.2), value: image == nil)
            .task(id: name) {
                guard ThemeImages.cached(name) == nil, let image = await ThemeImages.load(name) else { return }
                loaded = (name, image)
            }
    }
}

/// Hand-scattered doodles (always the same layout for a pack - a seeded generator).
struct DoodleLayer: View {
    let pack: DoodlePack
    let color: Color
    let opacity: Double
    var scale: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            let images = pack.symbols.map { name -> GraphicsContext.ResolvedImage in
                var image = context.resolve(Image(systemName: name))
                image.shading = .color(color)
                return image
            }
            guard !images.isEmpty else { return }
            var rng = SeededRandom(seed: 0x5AF1)
            let step = 56 * scale
            var row = 0
            var y = -step / 2
            while y < size.height + step {
                var x = (row % 2 == 0 ? 0 : step / 2) - step / 2
                while x < size.width + step {
                    let image = images[rng.next(images.count)]
                    let side = (18 + CGFloat(rng.next(9))) * scale
                    let k = side / max(image.size.width, image.size.height, 1)
                    var c = context
                    c.opacity = opacity
                    c.translateBy(x: x + CGFloat(rng.next(17) - 8) * scale, y: y + CGFloat(rng.next(17) - 8) * scale)
                    c.rotate(by: .degrees(Double(rng.next(61) - 30)))
                    c.draw(image, in: CGRect(x: -image.size.width * k / 2, y: -image.size.height * k / 2,
                                             width: image.size.width * k, height: image.size.height * k))
                    x += step
                }
                y += step * 0.86
                row += 1
            }
        }
        .allowsHitTesting(false)
    }
}

/// SplitMix64 - stable pseudo-random numbers so a wallpaper never reshuffles between redraws.
private struct SeededRandom {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next(_ bound: Int) -> Int {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Int(z % UInt64(max(bound, 1)))
    }
}

/// Telegram's wallpaper gallery: own photo, none, classic, then the picture themes.
struct WallpaperPage: View {
    @State private var theme = ThemeRuntime.shared
    @State private var item: PhotosPickerItem?
    @State private var preview: ImageChatTheme?

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    private var current: WallpaperChoice { WallpaperChoice(theme.wallpaper) }

    var body: some View {
        SettingsPage(title: "Обои") {
            section("Основные", index: 0) {
                PhotosPicker(selection: $item, matching: .images) {
                    WallpaperTile(name: "Своё фото", selected: current == .photo) {
                        ZStack {
                            if current == .photo { ChatWallpaper(choice: .photo) } else { Safir.card }
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Safir.accent)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(.ultraThinMaterial))
                        }
                    }
                }
                .buttonStyle(.plain)
                tile("Нет", .none, raw: "none")
                tile("Классика", .classic, raw: "")
            }
            section("Картинки", index: 1) {
                ForEach(ImageChatTheme.all) { picture in
                    Button {
                        Safir.tap()
                        preview = picture
                    } label: {
                        WallpaperTile(name: picture.name, selected: current.imageKey == picture.key) {
                            ImageThemeWallpaper(spec: ImageThemeSpec(theme: picture), thumbnail: true)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        // Telegram / WhatsApp: a picture opens full screen first, with brightness and blur.
        .fullScreenCover(item: $preview) { picture in
            ChatThemePreview(picture: picture, current: theme.wallpaper) { raw, _ in
                withAnimation(Safir.spring) { theme.wallpaper = raw }
            }
        }
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            Task {
                if let data = try? await picked.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    withAnimation(Safir.spring) { theme.setPhoto(image) }
                    Safir.tap(.medium)
                }
                item = nil
            }
        }
    }

    private func section<Content: View>(_ title: String, index: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr(title).uppercased()).font(.footnote.weight(.semibold)).foregroundStyle(Safir.muted).padding(.leading, 4)
            LazyVGrid(columns: columns, spacing: 12) { content() }
        }
        .appearIn(index)
    }

    private func tile(_ name: String, _ choice: WallpaperChoice, raw: String) -> some View {
        Button {
            Safir.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { theme.wallpaper = raw }
        } label: {
            WallpaperTile(name: name, selected: current == choice) {
                ChatWallpaper(choice: choice, scale: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

/// A 9:16 thumbnail with a ring and a check that pop in on the chosen one.
struct WallpaperTile<Content: View>: View {
    let name: String
    let selected: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 5) {
            content()
                .aspectRatio(9 / 16, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(selected ? Safir.accent : Safir.separator, lineWidth: selected ? 2.5 : 1)
                )
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Safir.accent))
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                }
                .scaleEffect(selected ? 1 : 0.95)
            Text(tr(name))
                .font(.caption2.weight(selected ? .bold : .regular))
                .foregroundStyle(selected ? Safir.text : Safir.muted)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}
