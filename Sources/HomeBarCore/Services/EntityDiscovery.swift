import Foundation

@MainActor
final class EntityDiscovery {
    private let socket: any WebSocketTransport
    private let store: EntityStore
    private let timeout: Duration
    private var nextID = 1
    private let allocateID: (() -> Int)?
    private var pending: [Int: String] = [:]
    private var deadlines: [Int: Task<Void, Never>] = [:]
    private var subscriptionID: Int?
    private var legacy = false
    private var initial = true
    private var live = false

    /** Bind discovery to the already authenticated socket and its observable store. */
    init(socket: any WebSocketTransport, store: EntityStore, timeout: Duration = .seconds(20), allocateID: (() -> Int)? = nil) {
        self.socket = socket
        self.store = store
        self.timeout = timeout
        self.allocateID = allocateID
    }

    /** Fetch each registry and the current state snapshot once per authenticated connection. */
    func start() async throws {
        for command in ["config/area_registry/list", "config/device_registry/list", "config/entity_registry/list", "get_states"] {
            try await send(command)
        }
    }

    /** Cancel outstanding command deadlines when this connection ends. */
    func close() {
        for task in deadlines.values { task.cancel() }
        deadlines = [:]
        pending = [:]
    }

    /** Route one result by command ID or apply a live event for the current subscription. */
    func receive(_ data: Data) async throws {
        guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = message["type"] as? String, let id = message["id"] as? Int else {
            store.report("Home Assistant sent an unreadable entity message. Reconnect to retry.")
            return
        }
        if type == "event", id == subscriptionID, let event = message["event"] as? [String: Any] {
            do {
                if legacy { try store.applyLegacy(event) }
                else {
                    try store.applyCompressed(event, initial: initial)
                    initial = false
                }
            } catch { store.report("An entity update could not be read. Reconnect to refresh its state.") }
            return
        }
        guard type == "result", let command = pending.removeValue(forKey: id) else { return }
        deadlines.removeValue(forKey: id)?.cancel()
        if message["success"] as? Bool == true {
            if command == "subscribe_entities" || command == "subscribe_events" {
                live = true
                if legacy { try await send("get_states") }
            } else {
                do { try store.load(message["result"] ?? NSNull(), command: command) }
                catch { store.report("The \(name(for: command)) response could not be read. Reconnect to retry.") }
            }
        } else if command == "subscribe_entities",
                  (message["error"] as? [String: Any])?["code"] as? String == "unknown_command" {
            legacy = true
            try await send("subscribe_events")
        } else {
            store.report("Home Assistant could not load \(name(for: command)). Check account permissions and reconnect.")
        }
        if command == "get_states", subscriptionID == nil { try await send("subscribe_entities") }
        updateStatus()
    }

    /** Send a uniquely numbered read command and give its result a bounded deadline. */
    private func send(_ command: String) async throws {
        let id = allocateID?() ?? nextID
        nextID += 1
        pending[id] = command
        var message: [String: Any] = ["id": id, "type": command]
        if command == "subscribe_events" { message["event_type"] = "state_changed" }
        if command == "subscribe_entities" || command == "subscribe_events" { subscriptionID = id }
        deadlines[id] = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: self?.timeout ?? .seconds(20)) }
            catch { return }
            guard let self, let expired = self.pending.removeValue(forKey: id) else { return }
            self.deadlines.removeValue(forKey: id)
            self.store.report("Loading \(self.name(for: expired)) timed out. Reconnect to retry.")
            if expired == "get_states", self.subscriptionID == nil {
                do { try await self.send("subscribe_entities") }
                catch { self.socket.close() }
            }
            self.updateStatus()
        }
        try await socket.send(JSONSerialization.data(withJSONObject: message))
    }

    /** Expose loading completion and live-update availability independently of authentication. */
    private func updateStatus() {
        if pending.isEmpty { store.finish(live: live) }
    }

    /** Return a readable fixed label for command failures without exposing server error text. */
    private func name(for command: String) -> String {
        switch command {
        case "config/area_registry/list": "rooms"
        case "config/device_registry/list": "devices"
        case "config/entity_registry/list": "entities"
        case "get_states": "entity states"
        default: "live entity updates"
        }
    }
}
