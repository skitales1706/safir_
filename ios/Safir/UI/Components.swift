import SwiftUI
import UIKit

/// Images from our own server must go through the pinned-trust session (AsyncImage uses
/// URLSession.shared, which rejects the self-signed production certificate).
@MainActor
final class ImageLoader {
    static let shared = ImageLoader()
    private let cache = NSCache<NSString, UIImage>()

    func image(for path: String) async -> UIImage? {
        if let hit = cache.object(forKey: path as NSString) { return hit }
        let api = Session.shared.api
        guard let url = api.ownServerURL(path), let data = try? await api.perform(URLRequest(url: url)),
              let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}

struct AvatarView: View {
    let name: String
    let path: String?
    var size: CGFloat = 44
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [color.opacity(0.85), color], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: path) {
            if let path, !path.isEmpty { image = await ImageLoader.shared.image(for: path) }
        }
    }

    private var initials: String {
        let parts = name.split(separator: " ").filter { $0.first?.isLetter == true }.prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    private var color: Color { Self.color(for: name) }

    /// A stable colour per person (avatar background, sender name in groups).
    static func color(for name: String) -> Color {
        let palette: [UInt32] = [0x1ECFEF, 0x7B4FD6, 0xD64F8E, 0x2E8B57, 0xE07B39, 0x3A6EA5, 0x1BA39C, 0xC99A2E]
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Color(hex: palette[sum % palette.count])
    }
}

enum TimeText {
    private static let clockFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM"
        return f
    }()

    static func short(_ millis: Int64) -> String {
        guard millis > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
        let cal = Calendar.current
        if cal.isDateInToday(date) { return clockFormat.string(from: date) }
        if cal.isDateInYesterday(date) { return "Вчера" }
        return dayFormat.string(from: date)
    }

    static func clock(_ millis: Int64) -> String {
        clockFormat.string(from: Date(timeIntervalSince1970: TimeInterval(millis) / 1000))
    }

    static func lastSeen(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "был(а) недавно" }
        return "был(а) " + short(Dates.millis(iso)).lowercased()
    }
}

/// Two overlapping checkmarks, Telegram style.
struct DoubleTick: View {
    var body: some View {
        ZStack {
            Image(systemName: "checkmark").offset(x: -3)
            Image(systemName: "checkmark").offset(x: 2)
        }
        .padding(.leading, 3)
    }
}

/// Delivery ticks: clock = sending, ! = failed, one tick = sent, two = delivered, accent = read.
struct TicksView: View {
    let status: Int
    let isDelivered: Bool
    let isRead: Bool

    var body: some View {
        Group {
            if status == DeliveryStatus.sending {
                Image(systemName: "clock")
            } else if status == DeliveryStatus.failed {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
            } else if isRead {
                DoubleTick().foregroundStyle(Safir.accent)
            } else if isDelivered {
                DoubleTick()
            } else {
                Image(systemName: "checkmark")
            }
        }
        .font(.caption2)
    }
}
