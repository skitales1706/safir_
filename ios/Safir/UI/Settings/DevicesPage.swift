import SwiftUI

struct DevicesPage: View {
    @Environment(Session.self) private var session
    @State private var profile = ProfileStore.shared
    @State private var confirmOthers = false
    @State private var ending: SessionInfo?
    @State private var pulse = false

    private var others: [SessionInfo] { profile.sessions.filter { !$0.isCurrent } }

    var body: some View {
        SettingsPage(title: "Устройства") {
            thisDevice.appearIn(0)

            if !others.isEmpty {
                SettingsGroup(footer: "Выйдите на устройствах, которыми больше не пользуетесь.") {
                    ActionSettingsRow(icon: "hand.raised.fill", color: Safir.danger, title: "Завершить другие сеансы",
                                      titleColor: Safir.danger) { confirmOthers = true }
                }
                .appearIn(1)
            }

            SettingsGroup(header: "Активные сеансы") {
                if profile.sessions.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView().padding(20)
                        Spacer()
                    }
                }
                ForEach(Array(profile.sessions.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { SettingsDivider() }
                    SettingsRow(icon: Self.icon(item.deviceName), color: item.isCurrent ? Tile.green : Tile.blue,
                                title: item.deviceName,
                                subtitle: item.isCurrent ? "Это устройство · в сети" : Self.when(item.createdAt)) {
                        if !item.isCurrent {
                            Button {
                                Safir.tap()
                                ending = item
                            } label: {
                                Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(Safir.muted)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .appearIn(2)
        }
        .task { await profile.loadSessions() }
        .confirmationDialog("Выйти на всех других устройствах?", isPresented: $confirmOthers, titleVisibility: .visible) {
            Button("Завершить", role: .destructive) { Task { await profile.revokeOthers() } }
        }
        .confirmationDialog("Завершить сеанс «\(ending?.deviceName ?? "")»?",
                            isPresented: Binding(get: { ending != nil }, set: { if !$0 { ending = nil } }),
                            titleVisibility: .visible) {
            Button("Завершить", role: .destructive) {
                if let item = ending { Task { await profile.revoke(item) } }
            }
        }
    }

    private var thisDevice: some View {
        VStack(spacing: 10) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(Safir.accent.gradient)
                .padding(.top, 18)
            Text(session.deviceName).font(.headline)
            HStack(spacing: 18) {
                status("Ключи Signal", ok: session.deviceReady)
                status("Соединение", ok: ChatService.shared.connected)
            }
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Safir.accent.opacity(0.2), Safir.card], startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Safir.separator, lineWidth: 0.5))
        .onAppear {
            guard !DemoData.active else { return }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private func status(_ title: String, ok: Bool) -> some View {
        HStack(spacing: 6) {
            Circle().fill(ok ? Safir.online : Safir.danger).frame(width: 8, height: 8)
                .scaleEffect(pulse && ok ? 1.35 : 1)
                .opacity(pulse && ok ? 0.6 : 1)
            Text(title).font(.footnote.weight(.medium)).foregroundStyle(Safir.muted)
        }
    }

    private static func icon(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("windows") || n.contains("desktop") || n.contains("mac") || n.contains("linux") { return "laptopcomputer" }
        if n.contains("web") || n.contains("chrome") || n.contains("safari") || n.contains("firefox") { return "globe" }
        if n.contains("ipad") { return "ipad" }
        return "iphone"
    }

    private static func when(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "Активен" }
        return "Вход: " + TimeText.short(Dates.millis(iso))
    }
}
