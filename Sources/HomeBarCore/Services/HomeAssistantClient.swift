import Foundation

@MainActor
public protocol WebSocketTransport: AnyObject {
    /** Return the next message as data or throw when the socket closes. */
    func receive() async throws -> Data
    /** Send JSON data as one text frame. */
    func send(_ data: Data) async throws
    /** Wait for a WebSocket pong or throw on failure. */
    func ping() async throws
    /** Close the connection and unblock pending operations. */
    func close()
}

@MainActor
final class URLSessionTransport: WebSocketTransport {
    private let session: URLSession
    private let socket: URLSessionWebSocketTask

    /** Open one ephemeral WebSocket without cookies or persistent caches. */
    init(url: URL) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
        socket = session.webSocketTask(with: url)
        socket.maximumMessageSize = 16 * 1_048_576
        socket.resume()
    }

    /** Receive one text or binary WebSocket message as UTF-8 data. */
    func receive() async throws -> Data {
        switch try await socket.receive() {
        case .string(let value): Data(value.utf8)
        case .data(let data): data
        @unknown default: throw ConnectionError.unexpectedResponse
        }
    }

    /** Send a JSON authentication message as a text frame. */
    func send(_ data: Data) async throws {
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }

    /** Check the underlying WebSocket connection with a protocol ping. */
    func ping() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            socket.sendPing { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    /** Close the socket and invalidate its owning session. */
    func close() {
        socket.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }
}

@MainActor
public final class HomeAssistantClient {
    private var transport: (any WebSocketTransport)?
    private let factory: (URL) -> any WebSocketTransport
    private let handshakeTimeout: Duration
    private let heartbeatInterval: Duration

    /** Configure a client with optional test transport and lifecycle timing. */
    public init(handshakeTimeout: Duration = .seconds(20), heartbeatInterval: Duration = .seconds(30),
                factory: ((URL) -> any WebSocketTransport)? = nil) {
        self.handshakeTimeout = handshakeTimeout
        self.heartbeatInterval = heartbeatInterval
        self.factory = factory ?? { URLSessionTransport(url: $0) }
    }

    /** Authenticate, notify the caller only after auth_ok, and receive until cancelled or disconnected. */
    public func run(address: ServerAddress, token: String, entities: EntityStore? = nil, authenticated: (String?) throws -> Void) async throws {
        let socket = factory(address.webSocketURL)
        transport = socket
        defer { socket.close(); transport = nil }
        var timedOut = false
        let watchdog = Task { @MainActor in
            try await Task.sleep(for: handshakeTimeout)
            timedOut = true
            socket.close()
        }
        defer { watchdog.cancel() }
        let version: String?
        do {
            version = try await authenticate(socket, token: token)
        } catch {
            if timedOut { throw ConnectionError.timeout }
            throw error
        }
        watchdog.cancel()
        try Task.checkCancellation()
        try authenticated(version)
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                try await Task.sleep(for: heartbeatInterval)
                let deadline = Task { @MainActor in
                    try await Task.sleep(for: .seconds(10))
                    socket.close()
                }
                do { try await socket.ping(); deadline.cancel() }
                catch { deadline.cancel(); socket.close(); return }
            }
        }
        defer { heartbeat.cancel() }
        let discovery = entities.map { EntityDiscovery(socket: socket, store: $0) }
        defer { discovery?.close(); entities?.disconnected() }
        if let entities { entities.begin(server: address.baseURL.absoluteString) }
        try await discovery?.start()
        while !Task.isCancelled {
            let data = try await socket.receive()
            try Task.checkCancellation()
            try await discovery?.receive(data)
        }
        throw CancellationError()
    }

    /** Stop all pending I/O so an explicit disconnect completes immediately. */
    public func disconnect() { transport?.close() }

    /** Perform the two-message official handshake and return the authenticated server version. */
    private func authenticate(_ socket: any WebSocketTransport, token: String) async throws -> String? {
        let greeting = try await message(from: socket)
        guard greeting.type == "auth_required" else { throw ConnectionError.unexpectedResponse }
        let data = try JSONEncoder().encode(Authentication(type: "auth", access_token: token))
        try await socket.send(data)
        let reply = try await message(from: socket)
        switch reply.type {
        case "auth_ok": return reply.ha_version
        case "auth_invalid": throw ConnectionError.authentication
        default: throw ConnectionError.unexpectedResponse
        }
    }

    /** Decode only protocol fields needed for authentication, discarding server-provided error text. */
    private func message(from socket: any WebSocketTransport) async throws -> Message {
        let data = try await socket.receive()
        guard let message = try? JSONDecoder().decode(Message.self, from: data) else {
            throw ConnectionError.unexpectedResponse
        }
        return message
    }

    private struct Message: Decodable { let type: String; let ha_version: String? }
    private struct Authentication: Encodable { let type: String; let access_token: String }
}
