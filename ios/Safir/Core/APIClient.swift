import Foundation

struct APIError: LocalizedError {
    let status: Int
    let detail: String

    var errorDescription: String? { detail }
}

/// Thin JSON-over-HTTPS client for the Safir backend. Requests/responses are snake_case on the
/// wire and camelCase in Swift (the coders convert).
final class APIClient {
    static let defaultServer = URL(string: "https://129.101.119.187/")!

    /// One client per process (the app, or the Notification Service Extension), configured from
    /// the shared Keychain so both reach the same server with the same session token.
    static let shared: APIClient = {
        let client = APIClient(baseURL: Keychain.get("base_url").flatMap(URL.init(string:)) ?? defaultServer)
        client.token = Keychain.get("auth_token")
        return client
    }()

    var baseURL: URL
    var token: String?

    private let session: URLSession
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config, delegate: PinnedTrustDelegate(), delegateQueue: nil)
    }

    func get<Response: Decodable>(_ path: String, query: [String: String] = [:], as type: Response.Type) async throws -> Response {
        try decoder.decode(type, from: try await send("GET", path, query: query, body: nil))
    }

    func post<Response: Decodable>(_ path: String, body: any Encodable, as type: Response.Type) async throws -> Response {
        try decoder.decode(type, from: try await send("POST", path, body: body))
    }

    func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        try decoder.decode(type, from: data)
    }

    func url(_ path: String, query: [String: String] = [:]) -> URL {
        let url = baseURL.appendingPathComponent(path)
        guard !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url ?? url
    }

    @discardableResult
    func send(_ method: String, _ path: String, query: [String: String] = [:], body: (any Encodable)?,
              bearer: String? = nil) async throws -> Data {
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let auth = bearer ?? token {
            request.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        return try await perform(request)
    }

    /// Raw request (uploads with a non-JSON body, ranged downloads). Auth header added here.
    func perform(_ request: URLRequest) async throws -> Data {
        var request = request
        if request.value(forHTTPHeaderField: "Authorization") == nil, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = Self.detail(from: data) ?? "HTTP \(status)"
            if status == 401 || status == 403 {
                Self.onAuthFailure?(status, detail)
            }
            throw APIError(status: status, detail: detail)
        }
        return data
    }

    /// Set by Session: a revoked token or a blocked/wiped device signs the app out.
    static var onAuthFailure: ((Int, String) -> Void)?

    /// The same pinned-trust URLSession, for the WebSocket.
    func webSocketTask(path: String) -> URLSessionWebSocketTask {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        var request = URLRequest(url: components.url!)
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return session.webSocketTask(with: request)
    }

    /// Absolute URL on OUR server for a media path, whatever host the message names - a
    /// sender-chosen host would otherwise learn every recipient's IP (same rule as Android).
    func ownServerURL(_ content: String) -> URL? {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var path = URL(string: trimmed)?.path ?? ""
        if path.isEmpty {
            path = trimmed
        }
        if !path.hasPrefix("/") {
            path = "/" + path
        }
        var base = baseURL.absoluteString
        if base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + path)
    }

    /// FastAPI errors: {"detail": "..."} or, for validation, {"detail": [{"msg": "..."}]}.
    private static func detail(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let text = json["detail"] as? String { return text }
        if let items = json["detail"] as? [[String: Any]] {
            return items.compactMap { $0["msg"] as? String }.joined(separator: "; ")
        }
        return nil
    }
}
