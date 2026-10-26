import AVFoundation
import CallKit
import Foundation
import Observation
import PushKit
import UIKit
import WebRTC

/// Calls: CallKit (the system call screen, also on a locked phone), PushKit (VoIP wake-up from
/// backend apns.py) and the same WebSocket signaling as Android's CallActivity:
/// incoming_call (extra "audio|video" + "|name|isGroup") -> call_accepted -> webrtc_offer /
/// webrtc_answer / webrtc_ice_candidate, call_ended. In a mesh the smaller user id offers.
@MainActor
@Observable
final class CallService: NSObject {
    static let shared = CallService()

    enum Phase: Equatable { case idle, ringingOut, ringingIn, connecting, active }

    struct Participant: Identifiable {
        let id: String
        var name: String
        var connected = false
        var video: RTCVideoTrack?
    }

    private(set) var phase: Phase = .idle
    private(set) var roomId: String?
    private(set) var isVideo = false
    private(set) var isGroup = false
    private(set) var title = ""
    private(set) var participants: [Participant] = []
    private(set) var muted = false
    private(set) var speaker = false
    private(set) var connectedAt: Date?
    private(set) var verifyCode: String?
    var showUI = false

    var inCall: Bool { phase != .idle }
    var localVideo: RTCVideoTrack? { rtc?.localVideoTrack }

    @ObservationIgnored private let provider: CXProvider
    @ObservationIgnored private let controller = CXCallController()
    @ObservationIgnored private var callUUID: UUID?
    @ObservationIgnored private var outgoing = false
    @ObservationIgnored private var rtc: WebRTCClient?
    @ObservationIgnored private var iceServers: [RTCIceServer]?
    @ObservationIgnored private var voipRegistry: PKPushRegistry?
    @ObservationIgnored private var ringTimeout: Task<Void, Never>?
    /// The other side of a 1:1 call, kept for the call log (participants empty out on hang-up).
    @ObservationIgnored private var logPeer: String?
    @ObservationIgnored private var declined = false

    private var myUserId: String { ChatService.shared.myUserId }
    private var api: APIClient { Session.shared.api }

