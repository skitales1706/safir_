import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// System camera for the attach menu (Android TakePicture): a photo or a short video, handed back
/// as a file URL (video) or JPEG data (photo).
struct CameraPicker: UIViewControllerRepresentable {
    enum Shot { case photo(Data), video(URL) }
    let onShot: (Shot) -> Void
    @Environment(\.dismiss) private var dismiss

    static var available: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoQuality = .typeHigh
        picker.videoMaximumDuration = 300
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL {
                parent.onShot(.video(url))
            } else if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.92) {
                parent.onShot(.photo(data))
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Contact card inside a bubble; the button opens the person's profile.
struct SharedContactCard: View {
    let contact: SharedContact
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AvatarView(name: contact.name, path: ChatStore.shared.user(contact.userId)?.avatarUrl, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(contact.username.isEmpty ? tr("Контакт Safir") : "@" + contact.username)
                        .font(.caption).foregroundStyle(Safir.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Divider().overlay(Safir.separator)
            Button {
                Safir.tap()
                onOpen()
            } label: {
                Text(tr("Открыть профиль")).font(.subheadline.weight(.semibold)).foregroundStyle(Safir.accent)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 18)
        .frame(minWidth: 200, maxWidth: 260, alignment: .leading)
    }
}

/// Pick a chat to send something to (profile → "Поделиться контактом").
struct ChatPickerSheet: View {
    let title: String
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var chats: [ChatItem] {
        let q = query.lowercased()
        return ChatStore.shared.chats().filter { !($0.isChannel && $0.myRole == "member") }
            .filter { q.isEmpty || $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List(chats) { chat in
                Button {
                    Safir.tap()
                    onPick(chat.id)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(name: chat.name, path: chat.avatarUrl, size: 42)
                        Text(chat.name).foregroundStyle(Safir.text).lineLimit(1)
                    }
                }
                .listRowBackground(Safir.background)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Safir.background.ignoresSafeArea())
            .searchable(text: $query, prompt: Text(tr("Поиск")))
            .navigationTitle(tr(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Отмена")) { dismiss() } }
            }
        }
    }
}

/// Pick a Safir contact to send as a card (attach menu → "Контакт").
struct ContactPickerSheet: View {
    let onPick: (APIUser) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var people: [APIUser] {
        let q = query.lowercased()
        return ChatStore.shared.contacts(excluding: ChatService.shared.myUserId).filter {
            q.isEmpty || ($0.fullName ?? "").lowercased().contains(q) || $0.username.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List(people, id: \.id) { user in
                Button {
                    Safir.tap()
                    onPick(user)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(name: user.fullName ?? user.username, path: user.avatarUrl, size: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.fullName ?? user.username).foregroundStyle(Safir.text)
                            Text("@" + user.username).font(.caption).foregroundStyle(Safir.muted)
                        }
                    }
                }
                .listRowBackground(Safir.background)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Safir.background.ignoresSafeArea())
            .searchable(text: $query, prompt: Text(tr("Поиск")))
            .overlay {
                if people.isEmpty {
                    ContentUnavailableView(tr("Нет контактов"), systemImage: "person.crop.circle.badge.questionmark")
                }
            }
            .navigationTitle(tr("Отправить контакт"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Отмена")) { dismiss() } }
            }
        }
    }
}
