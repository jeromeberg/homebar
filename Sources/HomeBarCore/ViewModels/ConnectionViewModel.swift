import AppKit
import Foundation
import Network
import Observation

@MainActor @Observable
public final class ConnectionViewModel {
    public let entities: EntityStore
    public var serverURL: String
    public var tokenInput = ""
    public private(set) var state: ConnectionState = .disconnected
    public private(set) var version: String?
    public private(set) var detail: String?
    public private(set) var hasSavedToken = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let store: any TokenStore
    @ObservationIgnored private let clientFactory: () -> HomeAssistantClient
    @ObservationIgnored private var client: HomeAssistantClient?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var activeCredentials: (ServerAddress, String)?
    @ObservationIgnored private var retryAllowed = false
    @ObservationIgnored private var pendingSave = false
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    public static let serverKey = "homeAssistantServerURL"

    /** Load the saved server, configure optional system recovery signals, and leave connection startup explicit. */
    public init(defaults: UserDefaults = .standard, store: any TokenStore = KeychainService(),
                observeSystem: Bool = true, clientFactory: @escaping () -> HomeAssistantClient = { HomeAssistantClient() }) {
        self.entities = EntityStore(defaults: defaults)
        self.defaults = defaults
        self.store = store
        self.clientFactory = clientFactory
        serverURL = defaults.string(forKey: Self.serverKey) ?? ""
        if observeSystem { observeRecovery() }
    }

    /** Reconnect on app launch only when a complete saved configuration exists. */
    public func restore() {
        guard let address = try? ServerAddress(serverURL) else { return }
        do {
            guard let token = try store.read(for: address.baseURL.absoluteString), !token.isEmpty else { return }
            hasSavedToken = true
            start(address: address, token: token, save: false)
        } catch { fail(.storage) }
    }

    /** Validate form input and use a saved token only for the exact saved server. */
    public func connect() {
        do {
            let address = try ServerAddress(serverURL)
            var token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty, address.baseURL.absoluteString == defaults.string(forKey: Self.serverKey) {
                token = try store.read(for: address.baseURL.absoluteString) ?? ""
            }
            guard !token.isEmpty else { throw ConnectionError.missingToken }
            start(address: address, token: token, save: true)
        } catch { fail(ConnectionError.sanitized(error)) }
    }

    /** Cancel pending attempts and retries while retaining saved credentials for the next launch. */
    public func disconnect() {
        generation += 1
        operation?.cancel()
        client?.disconnect()
        activeCredentials = nil
        entities.disconnected()
        retryAllowed = false
        state = .disconnected
        version = nil
        detail = nil
        tokenInput = ""
    }

    /** Retry immediately after wake or network recovery when an automatic retry is already pending. */
    public func recover() {
        guard retryAllowed, state == .reconnecting, let (address, token) = activeCredentials else { return }
        start(address: address, token: token, save: pendingSave)
    }

    /** Serialize connection lifetimes and retry transient failures with capped exponential delays. */
    private func start(address: ServerAddress, token: String, save: Bool) {
        let previous = operation
        previous?.cancel()
        client?.disconnect()
        generation += 1
        let current = generation
        activeCredentials = (address, token)
        pendingSave = save
        retryAllowed = true
        state = .connecting
        detail = nil
        version = nil
        operation = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, current == self.generation else { return }
            let client = self.clientFactory()
            self.client = client
            var attempt = 0
            var needsSave = save
            while !Task.isCancelled {
                do {
                    try await client.run(address: address, token: token, entities: self.entities) { version in
                        if needsSave {
                            try self.store.save(token, for: address.baseURL.absoluteString)
                            self.defaults.set(address.baseURL.absoluteString, forKey: Self.serverKey)
                            needsSave = false
                            self.pendingSave = false
                        }
                        self.hasSavedToken = true
                        self.tokenInput = ""
                        self.serverURL = address.baseURL.absoluteString
                        self.version = version
                        self.state = .connected
                        self.detail = nil
                        attempt = 0
                    }
                } catch {
                    guard !Task.isCancelled, current == self.generation else { return }
                    let failure = ConnectionError.sanitized(error)
                    self.version = nil
                    self.detail = failure.message
                    guard failure.canRetry else {
                        self.retryAllowed = false
                        self.activeCredentials = nil
                        self.state = .failed(failure.message)
                        return
                    }
                    self.state = .reconnecting
                    do { try await Task.sleep(for: .seconds(ReconnectPolicy.delay(for: attempt))) }
                    catch { return }
                    attempt += 1
                }
            }
        }
    }

    /** Present a validation or persistence failure without changing an existing live connection. */
    private func fail(_ error: ConnectionError) {
        detail = error.message
        if state != .connected && !state.isBusy { state = .failed(error.message) }
    }

    /** Observe network availability and Mac wake without creating additional active connections. */
    private func observeRecovery() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in self?.recover() }
        }
        monitor.start(queue: DispatchQueue(label: "com.jeromeberg.network"))
        self.monitor = monitor
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.state == .connected, let (address, token) = self.activeCredentials {
                    self.start(address: address, token: token, save: self.pendingSave)
                } else { self.recover() }
            }
        }
    }
}
