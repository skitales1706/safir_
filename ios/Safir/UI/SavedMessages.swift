import Observation
import PhotosUI
import SwiftUI

/// One item in Избранное (Android SavedMessage): a note typed here or a message forwarded from a
/// chat, with a private copy of its file. Old notes (id/text/date only) still decode.
struct SavedItem: Codable, Identifiable, Equatable {
    let id: String
    var text: String
    let date: Double
    /// "text" | "image" | "video" | "audio" | "file" (MessageItem.type names); nil = text.
    var type: String?
    /// File name inside SavedStore.folder.
    var file: String?
    /// Chat it was forwarded from.
    var source: String?
    var originalAt: Double?

    var kind: String { type ?? "text" }
}

/// Избранное, kept ONLY on this phone like Android's SavedMessages.kt: rows in the app database,
/// files in a no-backup folder with complete data protection. Nothing reaches the server.
@MainActor
@Observable
final class SavedStore {
    static let shared = SavedStore()
    private(set) var items: [SavedItem] = []

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var dir = base.appendingPathComponent("saved", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.complete])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? dir.setResourceValues(values)
        }
        return dir
    }

    private init() { load() }

    func url(_ item: SavedItem) -> URL? {
        item.file.map { Self.folder.appendingPathComponent($0) }
    }

    func addNote(_ text: String) {
        append(SavedItem(id: UUID().uuidString, text: text, date: Date().timeIntervalSince1970))
    }

    func addFile(_ data: Data, type: String, ext: String, text: String = "", source: String? = nil, originalAt: Double? = nil) {
        let name = UUID().uuidString + "." + ext
        do {
            try data.write(to: Self.folder.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        } catch {
            AppLog.write("Saved file write failed: \(error.localizedDescription)")
            return
        }
        append(SavedItem(id: UUID().uuidString, text: text, date: Date().timeIntervalSince1970, type: type,
                         file: name, source: source, originalAt: originalAt))
    }

    /// "Переслать → Избранное": text as is, media copied out of the encrypted cache.
    func save(_ messages: [MessageItem], source: String) async -> Bool {
        var ok = true
        for m in messages.sorted(by: { $0.timestamp < $1.timestamp }) {
            let at = Double(m.timestamp) / 1000
            if m.type == "text" {
                append(SavedItem(id: UUID().uuidString, text: m.content, date: Date().timeIntervalSince1970,
                                 source: source, originalAt: at))
            } else if let url = await MediaService.shared.resolve(m), let data = try? Data(contentsOf: url) {
                let ext = url.pathExtension.isEmpty ? MediaCache.ext(for: m.type) : url.pathExtension
                addFile(data, type: m.type, ext: ext, source: source, originalAt: at)
            } else {
                ok = false
            }
        }
        return ok
    }

    func delete(_ item: SavedItem) {
        if let url = url(item) { try? FileManager.default.removeItem(at: url) }
        items.removeAll { $0.id == item.id }
        persist()
    }

    private func append(_ item: SavedItem) {
        items.append(item)
        persist()
    }

    private func load() {
        guard let json = Database.shared.string("saved_notes"), let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([SavedItem].self, from: data) else { return }
        items = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        Database.shared.set(String(data: data, encoding: .utf8), for: "saved_notes")
    }
}

