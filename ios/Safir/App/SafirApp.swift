import SwiftUI

@main
struct SafirApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = Session.shared
    @State private var security = AppSecurity.shared
    @State private var settings = AppSettings.shared
    @State private var splashDone = ProcessInfo.processInfo.arguments.contains("-SafirScreenshots")

    init() {
        // Before anything talks to the server: the MDM may point the app at another one.
        Mdm.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .tint(Safir.accent)
                .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-SafirDark") ? .dark : settings.effectiveScheme)
                .onAppear { ThemeSwitcher.applyStored() }
                .environment(\.locale, L10n.shared.locale)
                .fullScreenCover(isPresented: Binding(get: { MeetingService.shared.showUI },
                                                      set: { MeetingService.shared.showUI = $0 })) {
                    if let room = MeetingService.shared.room {
                        MeetingView(room: room, title: MeetingService.shared.title)
                    }
                }
                .overlay {
                    if !splashDone {
                        SplashView().transition(.opacity)
                    }
                }
                .task {
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    withAnimation(.easeOut(duration: 0.35)) { splashDone = true }
                }
                .overlay {
                    if security.locked {
                        if Passcode.shared.isOn {
                            PasscodeLockView().transition(.opacity)
                        } else {
                            PrivacyCover(showUnlock: true)
                        }
                    } else if security.hideContent || (scenePhase != .active && security.policy.blockScreenshots) {
                        PrivacyCover(showUnlock: false)
                    }
                }
                .onOpenURL { TabRouter.shared.open($0) }
                .task {
                    TabRouter.installShortcuts()
                    Notifier.shared.install()
                    await session.resume()
                    await security.refreshPolicy()
                    if security.locked { await security.unlock() }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                ChatService.shared.appBecameActive()
                security.appBecameActive()
                Task {
                    await security.refreshPolicy()
                    if security.locked { await security.unlock() }
                }
            case .background:
                security.appWentToBackground()
                ChatService.shared.appEnteredBackground()
            default:
                break
            }
        }
    }
}
