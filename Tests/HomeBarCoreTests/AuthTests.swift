import CryptoKit
import Foundation
import Testing
@testable import HomeBarCore

final class AuthHTTPStub: URLProtocol, @unchecked Sendable {
    /** Intercept synthetic auth requests only. */
    override class func canInit(with request: URLRequest) -> Bool { true }

    /** Preserve the request for the synthetic response. */
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /** Return token responses or fixed errors without making a network connection. */
    override func startLoading() {
        let status: Int
        let body: String
        switch request.url?.host {
        case "rejected.local": status = 400; body = #"{"error":"invalid_grant","error_description":"private-server-text"}"#
        case "offline.local": status = 503; body = ""
        case "malformed.local": status = 200; body = #"{"access_token":"","expires_in":1800}"#
        default: status = 200; body = #"{"access_token":"renewed-access","expires_in":1800}"#
        }
        if request.url?.host == "good.local" {
            #expect(request.url?.path == "/proxy/auth/token")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
            }
            let form = URLComponents(string: "https://example.com/?" + String(decoding: data, as: UTF8.self))?.queryItems ?? []
            #expect(form.contains(URLQueryItem(name: "refresh_token", value: "refresh+&=")))
            #expect(form.contains(URLQueryItem(name: "grant_type", value: "refresh_token")))
            #expect(form.contains(URLQueryItem(name: "client_id", value: AuthorizationRequest.clientID)))
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    /** No asynchronous I/O needs cancellation in this stub. */
    override func stopLoading() {}
}

@MainActor
final class FakeAuth: HomeAssistantAuthenticating {
    var refreshes = 0
    var revocations = 0
    var rejected = false
    var cancelled = false
    var waitForCancellation = false

    /** Return synthetic login tokens or wait for the caller to cancel. */
    func signIn(address: ServerAddress) async throws -> AuthTokens {
        if cancelled { throw CancellationError() }
        if waitForCancellation { try await Task.sleep(for: .seconds(30)) }
        return AuthTokens(access_token: "login-access", refresh_token: "login-refresh", expires_in: 1800)
    }

    /** Count renewals and simulate revoked authorization when requested. */
    func refresh(address: ServerAddress, token: String) async throws -> AuthTokens {
        refreshes += 1
        if rejected { throw ConnectionError.authentication }
        return AuthTokens(access_token: "renewed-access", refresh_token: nil, expires_in: 1800)
    }

    /** Record revocation without contacting a server. */
    func revoke(address: ServerAddress, token: String) async throws { revocations += 1 }
}

@MainActor
struct AuthTests {
    private let frames = [#"{"type":"auth_required"}"#, #"{"type":"auth_ok"}"#]

    /** Wait for an asynchronous auth state with a short deadline. */
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Expected auth state was not reached")
    }

    @Test(arguments: [false, true])
    /** Deliver background browser success and failure callbacks on the main actor without trapping. */
    func backgroundBrowserCallback(failed: Bool) async {
        let expectedURL = URL(string: AuthorizationRequest.callback)!
        let received: Bool = await withCheckedContinuation { continuation in
            let handler = BrowserLogin.completionHandler { url, error in
                MainActor.assertIsolated()
                if failed {
                    continuation.resume(returning: url == nil && (error as? ConnectionError) == .authentication)
                } else {
                    continuation.resume(returning: url == expectedURL && error == nil)
                }
            }
            Task.detached {
                handler(failed ? nil : expectedURL, failed ? ConnectionError.authentication : nil)
            }
        }
        #expect(received)
    }

