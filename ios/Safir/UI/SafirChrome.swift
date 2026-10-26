import SwiftUI
import UIKit

extension Safir {
    /// Android PillColor: background of round buttons, search field and chips.
    static var pill: Color { palette.pill }
}

extension View {
    /// Safir glass: Apple's Liquid Glass with a faint accent tint on iOS 26 (needs the iOS 26
    /// SDK, i.e. Xcode 26 / Swift 6.2), frosted material before that. [rim] adds the hairline
    /// rim and soft shadow the material needs - Liquid Glass draws its own. [interactive] makes
    /// the glass react to touch (iOS 26 controls).
    @ViewBuilder
    func safirGlass<S: Shape>(in shape: S, rim: Bool = false, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let glass = Glass.regular.tint(Safir.accent.opacity(0.06))
            glassEffect(interactive ? glass.interactive() : glass, in: shape)
        } else {
            materialGlass(in: shape, rim: rim)
        }
        #else
        materialGlass(in: shape, rim: rim)
        #endif
    }

    @ViewBuilder
    private func materialGlass<S: Shape>(in shape: S, rim: Bool) -> some View {
        if rim {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }
}

/// Floating glass circle (back, attach, call...) - the separate panels over the wallpaper.
struct GlassCircle<Label: View>: View {
    var size: CGFloat = 44
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Safir.text)
                .frame(width: size, height: size)
                .safirGlass(in: Circle(), rim: true, interactive: true)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Glass capsule panel.
struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        content.safirGlass(in: Capsule(), rim: true)
    }
}

extension View {
    func glassCapsule() -> some View { modifier(GlassCapsule()) }
}

/// Round pill button of the chat-list header (Android NewChatButton).
struct PillCircleButton: View {
    let systemImage: String
    var tint: Color = Safir.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Safir.pill))
        }
        .buttonStyle(PressableStyle())
    }
}

enum ChatFilter: String, CaseIterable, Identifiable {
    case all = "Все", personal = "Личные", groups = "Группы", channels = "Каналы", unread = "Непрочитанные"
    var id: String { rawValue }

    func matches(_ c: ChatItem) -> Bool {
        switch self {
        case .all: return true
        case .personal: return !c.isGroup
        case .groups: return c.isGroup && !c.isChannel
        case .channels: return c.isChannel
        case .unread: return c.unreadCount > 0
        }
    }
}

/// With the navigation bar hidden (custom glass header) the edge swipe back still works.
extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
