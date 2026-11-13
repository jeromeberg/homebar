import Foundation
import Testing
@testable import HomeBarCore

private final class DiscoveryBrowser: NetServiceBrowser {
    var searches = 0
    var stops = 0

    /** Record a search without accessing the network. */
    override func searchForServices(ofType type: String, inDomain domainString: String) {
        #expect(type == "_home-assistant._tcp.")
        #expect(domainString == "local.")
        searches += 1
    }

    /** Record cancellation without accessing the network. */
    override func stop() { stops += 1 }
}

private final class DiscoveryService: NetService {
    override var hostName: String? { "homeassistant.local." }
    var resolutions = 0
    var stops = 0

    /** Record resolution without accessing the network. */
    override func resolve(withTimeout timeout: TimeInterval) { resolutions += 1 }

    /** Record resolution cancellation. */
    override func stop() { stops += 1 }
}

@MainActor
struct ServerDiscoveryTests {
    @Test
    /** Prefer a valid internal HTTPS URL, retaining proxy paths and the advertised name. */
    func internalURL() {
        let server = DiscoveredServer(name: "Fallback", host: "ha.local.", port: 8123, properties: [
            "internal_url": Data("https://ha.example/assistant/".utf8),
            "external_url": Data("https://external.example".utf8),
            "location_name": Data("My Home".utf8)
        ])
        #expect(server?.url == "https://ha.example/assistant")
        #expect(server?.name == "My Home")
    }

    @Test(arguments: ["", "invalid", "https://user:password@ha.local", "ftp://ha.local"])
    /** Fall back to the resolved host and actual port when the internal URL is unusable. */
    func resolvedAddress(_ internalURL: String) {
        let server = DiscoveredServer(name: "Home", host: "ha.local.", port: 1234, properties: [
            "internal_url": Data(internalURL.utf8), "base_url": Data("https://external.example".utf8)
        ])
        #expect(server?.url == "http://ha.local:1234")
        #expect(server?.name == "Home")
    }

    @Test
    /** Ignore installation landing pages and invalid resolved addresses. */
    func invalidRecords() {
        #expect(DiscoveredServer(name: "Setup", host: "ha.local", port: 8123,
                                 properties: ["landingpage": Data("True".utf8)]) == nil)
        #expect(DiscoveredServer(name: "Home", host: "", port: 8123, properties: [:]) == nil)
        #expect(DiscoveredServer(name: "Home", host: "ha.local", port: -1, properties: [:]) == nil)
    }

    @Test
    /** Resolve results once, deduplicate URLs, remove withdrawn servers, and ignore late callbacks after stopping. */
    func lifecycle() {
        let browser = DiscoveryBrowser()
        let discovery = ServerDiscovery(browser: browser)
        let first = DiscoveryService(domain: "local.", type: "_home-assistant._tcp.", name: "Home", port: 8123)
        let second = DiscoveryService(domain: "local.", type: "_home-assistant._tcp.", name: "Duplicate", port: 8123)
        discovery.start()
        discovery.start()
        #expect(browser.searches == 1)
        discovery.netServiceBrowser(browser, didFind: first, moreComing: false)
        discovery.netServiceBrowser(browser, didFind: first, moreComing: false)
        #expect(first.resolutions == 1)
        discovery.netServiceDidResolveAddress(first)
        discovery.netServiceBrowser(browser, didFind: second, moreComing: false)
        discovery.netServiceDidResolveAddress(second)
        #expect(discovery.servers.count == 1)
        #expect(discovery.servers.first?.url == "http://homeassistant.local:8123")
        discovery.netServiceBrowser(browser, didRemove: second, moreComing: false)
        #expect(discovery.servers.first?.name == "Home")
        #expect(second.stops == 1)
        discovery.stop()
        #expect(first.stops == 1)
        #expect(first.delegate == nil)
        discovery.netServiceDidResolveAddress(first)
        #expect(discovery.servers.isEmpty)
        discovery.start()
        #expect(browser.searches == 2)
        discovery.stop()
    }

    @Test
    /** Expose a fixed discovery error and allow a clean retry. */
    func failureAndRetry() {
        let browser = DiscoveryBrowser()
        let discovery = ServerDiscovery(browser: browser)
        discovery.start()
        discovery.netServiceBrowser(browser, didNotSearch: ["NSNetServicesErrorCode": -72008])
        #expect(discovery.error != nil)
        #expect(browser.stops == 1)
        discovery.start()
        #expect(discovery.error == nil)
        #expect(browser.searches == 2)
        discovery.stop()
    }
}
