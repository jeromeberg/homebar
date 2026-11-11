import Foundation

public enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed(String)

    public var label: String {
        switch self {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .reconnecting: "Reconnecting…"
        case .failed: "Connection failed"
        }
    }

    public var isBusy: Bool { self == .connecting || self == .reconnecting }
}

public enum ConnectionError: Error, Equatable, Sendable {
    case invalidURL
    case missingToken
    case authentication
    case unexpectedResponse
    case timeout
    case storage
    case network(Int)

    public var message: String {
        switch self {
        case .invalidURL: "Enter a valid http:// or https:// server URL without credentials, a query, or a fragment."
        case .missingToken: "Enter a Home Assistant access token."
        case .authentication: "Home Assistant rejected the token. Create a new token and try again."
        case .unexpectedResponse: "The server returned an unexpected response. Check the Home Assistant URL."
        case .timeout: "The connection timed out. Check the server and your network."
        case .storage: "Unable to access macOS Keychain. Check Keychain access and try again."
        case .network(let code):
            switch code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost: "The network connection is unavailable. HomeBar will retry."
            case NSURLErrorAppTransportSecurityRequiresSecureConnection: "macOS requires a secure connection for this address. Use HTTPS or a local IP address. Contact the server administrator if needed."
            case NSURLErrorCannotConnectToHost: "Connection refused. Check the server address and port. HomeBar will retry."
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: "The server could not be found. Check its address. HomeBar will retry."
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate,
                 NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
                 NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected,
                 NSURLErrorClientCertificateRequired: "A secure connection could not be established. Check the server’s TLS certificate."
            default: "The connection was interrupted. HomeBar will retry."
            }
        }
    }

    public var canRetry: Bool {
        switch self {
        case .timeout: true
        case .network(let code): !Self.tlsCodes.contains(code) && code != NSURLErrorAppTransportSecurityRequiresSecureConnection
        default: false
        }
    }

    private static let tlsCodes = [NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate,
        NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
        NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected, NSURLErrorClientCertificateRequired]

    /** Convert an error to a fixed message category without including server text or credentials. */
    public static func sanitized(_ error: Error) -> Self {
        if let error = error as? Self { return error }
        let error = error as NSError
        if error.domain == NSURLErrorDomain {
            return error.code == NSURLErrorTimedOut ? .timeout : .network(error.code)
        }
        return .network(NSURLErrorUnknown)
    }
}

public struct ServerAddress: Equatable, Sendable {
    public let baseURL: URL
    public let webSocketURL: URL

    /** Validate an HTTP(S) base address and append the WebSocket path, retaining any proxy prefix. */
    public init(_ input: String) throws {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.contains(where: { $0.isWhitespace }),
              var parts = URLComponents(string: value),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.port.map({ (1...65535).contains($0) }) ?? true else { throw ConnectionError.invalidURL }
        parts.scheme = scheme
        while parts.percentEncodedPath.hasSuffix("/") { parts.percentEncodedPath.removeLast() }
        guard let base = parts.url else { throw ConnectionError.invalidURL }
        baseURL = base
        parts.scheme = scheme == "https" ? "wss" : "ws"
        parts.percentEncodedPath += "/api/websocket"
        guard let socket = parts.url else { throw ConnectionError.invalidURL }
        webSocketURL = socket
    }
}

public enum ReconnectPolicy {
    /** Return the bounded retry delay in seconds for a zero-based consecutive failure count. */
    public static func delay(for attempt: Int) -> Double {
        min(30, pow(2, Double(max(0, min(attempt, 5)))))
    }
}
