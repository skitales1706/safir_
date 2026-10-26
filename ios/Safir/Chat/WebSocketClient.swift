import Foundation

/// The live connection (backend ws.py, /ws/{user_id}). Bearer token in the header - never in
/// the URL, which proxies log. Reconnects with backoff while the app is in the foreground; iOS
/// suspends it in the background, where APNs takes over (backend/apns.py).
@MainActor
final class WebSocketClient {
    var onEvent: (([String: Any]) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?

    private(set) var isConnected = false
    private var task: URLSessionWebSocketTask?
    private var generation = 0
    private var attempts = 0
    private var wanted = false
    private var userId = ""

    func connect(userId: String) {
        self.userId = userId.lowercased()
        wanted = true
        open()
    }

    func disconnect() {
        wanted = false
        generation += 1
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        setConnected(false)
    }

    func send(_ payload: [String: Any]) {
        guard let task, isConnected,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { error in
            if let error { AppLog.write("WS send failed: \(error.localizedDescription)") }
        }
    }

    private func open() {
        generation += 1
        let myGeneration = generation
        task?.cancel(with: .goingAway, reason: nil)
        let task = Session.shared.api.webSocketTask(path: "ws/\(userId)")
        self.task = task
        task.resume()
        // URLSessionWebSocketTask has no "opened" callback without a delegate; a successful
        // ping (or the first frame) proves the connection.
        task.sendPing { [weak self] error in
            Task { @MainActor in
                guard let self, self.generation == myGeneration else { return }
                if let error {
                    AppLog.write("WS connect failed: \(error.localizedDescription)")
                    self.scheduleReconnect()
                } else {
                    self.attempts = 0
                    self.setConnected(true)
                }
            }
        }
        receive(task, generation: myGeneration)
    }

    private func receive(_ task: URLSessionWebSocketTask, generation myGeneration: Int) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.generation == myGeneration else { return }
                switch result {
                case .failure(let error):
                    AppLog.write("WS closed: \(error.localizedDescription)")
                    self.setConnected(false)
                    self.scheduleReconnect()
                case .success(let message):
                    if !self.isConnected {
                        self.attempts = 0
                        self.setConnected(true)
                    }
                    var data: Data?
                    switch message {
                    case .string(let text): data = text.data(using: .utf8)
                    case .data(let d): data = d
                    @unknown default: data = nil
                    }
                    if let data, let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                        if json["type"] as? String == "ping" {
                            self.send(["type": "pong"])
                        } else {
                            self.onEvent?(json)
                        }
                    }
                    self.receive(task, generation: myGeneration)
                }
            }
        }
    }

    private func setConnected(_ connected: Bool) {
        guard connected != isConnected else { return }
        isConnected = connected
        if connected { onConnected?() } else { onDisconnected?() }
    }

    /// Both the ping and the receive loop may report the same failure - the generation check
    /// lets only the first scheduled reconnect run.
    private func scheduleReconnect() {
        guard wanted else { return }
        attempts += 1
        let delay = min(30.0, pow(2.0, Double(min(attempts, 5))) * 0.5)
        let myGeneration = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.wanted, self.generation == myGeneration else { return }
            self.open()
        }
    }
}
