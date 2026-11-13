import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Security

@MainActor
public protocol HomeAssistantAuthenticating {
    /** Sign in at the given server and return its access and refresh tokens. */
    func signIn(address: ServerAddress) async throws -> AuthTokens
    /** Obtain an access token using the server's saved refresh token. */
    func refresh(address: ServerAddress, token: String) async throws -> AuthTokens
    /** Revoke the server's refresh token when signing out. */
    func revoke(address: ServerAddress, token: String) async throws
}

public struct AuthTokens: Decodable, Sendable {
    public let access_token: String
    public let refresh_token: String?
    public let expires_in: Double
}

struct AuthorizationRequest {
    static let clientID = "https://homebar.jebrg.com/auth.html"
    static let callback = "com.jeromeberg.homebar://auth-callback"
    let verifier: String
    let state: String

    /** Generate independent cryptographically random PKCE and callback state values. */
    init() throws {
        verifier = try Self.randomValue()
        state = try Self.randomValue()
    }

    /** Build a server authorization URL with S256 PKCE and callback state. */
    func url(address: ServerAddress) -> URL {
        var parts = URLComponents(url: address.baseURL.appendingPathComponent("auth/authorize"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.callback),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return parts.url!
    }

    /** Return a single authorization code only for the expected callback and state. */
    func code(from url: URL) throws -> String {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "com.jeromeberg.homebar", parts.host == "auth-callback",
              parts.path.isEmpty, parts.user == nil, parts.password == nil, parts.port == nil,
              parts.fragment == nil else { throw ConnectionError.authentication }
        let items = parts.queryItems ?? []
        let states = items.filter { $0.name == "state" }
        let codes = items.filter { $0.name == "code" }
        guard states.count == 1, states.first?.value == state,
              codes.count == 1, let code = codes.first?.value, !code.isEmpty,
              !items.contains(where: { $0.name == "error" }) else { throw ConnectionError.authentication }
        return code
    }

    /** Return 32 random bytes encoded without URL-unsafe Base64 characters. */
    private static func randomValue() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw ConnectionError.authentication
        }
        return base64URL(Data(bytes))
    }

    /** Encode data using unpadded Base64 URL encoding. */
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

@MainActor
public final class HomeAssistantAuth: HomeAssistantAuthenticating {
    private let session: URLSession

    /** Use an ephemeral HTTP session, or an injected session for tests. */
    public init(session: URLSession? = nil) {
        self.session = session ?? URLSession(configuration: .ephemeral, delegate: AuthRedirectPolicy(), delegateQueue: nil)
    }

    /** Open the system browser, validate the callback, and exchange its code with PKCE. */
    public func signIn(address: ServerAddress) async throws -> AuthTokens {
        let request = try AuthorizationRequest()
        let callback = try await BrowserLogin().open(url: request.url(address: address))
        try Task.checkCancellation()
        let code = try request.code(from: callback)
        let tokens = try await exchange(address: address, fields: ["grant_type": "authorization_code", "code": code,
            "client_id": AuthorizationRequest.clientID, "code_verifier": request.verifier])
        guard let refresh = tokens.refresh_token, !refresh.isEmpty else { throw ConnectionError.unexpectedResponse }
        return tokens
    }

    /** Exchange a refresh token for a new short-lived access token. */
    public func refresh(address: ServerAddress, token: String) async throws -> AuthTokens {
        try await exchange(address: address, fields: ["grant_type": "refresh_token", "refresh_token": token,
            "client_id": AuthorizationRequest.clientID])
    }

    /** Revoke a login using the endpoint supported by existing Home Assistant versions. */
    public func revoke(address: ServerAddress, token: String) async throws {
        _ = try await send(address: address, fields: ["token": token, "action": "revoke"])
    }

    /** Decode a successful token response and reject empty or expired access tokens. */
    private func exchange(address: ServerAddress, fields: [String: String]) async throws -> AuthTokens {
        let data = try await send(address: address, fields: fields)
        guard let tokens = try? JSONDecoder().decode(AuthTokens.self, from: data),
              !tokens.access_token.isEmpty, tokens.expires_in > 0 else { throw ConnectionError.unexpectedResponse }
        return tokens
    }

    /** POST form fields without logging server bodies or credentials; return successful response data. */
    private func send(address: ServerAddress, fields: [String: String]) async throws -> Data {
        var request = URLRequest(url: address.baseURL.appendingPathComponent("auth/token"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = Data(fields.sorted(by: { $0.key < $1.key }).map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ConnectionError.unexpectedResponse }
        switch response.statusCode {
        case 200: return data
        case 400, 401, 403: throw ConnectionError.authentication
        case 429, 500...599: throw ConnectionError.network(NSURLErrorBadServerResponse)
        default: throw ConnectionError.unexpectedResponse
        }
    }
}

final class AuthRedirectPolicy: NSObject, URLSessionTaskDelegate {
    /** Refuse HTTP redirects so credentials cannot be forwarded to another endpoint. */
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class BrowserLogin: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var browser: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, any Error>?

    /** Await one browser callback, completing cancellation even when the browser sends no callback. */
    func open(url: URL) async throws -> URL {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let browser = ASWebAuthenticationSession(url: url, callbackURLScheme: "com.jeromeberg.homebar",
                    completionHandler: Self.completionHandler { [weak self] url, error in
                        if let url { self?.finish(.success(url)) }
                        else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                            self?.finish(.failure(CancellationError()))
                        } else { self?.finish(.failure(ConnectionError.authentication)) }
                    })
                self.browser = browser
                browser.presentationContextProvider = self
                if !browser.start() { finish(.failure(ConnectionError.authentication)) }
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }

    /** Accept a callback on any queue and deliver its URL or error on the main actor. */
    nonisolated static func completionHandler(
        _ receive: @escaping @MainActor @Sendable (URL?, (any Error)?) -> Void
    ) -> @Sendable (URL?, (any Error)?) -> Void {
        { url, error in
            Task { @MainActor in receive(url, error) }
        }
    }

    /** Resume the pending login once and release its browser session. */
    private func finish(_ result: Result<URL, any Error>) {
        let pending = continuation
        continuation = nil
        browser?.cancel()
        browser = nil
        pending?.resume(with: result)
    }

    /** Anchor browser sign-in to the active application window. */
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}