    override init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = true
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        // Banks: calls must not leak into the phone's system call history / iCloud.
        config.includesCallsInRecents = false
        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: nil)
        RTCAudioSession.sharedInstance().useManualAudio = true
        RTCAudioSession.sharedInstance().isAudioEnabled = false
    }

    /// PushKit - only for calls; iOS kills an app that gets a VoIP push without reporting a call.
    func registerVoIP() {
        guard voipRegistry == nil else { return }
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        voipRegistry = registry
    }

    // MARK: Outgoing

    func start(chat: ChatItem, video: Bool) {
        guard !inCall else { return }
        let others: [String]
        if chat.isGroup {
            others = ChatStore.shared.members(chat.id).filter { $0 != myUserId }
        } else if let partner = chat.partnerId {
            others = [partner]
        } else {
            return
        }
        guard !others.isEmpty else { return }
        let uuid = UUID()
        callUUID = uuid
        roomId = UUID().uuidString.lowercased()
        outgoing = true
        isVideo = video
        isGroup = chat.isGroup
        title = chat.name
        participants = others.map { Participant(id: $0, name: ChatStore.shared.displayName($0)) }
        logPeer = chat.isGroup ? nil : others.first
        let action = CXStartCallAction(call: uuid, handle: CXHandle(type: .generic, value: chat.name))
        action.isVideo = video
        controller.request(CXTransaction(action: action)) { error in
            if let error {
                Task { @MainActor in
                    AppLog.write("CallKit refused the call: \(error.localizedDescription)")
                    self.reset()
                }
            }
        }
    }

    // MARK: Incoming

    private func reportIncoming(roomId: String, callerId: String, video: Bool, group: Bool, name: String?,
                                completion: (() -> Void)? = nil) {
        if self.roomId == roomId {
            completion?()
            return
        }
        let callerName = name ?? ChatStore.shared.displayName(callerId)
        let uuid = UUID()
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: callerName)
        update.localizedCallerName = callerName
        update.hasVideo = video
        if inCall {
            // Busy: one call at a time. iOS still requires every VoIP push to be reported.
            provider.reportNewIncomingCall(with: uuid, update: update) { _ in
                Task { @MainActor in
                    self.provider.reportCall(with: uuid, endedAt: nil, reason: .declinedElsewhere)
                    completion?()
                }
            }
            signal("call_ended", to: callerId, room: roomId)
            return
        }
        callUUID = uuid
        self.roomId = roomId
        outgoing = false
        isVideo = video
        isGroup = group
        title = callerName
        participants = [Participant(id: callerId, name: callerName)]
        logPeer = group ? nil : callerId
        phase = .ringingIn
        // App open: our own incoming screen over CallKit's banner (locked phone: CallKit only).
        showUI = UIApplication.shared.applicationState == .active
        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            Task { @MainActor in
                if let error {
                    AppLog.write("CallKit incoming failed: \(error.localizedDescription)")
                    self.reset()
                }
                completion?()
            }
        }
        startRingTimeout()
    }

    private func startRingTimeout() {
        ringTimeout?.cancel()
        ringTimeout = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard !Task.isCancelled, self.phase == .ringingIn || self.phase == .ringingOut else { return }
            if let uuid = self.callUUID {
                self.provider.reportCall(with: uuid, endedAt: nil, reason: .unanswered)
            }
            self.hangUpSignals()
            self.reset()
        }
    }

    // MARK: Signaling (from ChatService)

    func handleSignal(_ e: [String: Any]) {
        let type = (e["call_type"] as? String) ?? (e["action"] as? String) ?? (e["status"] as? String) ?? ""
        let from = ((e["from_id"] as? String) ?? (e["sender_id"] as? String) ?? "").lowercased()
        let room = (e["room_id"] as? String) ?? (e["channel_name"] as? String) ?? ""
        guard !from.isEmpty, from != myUserId, !room.isEmpty else { return }
        switch type {
        case "incoming_call":
            let parts = ((e["extra"] as? String) ?? "").components(separatedBy: "|")
            let video = parts.first == "video"
            let name = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
            let group = parts.count > 2 && parts[2] == "1"
            reportIncoming(roomId: room, callerId: from, video: video, group: group, name: name)
        case "call_accepted" where room == roomId:
            ringTimeout?.cancel()
            phase = .connecting
            if outgoing, let uuid = callUUID { provider.reportOutgoingCall(with: uuid, startedConnectingAt: Date()) }
            Task { await connectMedia() }
        case "participant_added" where room == roomId:
            Task { await refreshRoster() }
        case "call_ended" where room == roomId:
            participantLeft(from)
        case "webrtc_offer" where room == roomId:
            let sdp = (e["payload"] as? String) ?? ""
            Task { await handleOffer(from: from, sdp: sdp) }
        case "webrtc_answer" where room == roomId:
            rtc?.handleAnswer(from, sdp: (e["payload"] as? String) ?? "")
        case "webrtc_ice_candidate" where room == roomId:
            rtc?.addCandidate(from, json: (e["payload"] as? String) ?? "")
        default:
            break
        }
    }

    private func signal(_ type: String, to peer: String, room: String, extra: String? = nil, payload: String? = nil) {
        var msg: [String: Any] = [
            "type": "call", "call_type": type, "action": type, "status": type,
            "to_id": peer, "receiver_id": peer, "partner_id": peer, "chat_id": peer,
            "from_id": myUserId, "sender_id": myUserId, "room_id": room, "channel_name": room,
        ]
        if let extra { msg["extra"] = extra }
        if let payload { msg["payload"] = payload }
        ChatService.shared.sendSignal(msg)
    }

    // MARK: Media

    private func ensureRTC() -> WebRTCClient {
        if let rtc { return rtc }
        let client = WebRTCClient()
        client.startLocalMedia(video: isVideo)
        client.onLocalCandidate = { [weak self] peer, candidate in
            guard let self, let room = self.roomId else { return }
            self.signal("webrtc_ice_candidate", to: peer, room: room, payload: WebRTCClient.serialize(candidate))
        }
        client.onConnected = { [weak self] peer in self?.peerConnected(peer) }
        client.onFailed = { [weak self] peer in self?.participantLeft(peer) }
        client.onRemoteVideo = { [weak self] peer, track in
            guard let self, let i = self.participants.firstIndex(where: { $0.id == peer }) else { return }
            self.participants[i].video = track
        }
        rtc = client
        return client
    }

    private func fetchIceServers() async -> [RTCIceServer] {
        if let iceServers { return iceServers }
        struct IceDTO: Decodable { let urls: [String]; let username: String?; let credential: String? }
        struct IceResponse: Decodable { let iceServers: [IceDTO] }
        let servers = ((try? await api.get("turn-credentials", as: IceResponse.self))?.iceServers ?? []).map {
            RTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential)
        }
        iceServers = servers
        return servers
    }

    private func connectMedia() async {
        _ = ensureRTC()
        await refreshRoster()
    }

    /// Everyone active in the room (GET /calls/{room}/participants); a connection to each one
    /// we don't have yet - the smaller user id of a pair sends the offer (no glare).
    private func refreshRoster() async {
        guard let room = roomId else { return }
        let rtc = ensureRTC()
        let servers = await fetchIceServers()
        struct Roster: Decodable { let participants: [String] }
        let roster = (try? await api.get("calls/\(room)/participants", as: Roster.self))?.participants ?? participants.map(\.id)
        for peer in roster.map({ $0.lowercased() }) where peer != myUserId {
            if !participants.contains(where: { $0.id == peer }) {
                participants.append(Participant(id: peer, name: ChatStore.shared.displayName(peer)))
            }
            guard !rtc.has(peer) else { continue }
            rtc.createPeer(peer, iceServers: servers)
            if myUserId < peer {
                rtc.offer(peer) { [weak self] sdp in
                    self?.signal("webrtc_offer", to: peer, room: room, payload: sdp)
                }
            }
        }
    }

    private func handleOffer(from peer: String, sdp: String) async {
        guard let room = roomId else { return }
        let rtc = ensureRTC()
        if !participants.contains(where: { $0.id == peer }) {
            participants.append(Participant(id: peer, name: ChatStore.shared.displayName(peer)))
        }
        if !rtc.has(peer) { rtc.createPeer(peer, iceServers: await fetchIceServers()) }
        rtc.handleOffer(peer, sdp: sdp) { [weak self] answer in
            self?.signal("webrtc_answer", to: peer, room: room, payload: answer)
        }
    }

    private func peerConnected(_ peer: String) {
        if let i = participants.firstIndex(where: { $0.id == peer }) { participants[i].connected = true }
        guard phase != .active else { return }
        phase = .active
        connectedAt = Date()
        if !isGroup { verifyCode = rtc?.verificationCode(peer) }
        if outgoing, let uuid = callUUID { provider.reportOutgoingCall(with: uuid, connectedAt: Date()) }
    }

    private func participantLeft(_ peer: String) {
        rtc?.remove(peer)
        participants.removeAll { $0.id == peer }
        if participants.isEmpty {
            if let uuid = callUUID { provider.reportCall(with: uuid, endedAt: nil, reason: .remoteEnded) }
            reset()
        }
    }

    /// Screenshot mode (-SafirDemoCall incoming|active): a made-up call on screen, no CallKit, no network.
    func startDemo(active: Bool) {
        demo = true
        title = "Амина Саидова"
        participants = [Participant(id: "u-amina", name: title, connected: active)]
        if active {
            phase = .active
            connectedAt = Date().addingTimeInterval(-83)
            verifyCode = "4821 7390 1155"
        } else {
            phase = .ringingIn
        }
        // Called from Session init, before MainTabs exists: a cover already "presented" when its
        // view mounts never shows, so flip it once the tabs are on screen.
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            showUI = true
        }
    }

    // MARK: User actions (from CallView)

    func answer() {
        guard let uuid = callUUID, phase == .ringingIn else { return }
        controller.request(CXTransaction(action: CXAnswerCallAction(call: uuid))) { error in
            if let error {
                Task { @MainActor in AppLog.write("CallKit answer failed: \(error.localizedDescription)") }
            }
        }
    }

    func hangUp() {
        guard let uuid = callUUID else {
            reset()
            return
        }
        controller.request(CXTransaction(action: CXEndCallAction(call: uuid))) { error in
            if error != nil {
                Task { @MainActor in
                    self.hangUpSignals()
                    self.reset()
                }
            }
        }
    }

    func toggleMute() {
        guard let uuid = callUUID else { return }
        controller.request(CXTransaction(action: CXSetMutedCallAction(call: uuid, muted: !muted))) { _ in }
    }

    func toggleSpeaker() {
        speaker.toggle()
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        try? session.overrideOutputAudioPort(speaker ? .speaker : .none)
        session.unlockForConfiguration()
    }

    func toggleVideo() {
        isVideo.toggle()
        rtc?.setVideoEnabled(isVideo)
    }

    private func hangUpSignals() {
        guard let room = roomId else { return }
        for p in participants { signal("call_ended", to: p.id, room: room) }
    }

    /// Every call ends in reset(), so this is where it goes into the Calls tab (1:1 only, like Android).
    private func recordCall() {
        guard roomId != nil, let peer = logPeer else { return }
        let status: String
        var duration = 0
        if let connectedAt {
            status = CallLogEntry.ok
            duration = max(0, Int(Date().timeIntervalSince(connectedAt)))
        } else if outgoing {
            status = CallLogEntry.cancelled
        } else {
            status = declined ? CallLogEntry.declined : CallLogEntry.missed
        }
        CallLog.shared.record(peerId: peer, outgoing: outgoing, video: isVideo, status: status, duration: duration)
    }

    /// Screenshot mode's made-up call (DemoData): nothing in CallKit to reset.
    private var demo = false

    private func reset() {
        demo = false
        recordCall()
        logPeer = nil
        declined = false
        ringTimeout?.cancel()
        rtc?.closeAll()
        rtc = nil
        callUUID = nil
        roomId = nil
        participants = []
        phase = .idle
        muted = false
        speaker = false
        connectedAt = nil
        verifyCode = nil
        showUI = false
        RTCAudioSession.sharedInstance().isAudioEnabled = false
    }

    private static func configureAudioSession(video: Bool) {
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        let config = RTCAudioSessionConfiguration.webRTC()
        config.category = AVAudioSession.Category.playAndRecord.rawValue
        config.mode = video ? AVAudioSession.Mode.videoChat.rawValue : AVAudioSession.Mode.voiceChat.rawValue
        try? session.setConfiguration(config)
        session.unlockForConfiguration()
    }
}

