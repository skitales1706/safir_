import SwiftUI

struct RootView: View {
    @Environment(Session.self) private var session
    @State private var onboarded = OnboardingView.seen

    var body: some View {
        switch session.state {
        case .loggedOut:
            if onboarded {
                LoginView().transition(.opacity)
            } else {
                OnboardingView { onboarded = true }
            }
        case .mfaCode:
            MfaCodeView()
        case .mfaSetupRequired(let pending):
            MfaEnrollView(pendingToken: pending)
        case .loggedIn(let user):
            MainTabView(user: user)
        }
    }
}
