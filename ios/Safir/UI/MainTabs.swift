import Observation
import SwiftUI

/// Bottom tabs - the same five as Android's TojBottomNav.
enum AppTab: Int, CaseIterable, Identifiable {
    case chats, contacts, calls, services, settings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .chats: return "Чаты"
        case .contacts: return "Контакты"
        case .calls: return "Звонки"
        case .services: return "Сервисы"
        case .settings: return "Настройки"
        }
    }

    var icon: String {
        switch self {
        case .chats: return "bubble.left.and.bubble.right"
        case .contacts: return "person.2"
        case .calls: return "phone"
        case .services: return "square.grid.2x2"
        case .settings: return "gearshape"
        }
    }

    /// One brand colour for every tab, like Telegram's single accent.
    var color: Color { Safir.accent }

    /// UI tests tap tabs by this id.
    var testId: String { "tab-\(rawValue)" }
}

/// Which tab is shown and which chat is open. Contacts, Calls and notifications open chats
/// through here, so a chat always lives in the Chats tab's stack (Telegram does the same).
@MainActor
@Observable
final class TabRouter {
    static let shared = TabRouter()

    var tab: AppTab = .chats
    var chatPath: [String] = []
    var settingsPath: [SettingsRoute] = []
    /// "new" / "saved" / "search" from a quick action or link; the chat list performs and clears it.
    var pendingAction: String?
    /// Bumped when the current tab is tapped again - lists scroll back to the top.
    private(set) var reselect = 0

    /// Whether the Chats / Settings root list is on screen. On iOS 26 the path binding alone did
    /// not report an open chat, and the bar covered the composer; the roots' own appear /
    /// disappear does.
    var chatsRootShown = true
    var settingsRootShown = true

    /// The bar hides while a chat or a settings page is open, like Telegram.
    var barHidden: Bool {
        !chatPath.isEmpty || (tab == .chats && !chatsRootShown)
            || (tab == .settings && (!settingsPath.isEmpty || !settingsRootShown))
    }

    func select(_ new: AppTab) {
        if new == tab {
            reselect &+= 1
        } else {
            tab = new
        }
    }

    func openChat(_ chatId: String) {
        tab = .chats
        chatPath = [chatId]
    }

    /// 1:1 chat with a person found in Contacts / search / the call log.
    func openChat(with user: APIUser) {
        openChat(ChatStore.shared.ensureDirectChat(myUserId: ChatService.shared.myUserId, partner: user))
    }

    func call(_ user: APIUser, video: Bool) {
        let id = ChatStore.shared.ensureDirectChat(myUserId: ChatService.shared.myUserId, partner: user)
        guard let chat = ChatStore.shared.chat(id) else { return }
        CallService.shared.start(chat: chat, video: video)
    }
}

struct MainTabView: View {
    let user: UserDTO
    @State private var router = TabRouter.shared
    @State private var unreadChats = 0
    private var calls: CallLog { CallLog.shared }

    var body: some View {
        TabView(selection: $router.tab) {
            ChatListView()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.chats)
            ContactsView()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.contacts)
            CallsView()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.calls)
            ServicesView()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.services)
            SettingsView(user: user)
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.settings)
        }
        .overlay(alignment: .bottom) {
            if !router.barHidden {
                SafirTabBar(selected: router.tab, badges: [.chats: unreadChats, .calls: calls.unseenMissed]) { tab in
                    Safir.tap()
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.74)) { router.select(tab) }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(Safir.spring, value: router.barHidden)
        .onAppear {
            countUnread()
            calls.refreshBadge()
        }
        .onChange(of: ChatService.shared.revision) { _, _ in countUnread() }
        .fullScreenCover(isPresented: Binding(get: { CallService.shared.showUI },
                                              set: { CallService.shared.showUI = $0 })) {
            CallView()
        }
    }

    /// Chats with unread messages, muted ones not counted (Android chatsBadge).
    private func countUnread() {
        unreadChats = ChatStore.shared.chats().filter { $0.unreadCount > 0 && !$0.isMuted }.count
    }
}

/// Telegram/Android floating pill: icon + small label per tab, a tinted capsule that slides to
/// the selected tab, a bounce on the newly selected icon and badges for unread chats / missed calls.
struct SafirTabBar: View {
    /// Room the lists leave under their last row so it can scroll out from under the bar.
    static let clearance: CGFloat = 76

    let selected: AppTab
    let badges: [AppTab: Int]
    let onSelect: (AppTab) -> Void
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                TabBarItem(tab: tab, selected: tab == selected, badge: badges[tab] ?? 0, ns: ns) {
                    onSelect(tab)
                }
            }
        }
        .padding(4)
        .frame(height: 60)
        // Transparent glass: the list shows through the bar.
        .safirGlass(in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, Self.bottomPadding)
    }

    /// Like Telegram (Android a61591b) the bar sits low: it dips ~12pt into the home indicator's
    /// empty top edge, clear of the indicator itself; phones with a Home button get 8pt from the edge.
    private static var bottomPadding: CGFloat {
        let inset = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.bottom ?? 0
        return inset > 0 ? 2 - min(12, max(0, inset - 20)) : 8
    }
}

private struct TabBarItem: View {
    let tab: AppTab
    let selected: Bool
    let badge: Int
    let ns: Namespace.ID
    let action: () -> Void
    @State private var bounce = 0

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: selected ? tab.icon + ".fill" : tab.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolEffect(.bounce, value: bounce)
                    // The gear turns a quarter when Settings opens (Android NavTab).
                    .rotationEffect(.degrees(tab == .settings && selected ? 90 : 0))
                    .frame(height: 24)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text(badge > 99 ? "99+" : "\(badge)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Capsule().fill(tab == .calls ? Safir.danger : Safir.accent))
                                .overlay(Capsule().stroke(Safir.surface, lineWidth: 1.5))
                                .offset(x: 13, y: -7)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                Text(tr(tab.title))
                    .font(.system(size: 10, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? tab.color : Safir.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if selected {
                    Capsule().fill(tab.color.opacity(0.14)).matchedGeometryEffect(id: "tab-highlight", in: ns)
                }
            }
            .contentShape(Capsule())
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: badge)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(tab.testId)
        .accessibilityLabel(tr(tab.title))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onChange(of: selected) { _, now in
            if now { bounce += 1 }
        }
    }
}

extension View {
    /// Lists in a tab keep their last row clear of the floating tab bar.
    func tabBarClearance() -> some View {
        contentMargins(.bottom, SafirTabBar.clearance, for: .scrollContent)
    }
}