// MARK: - CallKit

extension CallService: CXProviderDelegate {
    nonisolated func providerDidReset(_ provider: CXProvider) {
        // The iOS 26 simulator resets CallKit on launch; the screenshot-mode call is not CallKit's.
        MainActor.assumeIsolated { if !self.demo { self.reset() } }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        MainActor.assumeIsolated {
            guard let room = roomId else { return action.fail() }
            Self.configureAudioSession(video: isVideo)
            let me = ChatStore.shared.displayName(myUserId)
            let extra = "\(isVideo ? "video" : "audio")|\(me)|\(isGroup ? "1" : "0")"
            for p in participants { signal("incoming_call", to: p.id, room: room, extra: extra) }
            phase = .ringingOut
            showUI = true
            startRingTimeout()
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        MainActor.assumeIsolated {
            guard let room = roomId else { return action.fail() }
            ringTimeout?.cancel()
            Self.configureAudioSession(video: isVideo)
            // Woken from a VoIP push: the app may not have started its session yet.
            if ChatService.shared.myUserId.isEmpty {
                Task { await Session.shared.resume() }
            }
            for p in participants { signal("call_accepted", to: p.id, room: room) }
            phase = .connecting
            showUI = true
            action.fulfill()
            Task { await connectMedia() }
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        MainActor.assumeIsolated {
            if phase == .ringingIn { declined = true }
            hangUpSignals()
            reset()
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        MainActor.assumeIsolated {
            muted = action.isMuted
            rtc?.setMuted(action.isMuted)
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        MainActor.assumeIsolated {
            RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
            RTCAudioSession.sharedInstance().isAudioEnabled = true
        }
    }

    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        MainActor.assumeIsolated {
            RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
            RTCAudioSession.sharedInstance().isAudioEnabled = false
        }
    }
}

// MARK: - PushKit

extension CallService: PKPushRegistryDelegate {
    nonisolated func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let hex = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        MainActor.assumeIsolated { Session.shared.voipTokenReceived(hex) }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        MainActor.assumeIsolated { Session.shared.voipTokenReceived(nil) }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload,
                                  for type: PKPushType, completion: @escaping () -> Void) {
        let dict = payload.dictionaryPayload
        let room = (dict["room_id"] as? String) ?? UUID().uuidString.lowercased()
        let caller = ((dict["caller_id"] as? String) ?? "").lowercased()
        let video = (dict["video"] as? Bool) ?? false
        let target = (dict["uid"] as? String)?.lowercased()
        MainActor.assumeIsolated {
            // A call to another signed-in account (Accounts.swift): that account becomes active so
            // its WebSocket carries the call; iOS still needs the call reported right now.
            if let target, target != Accounts.shared.activeId, Accounts.shared.session(for: target) != nil {
                Task { await Accounts.shared.switchTo(target) }
            }
            reportIncoming(roomId: room, callerId: caller, video: video, group: false, name: nil, completion: completion)
        }
    }
}