    @Test
    /** Verify PKCE challenge generation, callback state, proxy paths, and strict callback validation. */
    func authorizationRequest() throws {
        let request = try AuthorizationRequest()
        let second = try AuthorizationRequest()
        #expect(request.state != second.state)
        #expect(request.verifier != second.verifier)
        #expect(request.verifier.count == 43)
        let url = request.url(address: try ServerAddress("https://ha.local/prefix"))
        #expect(url.path == "/prefix/auth/authorize")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let digest = Data(SHA256.hash(data: Data(request.verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        #expect(items.contains(URLQueryItem(name: "code_challenge", value: digest)))
        #expect(items.contains(URLQueryItem(name: "code_challenge_method", value: "S256")))
        let callback = "\(AuthorizationRequest.callback)?code=one-use-code&state=\(request.state)"
        #expect(try request.code(from: URL(string: callback)!) == "one-use-code")
        for invalid in [callback + "&code=duplicate", callback + "&state=duplicate", callback + "&error=denied",
                        callback.replacingOccurrences(of: request.state, with: "wrong"),
                        callback.replacingOccurrences(of: "auth-callback", with: "other"),
                        callback.replacingOccurrences(of: "com.jeromeberg.homebar", with: "other"), callback + "#fragment"] {
            #expect(throws: ConnectionError.authentication) { try request.code(from: URL(string: invalid)!) }
        }
    }

    @Test
    /** Decode successful refreshes and classify server errors without exposing their bodies. */
    func tokenResponses() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuthHTTPStub.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let auth = HomeAssistantAuth(session: session)
        let tokens = try await auth.refresh(address: ServerAddress("https://good.local/proxy"), token: "refresh+&=")
        #expect(tokens.access_token == "renewed-access")
        #expect(tokens.refresh_token == nil)
        for (host, expected) in [("rejected", ConnectionError.authentication), ("offline", .network(NSURLErrorBadServerResponse)), ("malformed", .unexpectedResponse)] {
            do {
                _ = try await auth.refresh(address: ServerAddress("https://\(host).local"), token: "synthetic")
                Issue.record("Expected token exchange failure")
            } catch { #expect(error as? ConnectionError == expected) }
        }
    }

    @Test
    /** Save only refresh credentials after auth_ok, restore by renewing, and remove them on sign-out. */
    func signInRestoreAndSignOut() async throws {
        let defaults = UserDefaults(suiteName: "HomeBarAuthTests.\(UUID().uuidString)")!
        let legacy = MemoryTokens()
        let refresh = MemoryTokens()
        let auth = FakeAuth()
        legacy.tokens["http://ha.local"] = "old-legacy-token"
        var sockets: [ScriptedSocket] = []
        let model = ConnectionViewModel(defaults: defaults, store: legacy, observeSystem: false, refreshStore: refresh, auth: auth,
            clientFactory: { HomeAssistantClient(factory: { _ in
                let socket = ScriptedSocket(frames)
                sockets.append(socket)
                return socket
            }) })
        model.serverURL = "http://ha.local"
        model.signIn()
        try await wait { model.state == .connected }
        #expect(refresh.tokens["http://ha.local"] == "login-refresh")
        #expect(legacy.writes == 0)
        #expect(legacy.tokens.isEmpty)
        #expect(auth.refreshes == 0)
        model.disconnect()
        model.restore()
        try await wait { model.state == .connected }
        #expect(auth.refreshes == 1)
        let fields = try #require(JSONSerialization.jsonObject(with: sockets.last!.sent[0]) as? [String: String])
        #expect(fields["access_token"] == "renewed-access")
        sockets.last!.close()
        try await wait { model.state == .reconnecting }
        model.recover()
        try await wait { model.state == .connected }
        #expect(auth.refreshes == 2)
        model.signOut()
        try await wait { auth.revocations == 1 }
        #expect(refresh.tokens.isEmpty)
        #expect(!model.hasSavedToken)
        #expect(defaults.string(forKey: ConnectionViewModel.serverKey) == nil)
        #expect(model.state == .disconnected)
    }

