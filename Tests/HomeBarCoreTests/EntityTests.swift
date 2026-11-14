import Foundation
import Testing
@testable import HomeBarCore

@MainActor
struct EntityTests {
    /** Create an isolated preferences store and entity store for each test. */
    private func store() -> (EntityStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "HomeBarEntityTests.\(UUID().uuidString)")!
        return (EntityStore(defaults: defaults), defaults)
    }

    /** Decode a synthetic JSON fixture into its ordinary Foundation representation. */
    private func json(_ value: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(value.utf8))
    }

    /** Build a result frame without relying on network access or real credentials. */
    private func result(_ id: Int, value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["id": id, "type": "result", "success": true, "result": value])
    }

    @Test
    /** Retain ISO timestamps from snapshots and legacy events, including optional fractional seconds. */
    func sensorUpdateTimeFromNormalStates() throws {
        let (store, _) = store()
        try store.load(json(#"[{"entity_id":"sensor.temperature","state":"21","attributes":{},"last_changed":"2026-11-14T09:00:00+00:00","last_updated":"2026-11-14T10:00:00.123456+00:00"}]"#), command: "get_states")
        let initial = try #require(store.entities.first?.lastUpdated)
        #expect(abs(initial.timeIntervalSince1970 - 1_794_650_400.123456) < 0.001)

        try store.applyLegacy(["data": ["entity_id": "sensor.temperature", "new_state": [
            "state": "21", "attributes": [:], "last_updated": "2026-11-14T12:00:00+01:00"
        ]]])
        #expect(store.entities.first?.lastUpdated == Date(timeIntervalSince1970: 1_794_654_000))
    }

    @Test
    /** Track compressed update times, using last_changed when last_updated is omitted. */
    func sensorUpdateTimeFromCompressedStates() throws {
        let (store, _) = store()
        try store.applyCompressed(["a": ["sensor.temperature": [
            "s": "21", "a": [:], "lc": 1_000.0, "lu": 2_000.5
        ]]], initial: true)
        #expect(store.entities.first?.lastUpdated == Date(timeIntervalSince1970: 2_000.5))

        try store.applyCompressed(["c": ["sensor.temperature": ["+": ["lu": 3_000.0]]]], initial: false)
        #expect(store.entities.first?.state == "21")
        #expect(store.entities.first?.lastUpdated == Date(timeIntervalSince1970: 3_000))

        try store.applyCompressed(["c": ["sensor.temperature": ["+": ["s": "22", "lc": 4_000.0]]]], initial: false)
        #expect(store.entities.first?.lastUpdated == Date(timeIntervalSince1970: 4_000))
        try store.applyCompressed(["c": ["sensor.temperature": ["+": ["a": ["friendly_name": "Temperature"]]]]], initial: false)
        #expect(store.entities.first?.lastUpdated == Date(timeIntervalSince1970: 4_000))

        store.disconnected()
        #expect(store.entities.first?.lastUpdated == Date(timeIntervalSince1970: 4_000))
        try store.applyCompressed(["a": ["sensor.temperature": [
            "s": "23", "a": [:], "lc": 5_000.0
        ]]], initial: true)
        #expect(store.entities.first?.lastUpdated == Date(timeIntervalSince1970: 5_000))
    }

    @Test
    /** Leave missing or malformed timestamps unavailable without losing the sensor value. */
    func sensorUpdateTimeUnavailable() throws {
        let (store, _) = store()
        try store.load(json(#"[{"entity_id":"sensor.temperature","state":"21","attributes":{}},{"entity_id":"sensor.humidity","state":"50","attributes":{},"last_updated":"invalid"}]"#), command: "get_states")
        #expect(store.entities.count == 2)
        #expect(store.entities.allSatisfy { $0.lastUpdated == nil })
        try store.applyCompressed(["a": ["sensor.temperature": ["s": "22", "a": [:]]]], initial: true)
        #expect(store.entities.first?.lastUpdated == nil)
        try store.applyLegacy(["data": ["entity_id": "sensor.temperature", "new_state": [
            "state": "23", "attributes": [:], "last_updated": "invalid"
        ]]])
        #expect(store.entities.first?.state == "23")
        #expect(store.entities.first?.lastUpdated == nil)
    }

    @Test
    /** Resolve direct and device rooms, friendly names, units, filtering, and unregistered states. */
    func discoveryAndFiltering() throws {
        let (store, _) = store()
        try store.load(json(#"[{"area_id":"bed","name":"Bedroom"},{"area_id":"desk","name":"Office"}]"#), command: "config/area_registry/list")
        try store.load(json(#"[{"id":"lamp-device","area_id":"bed"},{"id":"disabled-device","disabled_by":"user"}]"#), command: "config/device_registry/list")
        try store.load(json(#"[{"entity_id":"light.desk","device_id":"lamp-device","area_id":"desk","name":"Desk Lamp"},{"entity_id":"fan.bed","device_id":"lamp-device"},{"entity_id":"sensor.diagnostic","entity_category":"diagnostic"},{"entity_id":"sensor.hidden","hidden_by":"user"},{"entity_id":"light.disabled","disabled_by":"integration"},{"entity_id":"sensor.device_disabled","device_id":"disabled-device"},{"entity_id":"switch.plug"}]"#), command: "config/entity_registry/list")
        try store.load(json(#"[{"entity_id":"light.desk","state":"on","attributes":{}},{"entity_id":"fan.bed","state":"off","attributes":{"friendly_name":"Bedroom Fan"}},{"entity_id":"sensor.temperature","state":"21.4","attributes":{"friendly_name":"Temperature","unit_of_measurement":"°C","device_class":"temperature","ignored_attribute":[1,2]}},{"entity_id":"switch.other","state":"on","attributes":{}}]"#), command: "get_states")
        let entities = Dictionary(uniqueKeysWithValues: store.entities.map { ($0.id, $0) })
        #expect(entities["light.desk"]?.room == "Office")
        #expect(entities["fan.bed"]?.room == "Bedroom")
        #expect(entities["fan.bed"]?.name == "Bedroom Fan")
        #expect(entities["sensor.temperature"]?.room == "Other")
        #expect(entities["sensor.temperature"]?.stateLabel == "21.4°C")
        #expect(entities["sensor.temperature"]?.symbol == "thermometer.medium")
        #expect(entities["switch.plug"]?.state == "unavailable")
        #expect(entities["switch.other"]?.state == "on")
        let visible = store.groups(search: "", showHidden: false).flatMap(\.entities)
        #expect(Set(visible.map(\.id)) == ["light.desk", "fan.bed", "sensor.temperature", "switch.plug", "switch.other"])
        #expect(store.groups(search: "", showHidden: false).last?.name == "Other")
        #expect(store.groups(search: "BEDROOM", showHidden: false).flatMap(\.entities).map(\.id) == ["fan.bed"])
        #expect(store.groups(search: "", showHidden: true).flatMap(\.entities).count == 9)
    }

    @Test(arguments: ["", " \n\t"])
    /** Skip blank names and retain friendly, original, and entity ID fallbacks. */
    func blankEntityNames(blank: String) throws {
        let (store, _) = store()
        try store.load([
            ["entity_id": "sensor.water_ocea_cold_water", "name": blank],
            ["entity_id": "light.chevet_timothee", "name": blank],
            ["entity_id": "sensor.original", "name": blank, "original_name": "Original Name"],
            ["entity_id": "sensor.fallback_name", "name": blank, "original_name": blank]
        ], command: "config/entity_registry/list")
        try store.load(json(#"[{"entity_id":"sensor.water_ocea_cold_water","state":"4.48","attributes":{"friendly_name":"Water OCEA","unit_of_measurement":"m³","device_class":"water"}},{"entity_id":"light.chevet_timothee","state":"off","attributes":{"friendly_name":"chevet Timothée","supported_color_modes":["onoff"],"supported_features":0}}]"#), command: "get_states")
        for id in ["sensor.original", "sensor.fallback_name"] {
            try store.applyLegacy(["data": ["entity_id": id, "new_state": [
                "state": "0", "attributes": ["friendly_name": blank]
            ]]])
        }
        let names = Dictionary(uniqueKeysWithValues: store.entities.map { ($0.id, $0.name) })
        #expect(names["sensor.water_ocea_cold_water"] == "Water OCEA")
        #expect(names["light.chevet_timothee"] == "chevet Timothée")
        #expect(names["sensor.original"] == "Original Name")
        #expect(names["sensor.fallback_name"] == "Fallback Name")
    }

    @Test
    /** Restore selected IDs, prevent duplicate checkbox additions, and retain unavailable selections. */
    func selectionPersistence() throws {
        let (store, defaults) = store()
        store.begin(server: "http://home.local")
        store.setSelected("light.desk", selected: true)
        store.setSelected("light.desk", selected: true)
        store.setSelected("sensor.pm25", selected: true)
        store.setSelected("switch.plug", selected: true)
        let restored = EntityStore(defaults: defaults)
        #expect(restored.selectedIDs == ["light.desk", "sensor.pm25", "switch.plug"])
        #expect(restored.selectedEntities.allSatisfy { $0.stateLabel == "Unavailable" })
        #expect(restored.groups(search: "", showHidden: false).flatMap(\.entities).count == 3)
        restored.begin(server: "http://home.local")
        #expect(restored.selectedIDs.count == 3)
        restored.setSelected("light.desk", selected: false)
        #expect(EntityStore(defaults: defaults).selectedIDs == ["sensor.pm25", "switch.plug"])
        restored.begin(server: "http://different.local")
        #expect(restored.selectedIDs.isEmpty)
    }

    @Test
    /** Persist local names without changing IDs or order, and retain them through live state updates. */
    func localNamePersistence() throws {
        let (store, defaults) = store()
        store.begin(server: "http://home.local")
        store.setSelected("light.desk", selected: true)
        store.setSelected("switch.plug", selected: true)
        try store.load(json(#"[{"entity_id":"light.desk","name":"Desk Lamp"}]"#), command: "config/entity_registry/list")
        store.setLocalName("  Reading Lamp \n", for: "light.desk")
        #expect(store.selectedIDs == ["light.desk", "switch.plug"])
        #expect(store.selectedEntities.first?.name == "Reading Lamp")
        #expect(store.groups(search: "reading", showHidden: false).flatMap(\.entities).map(\.id) == ["light.desk"])
        try store.applyLegacy(["data": ["entity_id": "light.desk", "new_state": ["state": "on",
            "attributes": ["friendly_name": "Updated HA Lamp"]]]])
        #expect(store.selectedEntities.first?.name == "Reading Lamp")
        #expect(store.selectedEntities.first?.state == "on")
        let restored = EntityStore(defaults: defaults)
        #expect(restored.selectedEntities.first?.id == "light.desk")
        #expect(restored.selectedEntities.first?.name == "Reading Lamp")
        store.setSelected("light.desk", selected: false)
        store.setSelected("light.desk", selected: true)
        #expect(store.selectedEntities.last?.name == "Reading Lamp")
    }

    @Test
    /** Restore the latest Home Assistant name when a local name is cleared, including whitespace input. */
    func resetLocalName() throws {
        let (store, defaults) = store()
        store.setSelected("light.desk", selected: true)
        try store.load(json(#"[{"entity_id":"light.desk","name":"Desk Lamp"}]"#), command: "config/entity_registry/list")
        store.setLocalName("Reading Lamp", for: "light.desk")
        try store.load(json(#"[{"entity_id":"light.desk","name":"New HA Name"}]"#), command: "config/entity_registry/list")
        store.setLocalName(" \n ", for: "light.desk")
        #expect(store.selectedEntities.first?.name == "New HA Name")
        store.setLocalName("Reading Lamp", for: "light.desk")
        store.setLocalName("", for: "light.desk")
        store.setLocalName("Unsupported", for: "cover.room")
        #expect(store.selectedEntities.first?.name == "New HA Name")
        let restored = EntityStore(defaults: defaults)
        try restored.load(json(#"[{"entity_id":"light.desk","name":"New HA Name"}]"#), command: "config/entity_registry/list")
        #expect(restored.selectedEntities.first?.name == "New HA Name")
    }

    @Test
    /** Keep local names separate for each Home Assistant server and retain them on reconnect. */
    func localNamesFollowServer() {
        let (store, defaults) = store()
        store.begin(server: "http://home.local")
        store.setSelected("light.desk", selected: true)
        store.setLocalName("Reading Lamp", for: "light.desk")
        store.disconnected()
        store.begin(server: "http://home.local")
        #expect(store.selectedEntities.first?.name == "Reading Lamp")
        let restored = EntityStore(defaults: defaults)
        restored.begin(server: "http://other.local")
        restored.setSelected("light.desk", selected: true)
        #expect(restored.selectedEntities.first?.name == "Desk")
        #expect(EntityStore(defaults: defaults).selectedEntities.first?.name == "Desk")
        restored.begin(server: "http://home.local")
        #expect(restored.selectedEntities.first?.name == "Reading Lamp")
    }

    @Test
    /** Restore each server's selections, order, and names after switches and app restarts. */
    func preferencesPerServer() {
        let (store, defaults) = store()
        store.begin(server: "http://home.local")
        store.setSelected("light.desk", selected: true)
        store.setSelected("switch.plug", selected: true)
        store.moveSelected(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        store.setLocalName("Home Lamp", for: "light.desk")
        store.begin(server: "http://cabin.local")
        #expect(store.selectedIDs.isEmpty)
        store.setSelected("light.desk", selected: true)
        #expect(store.selectedEntities.first?.name == "Desk")
        store.setLocalName("Cabin Lamp", for: "light.desk")
        store.disconnected()

        let restored = EntityStore(defaults: defaults)
        #expect(restored.selectedIDs == ["light.desk"])
        #expect(restored.selectedEntities.first?.name == "Cabin Lamp")
        restored.begin(server: "http://home.local")
        #expect(restored.selectedIDs == ["switch.plug", "light.desk"])
        #expect(restored.selectedEntities.last?.name == "Home Lamp")
        restored.setSelected("switch.plug", selected: false)
        restored.setLocalName("", for: "light.desk")
        restored.begin(server: "http://cabin.local")
        #expect(restored.selectedIDs == ["light.desk"])
        #expect(restored.selectedEntities.first?.name == "Cabin Lamp")
        restored.begin(server: "http://home.local")
        #expect(restored.selectedIDs == ["light.desk"])
        #expect(restored.selectedEntities.first?.name == "Desk")
    }

    @Test
    /** Migrate legacy preferences to their original server even when another server connects first. */
    func migrateLegacyPreferences() {
        let (_, defaults) = store()
        defaults.set("http://home.local", forKey: "selectedEntitiesServer")
        defaults.set(["switch.plug", "light.desk"], forKey: "selectedEntityIDs")
        defaults.set(["light.desk": "Home Lamp"], forKey: "localEntityNames")
        let migrated = EntityStore(defaults: defaults)
        #expect(migrated.selectedIDs == ["switch.plug", "light.desk"])
        migrated.begin(server: "http://cabin.local")
        #expect(migrated.selectedIDs.isEmpty)
        let restored = EntityStore(defaults: defaults)
        restored.begin(server: "http://home.local")
        #expect(restored.selectedIDs == ["switch.plug", "light.desk"])
        #expect(restored.selectedEntities.last?.name == "Home Lamp")
        #expect(defaults.object(forKey: "selectedEntityIDs") == nil)
        #expect(defaults.object(forKey: "localEntityNames") == nil)
    }

    @Test
    /** Move selections both ways and in groups, keeping display order and saved preferences in sync. */
    func reorderPersistence() {
        let (store, defaults) = store()
        let original = ["light.desk", "sensor.pm25", "switch.plug", "fan.bed"]
        for id in original { store.setSelected(id, selected: true) }

        store.moveSelected(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        #expect(store.selectedIDs == ["sensor.pm25", "switch.plug", "fan.bed", "light.desk"])
        store.moveSelected(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(store.selectedIDs == original)
        store.moveSelected(fromOffsets: IndexSet([0, 2]), toOffset: 4)
        let expected = ["sensor.pm25", "fan.bed", "light.desk", "switch.plug"]
        #expect(store.selectedIDs == expected)
        #expect(store.selectedEntities.map(\.id) == expected)

        let restored = EntityStore(defaults: defaults)
        #expect(restored.selectedIDs == expected)
        restored.disconnected()
        restored.begin(server: "http://home.local")
        #expect(restored.selectedEntities.map(\.id) == expected)
        restored.setSelected("sensor.temperature", selected: true)
        #expect(restored.selectedIDs == expected + ["sensor.temperature"])
    }

    @Test
    /** Leave selection unchanged for adjacent drops, empty moves, and invalid offsets. */
    func reorderNoOpAndInvalidOffsets() {
        let (store, defaults) = store()
        store.moveSelected(fromOffsets: IndexSet(integer: 0), toOffset: 0)
        #expect(store.selectedIDs.isEmpty)
        let original = ["light.desk", "switch.plug"]
        for id in original { store.setSelected(id, selected: true) }
        store.moveSelected(fromOffsets: IndexSet(integer: 0), toOffset: 1)
        store.moveSelected(fromOffsets: IndexSet(), toOffset: 0)
        store.moveSelected(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        store.moveSelected(fromOffsets: IndexSet(integer: 0), toOffset: -1)
        store.moveSelected(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(store.selectedIDs == original)
        #expect(EntityStore(defaults: defaults).selectedIDs == original)
    }

    @Test
    /** Merge compressed additions, changed state/attributes, attribute removals, and entity removals. */
    func compressedUpdates() throws {
        let (store, _) = store()
        try store.load(json(#"[{"entity_id":"sensor.stale","state":"1","attributes":{}}]"#), command: "get_states")
        let initial = try #require(json(#"{"a":{"sensor.air":{"s":"8","a":{"friendly_name":"Air","unit_of_measurement":"µg/m³","device_class":"pm25"}},"sensor.humidity":{"s":"45","a":{"unit_of_measurement":"%"}},"light.desk":{"s":"off","a":{}}}}"#) as? [String: Any])
        try store.applyCompressed(initial, initial: true)
        #expect(!store.entities.contains { $0.id == "sensor.stale" })
        #expect(store.entities.first { $0.id == "sensor.air" }?.stateLabel == "8 µg/m³")
        #expect(store.entities.first { $0.id == "sensor.humidity" }?.stateLabel == "45%")
        let changes = try #require(json(#"{"c":{"sensor.air":{"+":{"s":"10","a":{"friendly_name":"PM2.5"}},"-":{"a":["unit_of_measurement"]}},"light.desk":{"+":{"s":"on"}}},"r":["sensor.humidity"]}"#) as? [String: Any])
        try store.applyCompressed(changes, initial: false)
        #expect(store.entities.first { $0.id == "sensor.air" }?.name == "PM2.5")
        #expect(store.entities.first { $0.id == "sensor.air" }?.stateLabel == "10")
        #expect(store.entities.first { $0.id == "light.desk" }?.stateLabel == "On")
        #expect(!store.entities.contains { $0.id == "sensor.humidity" })
        store.disconnected()
        #expect(store.entities.allSatisfy { $0.state == "unavailable" })
    }

    @Test
    /** Correlate out-of-order results and subscribe once after the state snapshot arrives. */
    func commandRoutingAndSubscription() async throws {
        let (store, _) = store()
        let socket = ScriptedSocket([])
        let discovery = EntityDiscovery(socket: socket, store: store)
        store.begin(server: "http://home.local")
        defer { discovery.close() }
        try await discovery.start()
        #expect(socket.sentTypes == ["config/area_registry/list", "config/device_registry/list", "config/entity_registry/list", "get_states"])
        try await discovery.receive(result(3, value: []))
        try await discovery.receive(result(1, value: []))
        try await discovery.receive(result(4, value: []))
        #expect(socket.sentTypes.last == "subscribe_entities")
        try await discovery.receive(result(2, value: []))
        try await discovery.receive(result(5, value: NSNull()))
        #expect(!store.isLoading)
        #expect(store.isLive)
        try await discovery.receive(Data(#"{"id":99,"type":"event","event":{"a":{"sensor.wrong":{"s":"1","a":{}}}}}"#.utf8))
        #expect(store.entities.isEmpty)
        try await discovery.receive(Data(#"{"id":5,"type":"event","event":{"a":{"light.test":{"s":"on","a":{"friendly_name":"Test Lamp"}}}}}"#.utf8))
        #expect(store.entities.first?.name == "Test Lamp")
        #expect(socket.sentTypes.filter { $0 == "subscribe_entities" }.count == 1)
    }

    @Test(arguments: ["fan.bed", "switch.plug"])
    /** Fall back to legacy changes for the supplied entity ID without polling. */
    func legacyFallback(entityID: String) async throws {
        let (store, _) = store()
        let socket = ScriptedSocket([])
        let discovery = EntityDiscovery(socket: socket, store: store)
        defer { discovery.close() }
        try await discovery.start()
        for id in 1...4 { try await discovery.receive(result(id, value: [])) }
        try await discovery.receive(Data(#"{"id":5,"type":"result","success":false,"error":{"code":"unknown_command","message":"ignored"}}"#.utf8))
        #expect(socket.sentTypes.last == "subscribe_events")
        let request = try #require(JSONSerialization.jsonObject(with: socket.sent.last!) as? [String: Any])
        #expect(request["event_type"] as? String == "state_changed")
        try await discovery.receive(result(6, value: NSNull()))
        #expect(socket.sentTypes.last == "get_states")
        try await discovery.receive(result(7, value: []))
        try await discovery.receive(Data(#"{"id":6,"type":"event","event":{"data":{"entity_id":"\#(entityID)","new_state":{"state":"unknown","attributes":{"friendly_name":"Fan"}}}}}"#.utf8))
        #expect(store.entities.first?.stateLabel == "Unknown")
        try await discovery.receive(Data(#"{"id":6,"type":"event","event":{"data":{"entity_id":"\#(entityID)","new_state":null}}}"#.utf8))
        #expect(store.entities.isEmpty)
        #expect(store.isLive)
    }

    @Test
    /** Surface API failures safely while allowing successful requests and state updates to continue. */
    func apiErrorsAndTimeouts() async throws {
        let (store, _) = store()
        store.begin(server: "http://home.local")
        let socket = ScriptedSocket([])
        let discovery = EntityDiscovery(socket: socket, store: store, timeout: .milliseconds(20))
        defer { discovery.close() }
        try await discovery.start()
        try await discovery.receive(Data(#"{"id":3,"type":"result","success":false,"error":{"code":"unauthorized","message":"sensitive-server-text"}}"#.utf8))
        try await discovery.receive(result(4, value: NSNull()))
        #expect(store.errors.contains { $0.contains("response could not be read") })
        try await discovery.receive(Data(#"{"id":5,"type":"result","success":false,"error":{"code":"unauthorized","message":"sensitive-server-text"}}"#.utf8))
        #expect(!socket.sentTypes.contains("subscribe_events"))
        try await wait { !store.isLoading }
        #expect(!store.isLoading)
        #expect(!store.isLive)
        #expect(store.errors.contains { $0.contains("timed out") })
        #expect(!store.errors.joined().contains("sensitive-server-text"))
    }

    @Test
    /** Repeat discovery and subscriptions on a new connection while retaining selection. */
    func reconnectRestoresSubscription() async throws {
        let (store, _) = store()
        store.begin(server: "http://home.local")
        store.setSelected("light.desk", selected: true)
        for _ in 0..<2 {
            store.begin(server: "http://home.local")
            let socket = ScriptedSocket([])
            let discovery = EntityDiscovery(socket: socket, store: store)
            try await discovery.start()
            for id in 1...4 { try await discovery.receive(result(id, value: [])) }
            try await discovery.receive(result(5, value: NSNull()))
            #expect(store.isLive)
            #expect(socket.sentTypes.filter { $0 == "subscribe_entities" }.count == 1)
            discovery.close()
            store.disconnected()
        }
        #expect(store.selectedIDs == ["light.desk"])
    }
    /** Wait for a real client/store state transition with a short deterministic deadline. */
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Expected entity state was not reached")
    }

    @Test(arguments: ["light.desk", "switch.plug"])
    /** Exercise discovery, live state, service calls, and reconnect for the supplied entity ID. */
    func connectionIntegration(entityID: String) async throws {
        let (store, defaults) = store()
        store.setSelected(entityID, selected: true)
        let frames = [
            #"{"type":"auth_required"}"#,
            #"{"type":"auth_ok","ha_version":"2026.11"}"#,
            #"{"id":1,"type":"result","success":true,"result":[]}"#,
            #"{"id":2,"type":"result","success":true,"result":[]}"#,
            #"{"id":3,"type":"result","success":true,"result":[{"entity_id":"\#(entityID)","name":"Desk Lamp"}]}"#,
            #"{"id":4,"type":"result","success":true,"result":[]}"#,
            #"{"id":5,"type":"result","success":true,"result":null}"#,
            #"{"id":5,"type":"event","event":{"a":{"\#(entityID)":{"s":"on","a":{}}}}}"#
        ]
        let first = ScriptedSocket(frames)
        let second = ScriptedSocket(frames)
        var connections = 0
        let model = ConnectionViewModel(defaults: defaults, store: MemoryTokens(), observeSystem: false, refreshStore: MemoryTokens(),
            clientFactory: { HomeAssistantClient(factory: { _ in
                connections += 1
                return connections == 1 ? first : second
            }) })
        model.serverURL = "http://home.local"
        model.tokenInput = "synthetic-token"
        model.connect()
        try await wait { model.entities.selectedEntities.first?.stateLabel == "On" }
        #expect(model.state == .connected)
        #expect(model.entities.isLive)
        #expect(connections == 1)
        #expect(first.sentTypes == ["auth", "config/area_registry/list", "config/device_registry/list", "config/entity_registry/list", "get_states", "subscribe_entities"])
        first.push(#"{"id":5,"type":"event","event":{"c":{"\#(entityID)":{"+":{"s":"off"}}}}}"#)
        try await wait { model.entities.selectedEntities.first?.stateLabel == "Off" }
        first.close()
        try await wait { model.state == .reconnecting }
        #expect(model.entities.selectedEntities.first?.stateLabel == "Unavailable")
        model.recover()
        try await wait { model.entities.isLive && model.entities.selectedEntities.first?.stateLabel == "On" }
        #expect(connections == 2)
        #expect(second.sentTypes.filter { $0 == "subscribe_entities" }.count == 1)
        let control = Task { try await model.control(entityID, command: .power(false)) }
        try await wait { second.sentTypes.last == "call_service" }
        let request = try #require(JSONSerialization.jsonObject(with: second.sent.last!) as? [String: Any])
        #expect(request["domain"] as? String == String(entityID.prefix(while: { $0 != "." })))
        #expect(request["service"] as? String == "turn_off")
        #expect(request["target"] as? [String: String] == ["entity_id": entityID])
        #expect(model.entities.selectedEntities.first?.state == "on")
        second.push(#"{"id":6,"type":"result","success":true,"result":null}"#)
        try await control.value
        #expect(model.entities.selectedEntities.first?.state == "on")
        second.push(#"{"id":5,"type":"event","event":{"c":{"\#(entityID)":{"+":{"s":"off"}}}}}"#)
        try await wait { model.entities.selectedEntities.first?.state == "off" }
        #expect(connections == 2)
        second.push(#"{"id":5,"type":"event","event":{"c":{"\#(entityID)":{"+":{"s":"unavailable"}}}}}"#)
        try await wait { model.entities.selectedEntities.first?.isAvailable == false }
        await #expect(throws: ServiceCallError.unavailable) { try await model.control(entityID, command: .power(true)) }
        model.disconnect()
        #expect(model.entities.selectedEntities.first?.stateLabel == "Unavailable")
        #expect(!model.entities.isLive)
    }

}
