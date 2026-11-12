import Foundation
import Testing
@testable import HomeBarCore

@MainActor
final class MemoryTokens: TokenStore {
    var tokens: [String: String] = [:]
    var writes = 0
    var rejectWrites = false

    /** Read a test token for one server. */
    func read(for server: String) throws -> String? { tokens[server] }

    /** Save a test token or simulate a Keychain failure. */
    func save(_ token: String, for server: String) throws {
        if rejectWrites { throw ConnectionError.storage }
        tokens[server] = token
        writes += 1
    }
}

@MainActor
final class ScriptedSocket: WebSocketTransport {
    var messages: [String]
    var sent: [Data] = []
    var closed = false
    var failSends = false
    var pending: CheckedContinuation<Data, any Error>?

    var sentTypes: [String] {
        sent.compactMap { (try? JSONSerialization.jsonObject(with: $0) as? [String: Any])?["type"] as? String }
    }

    /** Configure a sequence of synthetic server frames. */
    init(_ messages: [String]) { self.messages = messages }

    /** Return scripted frames, then suspend until closed. */
    func receive() async throws -> Data {
        if closed { throw URLError(.networkConnectionLost) }
        if !messages.isEmpty { return Data(messages.removeFirst().utf8) }
        return try await withCheckedThrowingContinuation { pending = $0 }
    }

    /** Record a client frame without printing credentials. */
    func send(_ data: Data) async throws {
        if failSends { throw URLError(.networkConnectionLost) }
        sent.append(data)
    }

    /** Simulate a healthy WebSocket ping. */
    func ping() async throws {}

    /** Deliver a synthetic live frame to an active receiver or queue it for the next read. */
    func push(_ message: String) {
        if let receiver = pending {
            pending = nil
            receiver.resume(returning: Data(message.utf8))
        } else { messages.append(message) }
    }

    /** End pending reads like a disconnected WebSocket. */
    func close() {
        closed = true
        pending?.resume(throwing: URLError(.networkConnectionLost))
        pending = nil
    }
}

struct AddressTests {
    @Test(arguments: [
        ("http://homeassistant.local:8123///", "http://homeassistant.local:8123", "ws://homeassistant.local:8123/api/websocket"),
        ("https://example.com/ha/", "https://example.com/ha", "wss://example.com/ha/api/websocket"),
        ("http://[::1]:8123", "http://[::1]:8123", "ws://[::1]:8123/api/websocket"),
        (" https://example.com/a%20b/ ", "https://example.com/a%20b", "wss://example.com/a%20b/api/websocket")
    ])
    /** Verify normalized server and WebSocket addresses, including proxy paths. */
    func valid(input: String, base: String, socket: String) throws {
        let address = try ServerAddress(input)
        #expect(address.baseURL.absoluteString == base)
        #expect(address.webSocketURL.absoluteString == socket)
    }

    @Test(arguments: ["homeassistant.local:8123", "ftp://example.com", "http://", "http://a b", "https://user:secret@example.com",
                      "https://example.com?q=1", "https://example.com/#x", "http://example.com:0", "http://example.com:70000"])
    /** Reject ambiguous or unsafe base URLs. */
    func invalid(_ value: String) {
        #expect(throws: ConnectionError.invalidURL) { try ServerAddress(value) }
    }

    @Test
    /** Verify retry delays grow and remain bounded even for extreme attempt counts. */
    func backoff() {
        #expect((0...7).map { ReconnectPolicy.delay(for: $0) } == [1, 2, 4, 8, 16, 30, 30, 30])
        #expect(ReconnectPolicy.delay(for: Int.max) == 30)
        #expect(!ConnectionError.authentication.canRetry)
        #expect(!ConnectionError.network(NSURLErrorServerCertificateUntrusted).canRetry)
        #expect(ConnectionError.timeout.canRetry)
    }
}

@MainActor
struct ConnectionTests {
    private let greeting = #"{"type":"auth_required","ha_version":"2026.11"}"#
    private let accepted = #"{"type":"auth_ok","ha_version":"2026.11"}"#