    @Test
    /** Clear revoked refresh tokens and stop retries instead of falling back to a legacy token. */
    func rejectedRefresh() async throws {
        let defaults = UserDefaults(suiteName: "HomeBarAuthTests.\(UUID().uuidString)")!
        defaults.set("http://ha.local", forKey: ConnectionViewModel.serverKey)
        let refresh = MemoryTokens()
        refresh.tokens["http://ha.local"] = "revoked"
        let auth = FakeAuth()
        auth.rejected = true
        var opened = false
        let model = ConnectionViewModel(defaults: defaults, store: MemoryTokens(), observeSystem: false, refreshStore: refresh, auth: auth,
            clientFactory: { opened = true; return HomeAssistantClient() })
        model.restore()
        try await wait { model.state == .failed(ConnectionError.authentication.message) }
        #expect(refresh.tokens.isEmpty)
        #expect(auth.refreshes == 1)
        model.recover()
        #expect(auth.refreshes == 1)
        #expect(!model.hasSavedToken)
        #expect(opened)
        model.disconnect()
    }

    @Test
    /** Retry a rejected access token once with a fresh token before accepting the socket. */
    func rejectedAccessToken() async throws {
        let auth = FakeAuth()
        var opened = 0
        let refresh = MemoryTokens()
        let model = ConnectionViewModel(defaults: UserDefaults(suiteName: "HomeBarAuthTests.\(UUID().uuidString)")!,
            store: MemoryTokens(), observeSystem: false, refreshStore: refresh, auth: auth,
            clientFactory: { HomeAssistantClient(factory: { _ in
                opened += 1
                return ScriptedSocket(opened == 1 ? [frames[0], #"{"type":"auth_invalid"}"#] : frames)
            }) })
        model.serverURL = "http://ha.local"
        model.signIn()
        try await wait { model.state == .connected }
        #expect(opened == 2)
        #expect(auth.refreshes == 1)
        #expect(refresh.tokens["http://ha.local"] == "login-refresh")
        model.disconnect()
    }

    @Test(arguments: [false, true])
    /** Preserve previous credentials when WebSocket auth or refresh-token persistence fails. */
    func failedSignIn(storageFailure: Bool) async throws {
        let defaults = UserDefaults(suiteName: "HomeBarAuthTests.\(UUID().uuidString)")!
        defaults.set("http://old.local", forKey: ConnectionViewModel.serverKey)
        let refresh = MemoryTokens()
        refresh.tokens["http://old.local"] = "old-refresh"
        refresh.rejectWrites = storageFailure
        let socket = ScriptedSocket(storageFailure ? frames : [frames[0], #"{"type":"auth_invalid"}"#])
        let auth = FakeAuth()
        auth.rejected = !storageFailure
        let model = ConnectionViewModel(defaults: defaults, store: MemoryTokens(), observeSystem: false, refreshStore: refresh,
            auth: auth, clientFactory: { HomeAssistantClient(factory: { _ in socket }) })
        model.serverURL = "http://new.local"
        model.signIn()
        let expected = storageFailure ? ConnectionError.storage : .authentication
        try await wait { model.state == .failed(expected.message) }
        #expect(defaults.string(forKey: ConnectionViewModel.serverKey) == "http://old.local")
        #expect(refresh.tokens == ["http://old.local": "old-refresh"])
        #expect(socket.closed)
        model.disconnect()
    }

    @Test(arguments: [false, true])
    /** Browser cancellation and explicit disconnect never save credentials or start a connection. */
    func cancelledSignIn(explicit: Bool) async throws {
        let auth = FakeAuth()
        auth.cancelled = !explicit
        auth.waitForCancellation = explicit
        let refresh = MemoryTokens()
        let model = ConnectionViewModel(defaults: UserDefaults(suiteName: "HomeBarAuthTests.\(UUID().uuidString)")!,
            store: MemoryTokens(), observeSystem: false, refreshStore: refresh, auth: auth)
        model.serverURL = "http://ha.local"
        model.signIn()
        if explicit { model.disconnect() }
        try await wait { model.state == .disconnected }
        #expect(refresh.writes == 0)
    }
}