/// Избранное as a chat (Android SavedMessagesScreen): notes, photos, videos and files, the
/// chat each forwarded item came from, a composer with text and gallery.
struct SavedMessagesView: View {
    @State private var store = SavedStore.shared
    @State private var draft = ""
    @State private var toast: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var viewing: URL?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if store.items.isEmpty { empty }
                        ForEach(store.items) { item in
                            bubble(item).id(item.id)
                                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                        removal: .scale(scale: 0.8).combined(with: .opacity)))
                        }
                    }
                    .padding(12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: store.items.count) { _, _ in
                    if let last = store.items.last { withAnimation(Safir.spring) { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
                .onAppear { if let last = store.items.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            composer
        }
        .background(ChatWallpaper())
        .navigationTitle(tr("Избранное"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .settingsToast($toast)
        .onChange(of: photoItem) { _, item in
            if let item { Task { await addPicked(item) } }
        }
        .fullScreenCover(isPresented: Binding(get: { viewing != nil }, set: { if !$0 { viewing = nil } })) {
            if let viewing { SavedFileViewer(url: viewing) }
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 52))
                .foregroundStyle(Safir.accent.gradient)
            Text(tr("Избранное")).font(.headline)
            Text(tr("Заметки, ссылки, фото и пересланные сообщения для себя. Хранятся только на этом телефоне."))
                .font(.footnote).foregroundStyle(Safir.muted).multilineTextAlignment(.center)
        }
        .padding(.top, 80).padding(.horizontal, 30)
        .appearIn(0)
    }

    private func bubble(_ item: SavedItem) -> some View {
        HStack {
            Spacer(minLength: 50)
            VStack(alignment: .leading, spacing: 4) {
                if let source = item.source {
                    Label(tr("Из чата «%@»", source), systemImage: "arrowshape.turn.up.right.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(Safir.accent).lineLimit(1)
                }
                content(item)
                Text(TimeText.short(Int64(item.date * 1000))).font(.system(size: 11)).foregroundStyle(Safir.metaOut)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(BubbleShape(isMe: true, tail: item == store.items.last)
                .fill(LinearGradient(colors: [Safir.bubbleOut, Safir.bubbleOutDeep], startPoint: .top, endPoint: .bottom)))
            .contextMenu {
                if !item.text.isEmpty && !AppSecurity.shared.policy.blockCopy {
                    Button { UIPasteboard.general.string = item.text; toast = tr("Скопировано") } label: {
                        Label(tr("Копировать"), systemImage: "doc.on.doc")
                    }
                }
                if let url = store.url(item), item.kind != "text" {
                    ShareLink(item: url) { Label(tr("Поделиться"), systemImage: "square.and.arrow.up") }
                }
                Button(role: .destructive) {
                    withAnimation(Safir.spring) { store.delete(item) }
                } label: { Label(tr("Удалить"), systemImage: "trash") }
            }
        }
    }

    @ViewBuilder
    private func content(_ item: SavedItem) -> some View {
        switch item.kind {
        case "image":
            if let url = store.url(item), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(maxWidth: 240, maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onTapGesture { viewing = url }
            } else {
                fileRow(item, icon: "photo")
            }
        case "video":
            fileRow(item, icon: "play.rectangle.fill")
        case "audio":
            fileRow(item, icon: "waveform")
        case "file":
            fileRow(item, icon: "doc.fill")
        default:
            Text(item.text).font(.system(size: AppSettings.shared.fontSize)).foregroundStyle(Safir.text)
                .textSelection(.enabled)
        }
    }

    private func fileRow(_ item: SavedItem, icon: String) -> some View {
        Button {
            viewing = store.url(item)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.title3).foregroundStyle(.white)
                    .frame(width: 42, height: 42).background(Circle().fill(Safir.accent))
                Text(item.text.isEmpty ? tr(label(item.kind)) : item.text)
                    .font(.subheadline.weight(.medium)).foregroundStyle(Safir.text).lineLimit(2)
            }
        }
        .buttonStyle(.plain)
    }

    private func label(_ kind: String) -> String {
        switch kind {
        case "video": return "Видео"
        case "audio": return "Голосовое"
        case "image": return "Фото"
        default: return "Файл"
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            PhotosPicker(selection: $photoItem, matching: .any(of: [.images, .videos])) {
                Image(systemName: "paperclip")
                    .font(.system(size: 19, weight: .semibold)).foregroundStyle(Safir.text)
                    .frame(width: 42, height: 42)
                    .safirGlass(in: Circle(), rim: true)
            }
            TextField(tr("Заметка…"), text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .focused($focused)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .safirGlass(in: RoundedRectangle(cornerRadius: 21, style: .continuous), rim: true)
            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: add) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Safir.brandGradient))
                }
                .buttonStyle(PressableStyle())
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: draft.isEmpty)
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Safir.tap()
        withAnimation(Safir.spring) { store.addNote(text) }
        draft = ""
    }

    private func addPicked(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            guard let movie = try? await item.loadTransferable(type: PickedMovie.self),
                  let data = try? Data(contentsOf: movie.url) else { return }
            let ext = movie.url.pathExtension.isEmpty ? "mp4" : movie.url.pathExtension
            withAnimation(Safir.spring) { store.addFile(data, type: "video", ext: ext) }
        } else if let data = try? await item.loadTransferable(type: Data.self) {
            withAnimation(Safir.spring) { store.addFile(data, type: "image", ext: "jpg") }
        }
    }
}

/// Full-screen look at a saved file: photos zoomable, anything else can be opened elsewhere.
private struct SavedFileViewer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image = UIImage(contentsOfFile: url.path) {
                ZoomableImage(image: image)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.fill").font(.system(size: 54)).foregroundStyle(.white.opacity(0.8))
                    Text(url.lastPathComponent).font(.footnote).foregroundStyle(.white.opacity(0.7))
                    ShareLink(item: url) { Label(tr("Открыть в…"), systemImage: "square.and.arrow.up") }
                        .buttonStyle(.borderedProminent).tint(Safir.accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            GlassCircle(action: { dismiss() }) { Image(systemName: "xmark") }
                .padding(16)
        }
    }
}

/// Pinch to zoom, double tap to toggle 2x, drag while zoomed.
struct ZoomableImage: View {
    let image: UIImage
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        Image(uiImage: image).resizable().scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gesture(
                MagnificationGesture()
                    .onChanged { scale = max(1, min(lastScale * $0, 5)) }
                    .onEnded { _ in
                        lastScale = scale
                        if scale == 1 { withAnimation(Safir.spring) { offset = .zero; lastOffset = .zero } }
                    }
                    .simultaneously(with: DragGesture()
                        .onChanged { value in
                            guard scale > 1 else { return }
                            offset = CGSize(width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height)
                        }
                        .onEnded { _ in lastOffset = offset })
            )
            .onTapGesture(count: 2) {
                withAnimation(Safir.spring) {
                    if scale > 1 {
                        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
                    } else {
                        scale = 2; lastScale = 2
                    }
                }
            }
    }
}