    /** Create isolated preferences and token storage for a connection model. */
    private func model(socket: ScriptedSocket, store: MemoryTokens = MemoryTokens()) -> (ConnectionViewModel, UserDefaults) {
        let defaults = UserDefaults(suiteName: "HomeBarTests.\(UUID().uuidString)")!
        let model = ConnectionViewModel(defaults: defaults, store: store, observeSystem: false,
            clientFactory: { HomeAssistantClient(handshakeTimeout: .seconds(1), factory: { _ in socket }) })
        return (model, defaults)
    }

    /** Wait briefly for asynchronous state changes, failing if the expected state never arrives. */
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Expected connection state was not reached")
    }

    @Test
    /** Verify auth_ok controls connected state and successful credentials are saved without exposing the form token. */
    func successAndDisconnect() async throws {
        let socket = ScriptedSocket([greeting, accepted])
        let store = MemoryTokens()
        let (model, defaults) = model(socket: socket, store: store)
        model.serverURL = "http://localhost:8123/"
        model.tokenInput = "synthetic-token"
        model.connect()
        #expect(model.state == .connecting)
        #expect(store.writes == 0)
        try await wait { model.state == .connected }
        #expect(model.version == "2026.11")
        #expect(store.writes == 1)
        #expect(model.tokenInput.isEmpty)
        #expect(defaults.string(forKey: ConnectionViewModel.serverKey) == "http://localhost:8123")
        let auth = try #require(socket.sent.first)
        let fields = try #require(JSONSerialization.jsonObject(with: auth) as? [String: String])
        #expect(fields["type"] == "auth")
        #expect(fields["access_token"] == "synthetic-token")
        model.disconnect()
        #expect(model.state == .disconnected)
        #expect(socket.closed)
        model.recover()
        #expect(model.state == .disconnected)
    }

    @Test
    /** Reject auth_invalid and preserve prior server and token, ignoring untrusted server error text. */
    func rejectedCredentials() async throws {
        let socket = ScriptedSocket([greeting, #"{"type":"auth_invalid","message":"synthetic-token"}"#])
        let store = MemoryTokens()
        store.tokens["http://old.local"] = "previous-token"
        let (model, defaults) = model(socket: socket, store: store)
        defaults.set("http://old.local", forKey: ConnectionViewModel.serverKey)
        model.serverURL = "http://new.local"
        model.tokenInput = "synthetic-token"
        model.connect()
        try await wait { if case .failed = model.state { true } else { false } }
        #expect(model.state == .failed(ConnectionError.authentication.message))
        #expect(model.detail?.contains("synthetic-token") == false)
        #expect(store.writes == 0)
        #expect(defaults.string(forKey: ConnectionViewModel.serverKey) == "http://old.local")
        #expect(store.tokens["http://old.local"] == "previous-token")
        model.recover()
        #expect(socket.sent.count == 1)
        model.disconnect()
    }

    @Test
    /** Restore a saved configuration without putting the Keychain token into the editable field. */
    func restoreCredentials() async throws {
        let socket = ScriptedSocket([greeting, accepted])
        let store = MemoryTokens()
        store.tokens["http://saved.local"] = "saved-test-token"
        let (model, defaults) = model(socket: socket, store: store)
        defaults.set("http://saved.local", forKey: ConnectionViewModel.serverKey)
        model.serverURL = "http://saved.local"
        model.restore()
        try await wait { model.state == .connected }
        #expect(model.tokenInput.isEmpty)
        #expect(store.writes == 0)
        model.disconnect()
    }

    @Test
    /** A closed connection enters controlled reconnection and explicit disconnect cancels the retry. */
    func connectionLoss() async throws {
        let socket = ScriptedSocket([greeting, accepted])
        let (model, _) = model(socket: socket)
        model.serverURL = "http://localhost:8123"
        model.tokenInput = "test-token"
        model.connect()
        try await wait { model.state == .connected }
        socket.close()
        try await wait { model.state == .reconnecting }
        model.disconnect()
        try await Task.sleep(for: .milliseconds(1100))
        #expect(model.state == .disconnected)
        #expect(socket.sentTypes == ["auth", "config/area_registry/list", "config/device_registry/list", "config/entity_registry/list", "get_states"])
    }

    @Test
    /** Do not treat an open socket as authenticated, and stop a stalled handshake after its deadline. */
    func handshakeTimeout() async throws {
        let socket = ScriptedSocket([greeting])
        let client = HomeAssistantClient(handshakeTimeout: .milliseconds(20), factory: { _ in socket })
        var authenticated = false
        do {
            try await client.run(address: ServerAddress("http://localhost"), token: "test-token") { _ in authenticated = true }
            Issue.record("A stalled handshake must fail")
        } catch { #expect(error as? ConnectionError == .timeout) }
        #expect(!authenticated)
        #expect(socket.closed)
    }

    @Test
    /** Keep the previous configuration if Keychain refuses a newly validated token. */
    func persistenceFailure() async throws {
        let store = MemoryTokens()
        store.rejectWrites = true
        let socket = ScriptedSocket([greeting, accepted])
        let (model, defaults) = model(socket: socket, store: store)
        defaults.set("http://old.local", forKey: ConnectionViewModel.serverKey)
        model.serverURL = "http://new.local"
        model.tokenInput = "test-token"
        model.connect()
        try await wait { model.state == .failed(ConnectionError.storage.message) }
        #expect(defaults.string(forKey: ConnectionViewModel.serverKey) == "http://old.local")
        #expect(socket.closed)
        model.disconnect()
    }

    @Test
    /** Reject an unexpected handshake frame without sending the token. */
    func unexpectedResponse() async throws {
        let socket = ScriptedSocket([accepted])
        let client = HomeAssistantClient(factory: { _ in socket })
        do {
            try await client.run(address: ServerAddress("http://localhost"), token: "test-token") { _ in Issue.record("Unexpected authentication") }
            Issue.record("Unexpected response must fail")
        } catch { #expect(error as? ConnectionError == .unexpectedResponse) }
        #expect(socket.sent.isEmpty)
    }
    @Test
    /** Retry a transient failure and preserve pending credentials when network recovery expedites it. */
    func recoverySavesPendingCredentials() async throws {
        let first = ScriptedSocket([])
        first.close()
        let second = ScriptedSocket([greeting, accepted])
        let defaults = UserDefaults(suiteName: "HomeBarTests.\(UUID().uuidString)")!
        let store = MemoryTokens()
        var opened = 0
        let model = ConnectionViewModel(defaults: defaults, store: store, observeSystem: false,
            clientFactory: { HomeAssistantClient(factory: { _ in
                opened += 1
                return opened == 1 ? first : second
            }) })
        model.serverURL = "http://new.local/"
        model.tokenInput = "test-token"
        model.connect()
        try await wait { model.state == .reconnecting }
        #expect(store.writes == 0)
        model.recover()
        try await wait { model.state == .connected }
        #expect(opened == 2)
        #expect(first.closed)
        #expect(store.writes == 1)
        #expect(defaults.string(forKey: ConnectionViewModel.serverKey) == "http://new.local")
        model.disconnect()
    }

    @Test
    /** Reconnect automatically after the first backoff delay using a fresh socket. */
    func automaticRetry() async throws {
        let first = ScriptedSocket([])
        first.close()
        let second = ScriptedSocket([greeting, accepted])
        let defaults = UserDefaults(suiteName: "HomeBarTests.\(UUID().uuidString)")!
        var opened = 0
        let model = ConnectionViewModel(defaults: defaults, store: MemoryTokens(), observeSystem: false,
            clientFactory: { HomeAssistantClient(factory: { _ in
                opened += 1
                return opened == 1 ? first : second
            }) })
        model.serverURL = "http://localhost"
        model.tokenInput = "test-token"
        model.connect()
        try await wait { model.state == .reconnecting }
        #expect(opened == 1)
        try await Task.sleep(for: .milliseconds(1100))
        try await wait { model.state == .connected }
        #expect(opened == 2)
        model.disconnect()
    }

}
