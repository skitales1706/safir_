import AVFoundation
import CryptoKit
import Foundation
import WebRTC

/// Peer connections for one call - full mesh, one RTCPeerConnection per other participant,
/// exactly like Android's WebRtcManager (same SDP/ICE JSON on the wire, so iOS <-> Android works).
final class WebRTCClient: NSObject {
    var onLocalCandidate: ((String, RTCIceCandidate) -> Void)?
    var onConnected: ((String) -> Void)?
    var onFailed: ((String) -> Void)?
    var onRemoteVideo: ((String, RTCVideoTrack) -> Void)?

    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(),
                                        decoderFactory: RTCDefaultVideoDecoderFactory())
    }()

    private var peers: [String: RTCPeerConnection] = [:]
    private var pendingCandidates: [String: [RTCIceCandidate]] = [:]
    private var audioTrack: RTCAudioTrack?
    private(set) var localVideoTrack: RTCVideoTrack?
    private var capturer: RTCCameraVideoCapturer?
    private let constraints = RTCMediaConstraints(mandatoryConstraints: nil,
                                                  optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])

    func startLocalMedia(video: Bool) {
        let audioSource = Self.factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        audioTrack = Self.factory.audioTrack(with: audioSource, trackId: "audio0")
        guard video else { return }
        let videoSource = Self.factory.videoSource()
        let capturer = RTCCameraVideoCapturer(delegate: videoSource)
        self.capturer = capturer
        localVideoTrack = Self.factory.videoTrack(with: videoSource, trackId: "video0")
        let devices = RTCCameraVideoCapturer.captureDevices()
        guard let device = devices.first(where: { $0.position == .front }) ?? devices.first else { return }
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        guard let format = formats.last(where: { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width <= 1280 })
                ?? formats.last else { return }
        let fps = format.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 30
        capturer.startCapture(with: device, format: format, fps: Int(min(fps, 30)))
    }

    func has(_ peerId: String) -> Bool { peers[peerId] != nil }

    func createPeer(_ peerId: String, iceServers: [RTCIceServer]) {
        guard peers[peerId] == nil else { return }
        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        guard let pc = Self.factory.peerConnection(with: config, constraints: constraints, delegate: self) else { return }
        if let audioTrack { pc.add(audioTrack, streamIds: ["stream0"]) }
        if let localVideoTrack { pc.add(localVideoTrack, streamIds: ["stream0"]) }
        peers[peerId] = pc
    }

    func offer(_ peerId: String, completion: @escaping (String) -> Void) {
        guard let pc = peers[peerId] else { return }
        pc.offer(for: constraints) { sdp, error in
            guard let sdp, error == nil else { return }
            pc.setLocalDescription(sdp) { _ in
                DispatchQueue.main.async { completion(sdp.sdp) }
            }
        }
    }

    func handleOffer(_ peerId: String, sdp: String, completion: @escaping (String) -> Void) {
        guard let pc = peers[peerId] else { return }
        let constraints = self.constraints
        pc.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: sdp)) { [weak self] error in
            guard error == nil else { return }
            DispatchQueue.main.async { self?.flushCandidates(peerId) }
            pc.answer(for: constraints) { answer, error in
                guard let answer, error == nil else { return }
                pc.setLocalDescription(answer) { _ in
                    DispatchQueue.main.async { completion(answer.sdp) }
                }
            }
        }
    }

    func handleAnswer(_ peerId: String, sdp: String) {
        guard let pc = peers[peerId] else { return }
        pc.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: sdp)) { [weak self] _ in
            DispatchQueue.main.async { self?.flushCandidates(peerId) }
        }
    }

    /// Candidates can arrive before the remote description - they wait until it's set.
    func addCandidate(_ peerId: String, json: String) {
        guard let data = json.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let sdp = obj["candidate"] as? String else { return }
        let index = Int32((obj["sdpMLineIndex"] as? NSNumber)?.intValue ?? 0)
        let candidate = RTCIceCandidate(sdp: sdp, sdpMLineIndex: index, sdpMid: obj["sdpMid"] as? String)
        guard let pc = peers[peerId], pc.remoteDescription != nil else {
            pendingCandidates[peerId, default: []].append(candidate)
            return
        }
        pc.add(candidate) { _ in }
    }

    private func flushCandidates(_ peerId: String) {
        guard let pc = peers[peerId], let queued = pendingCandidates.removeValue(forKey: peerId) else { return }
        for c in queued { pc.add(c) { _ in } }
    }

    static func serialize(_ c: RTCIceCandidate) -> String {
        let obj: [String: Any] = ["sdpMid": c.sdpMid ?? "", "sdpMLineIndex": c.sdpMLineIndex, "candidate": c.sdp]
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func setMuted(_ muted: Bool) { audioTrack?.isEnabled = !muted }
    func setVideoEnabled(_ on: Bool) { localVideoTrack?.isEnabled = on }

    func remove(_ peerId: String) {
        peers.removeValue(forKey: peerId)?.close()
        pendingCandidates[peerId] = nil
    }

    func closeAll() {
        capturer?.stopCapture()
        capturer = nil
        for pc in peers.values { pc.close() }
        peers.removeAll()
        pendingCandidates.removeAll()
        audioTrack = nil
        localVideoTrack = nil
    }

    /// Same 10 digits as Android's WebRtcManager.verificationCode: SHA-256 over both DTLS
    /// fingerprints (sorted). Equal on both phones = no one is in the middle of the media.
    func verificationCode(_ peerId: String) -> String? {
        guard let pc = peers[peerId], let local = Self.fingerprint(pc.localDescription?.sdp),
              let remote = Self.fingerprint(pc.remoteDescription?.sdp) else { return nil }
        let digest = Array(SHA256.hash(data: Data([local, remote].sorted().joined(separator: "|").utf8)))
        var n: UInt64 = 0
        for i in 0..<5 { n = (n << 8) | UInt64(digest[i]) }
        let code = String(format: "%010llu", n % 10_000_000_000)
        return "\(code.prefix(5)) \(code.suffix(5))"
    }

    private static func fingerprint(_ sdp: String?) -> String? {
        guard let sdp else { return nil }
        for line in sdp.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.lowercased().hasPrefix("a=fingerprint:") {
                return String(t.dropFirst("a=fingerprint:".count)).trimmingCharacters(in: .whitespaces).uppercased()
            }
        }
        return nil
    }

    private func peerId(of pc: RTCPeerConnection) -> String? {
        peers.first { $0.value === pc }?.key
    }
}

extension WebRTCClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        DispatchQueue.main.async {
            guard let id = self.peerId(of: peerConnection) else { return }
            self.onLocalCandidate?(id, candidate)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        DispatchQueue.main.async {
            guard let id = self.peerId(of: peerConnection) else { return }
            switch newState {
            case .connected, .completed: self.onConnected?(id)
            case .failed: self.onFailed?(id)
            default: break
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver,
                        streams mediaStreams: [RTCMediaStream]) {
        guard let track = rtpReceiver.track as? RTCVideoTrack else { return }
        DispatchQueue.main.async {
            guard let id = self.peerId(of: peerConnection) else { return }
            self.onRemoteVideo?(id, track)
        }
    }
}
