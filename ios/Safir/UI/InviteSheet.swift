import CoreImage.CIFilterBuiltins
import SwiftUI

/// "Пригласить друзей" (Android InviteSheet.kt): a QR code of the link a friend can scan with the
/// camera, plus Send and Copy. The link is this server's web client (works with no install).
struct InviteSheet: View {
    let text: String
    let link: String
    @State private var copied = false

    var body: some View {
        VStack(spacing: 18) {
            Text(tr("Пригласить друзей")).font(.title3.bold()).foregroundStyle(Safir.text).padding(.top, 24)
            Text(tr("Отправьте ссылку или дайте отсканировать QR-код камерой"))
                .font(.subheadline).foregroundStyle(Safir.muted).multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if let qr = Self.qr(link) {
                Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            }
            Text(link).font(.footnote.monospaced()).foregroundStyle(Safir.muted).lineLimit(1).truncationMode(.middle)
                .padding(.horizontal, 24)
            HStack(spacing: 10) {
                ShareLink(item: text) {
                    Label(tr("Отправить"), systemImage: "square.and.arrow.up")
                        .font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Capsule().fill(Safir.brandGradient))
                }
                Button {
                    UIPasteboard.general.string = link
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(Safir.spring) { copied = true }
                } label: {
                    Label(tr(copied ? "Скопировано" : "Копировать"), systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.headline).foregroundStyle(Safir.accent)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Capsule().fill(Safir.accent.opacity(0.14)))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 0)
        }
        .background(Safir.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private static func qr(_ string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
