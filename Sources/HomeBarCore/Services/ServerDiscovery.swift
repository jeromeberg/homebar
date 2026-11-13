import Foundation
import Observation

public struct DiscoveredServer: Identifiable, Equatable, Sendable {
    public var id: String { url }
    public let name: String
    public let url: String

    /** Build a server from resolved Bonjour data, preferring its valid internal URL. Return nil for setup-only records or invalid addresses. */
    init?(name: String, host: String, port: Int, properties: [String: Data]) {
        guard properties["landingpage"] == nil else { return nil }
        let internalURL = properties["internal_url"].flatMap { String(data: $0, encoding: .utf8) }
        if let internalURL, let address = try? ServerAddress(internalURL) {
            url = address.baseURL.absoluteString
        } else {
            guard !host.isEmpty, (1...65535).contains(port) else { return nil }
            var parts = URLComponents()
            parts.scheme = "http"
            parts.host = host.hasSuffix(".") ? String(host.dropLast()) : host
            parts.port = port
            guard let value = parts.url, let address = try? ServerAddress(value.absoluteString) else { return nil }
            url = address.baseURL.absoluteString
        }
        let location = properties["location_name"].flatMap { String(data: $0, encoding: .utf8) }
        self.name = location.flatMap { $0.isEmpty ? nil : $0 } ?? name
    }
}

@MainActor @Observable
public final class ServerDiscovery: NSObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    public private(set) var servers: [DiscoveredServer] = []
    public private(set) var error: String?

    @ObservationIgnored private let browser: NetServiceBrowser
    @ObservationIgnored private var services: Set<NetService> = []
    @ObservationIgnored private var resolved: [NetService: DiscoveredServer] = [:]
    @ObservationIgnored private var isBrowsing = false

    /** Create a local service browser. The browser parameter allows isolated discovery tests. */
    public init(browser: NetServiceBrowser = NetServiceBrowser()) {
        self.browser = browser
        super.init()
        browser.delegate = self
    }

    /** Start one continuous LAN search without changing the connection form. */
    public func start() {
        guard !isBrowsing else { return }
        error = nil
        isBrowsing = true
        browser.searchForServices(ofType: "_home-assistant._tcp.", inDomain: "local.")
    }

    /** Cancel browsing and pending resolutions, and discard stale results. */
    public func stop() {
        isBrowsing = false
        browser.stop()
        for service in services {
            service.delegate = nil
            service.stop()
        }
        services.removeAll()
        resolved.removeAll()
        servers.removeAll()
    }

    /** Resolve each discovered service once, with a short timeout. */
    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard isBrowsing, browser === self.browser, services.insert(service).inserted else { return }
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    /** Remove withdrawn services and cancel any pending resolution. */
    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        guard isBrowsing, browser === self.browser, let removed = services.remove(service) else { return }
        removed.delegate = nil
        removed.stop()
        resolved.removeValue(forKey: removed)
        updateServers()
    }

    /** Report discovery failures without blocking manual connection. */
    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        guard isBrowsing, browser === self.browser else { return }
        stop()
        error = "Local discovery is unavailable. Check HomeBar’s Local Network permission or enter the URL manually."
    }

    /** Convert a resolved service to a selectable server, ignoring callbacks after cancellation. */
    public func netServiceDidResolveAddress(_ sender: NetService) {
        guard isBrowsing, services.contains(sender), let host = sender.hostName else { return }
        let properties = sender.txtRecordData().map(NetService.dictionary(fromTXTRecord:)) ?? [:]
        resolved[sender] = DiscoveredServer(name: sender.name, host: host, port: sender.port, properties: properties)
        updateServers()
    }

    /** Publish unique URLs in a stable display order. */
    private func updateServers() {
        var urls: Set<String> = []
        servers = resolved.values.sorted {
            $0.name == $1.name ? $0.url < $1.url : $0.name < $1.name
        }.filter { urls.insert($0.url).inserted }
    }
}
