import Foundation
import Testing
@testable import HomeBarCore

@MainActor
struct DeviceControlTests {
    /** Create an entity from reported attributes through the production state decoder. */
    private func entity(_ id: String = "light.desk", attributes: [String: Any], state: String = "on") throws -> HAEntity {
        let store = EntityStore(defaults: UserDefaults(suiteName: "DeviceTests.\(UUID().uuidString)")!)
        try store.load([["entity_id": id, "state": state, "attributes": attributes]], command: "get_states")
        return try #require(store.entities.first)
    }

    /** Wait for a synthetic transport transition without accessing a real device. */
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Expected service transition was not reached")
    }

    @Test
    /** Check all Phase 3 service names, target formatting, bounds, and capability guards. */
    func commandFormats() throws {
        let light = try entity(attributes: ["supported_color_modes": ["color_temp"],
            "min_color_temp_kelvin": 2200, "max_color_temp_kelvin": 6500, "brightness": 255])
        #expect(light.attributes.brightnessPercent == 100)
        let power = try DeviceCommand.power(false).message(for: light)
        #expect(power["type"] as? String == "call_service")
        #expect(power["domain"] as? String == "light")
        #expect(power["service"] as? String == "turn_off")
        #expect(power["target"] as? [String: String] == ["entity_id": "light.desk"])
        #expect(try DeviceCommand.power(true).message(for: light)["service"] as? String == "turn_on")
        #expect(try DeviceCommand.brightness(70).message(for: light)["service_data"] as? [String: Int] == ["brightness_pct": 70])
        #expect(try DeviceCommand.brightness(-1).message(for: light)["service_data"] as? [String: Int] == ["brightness_pct": 0])
        #expect(try DeviceCommand.temperature(9000).message(for: light)["service_data"] as? [String: Int] == ["color_temp_kelvin": 6500])
        let fan = try entity("fan.air", attributes: ["supported_features": 57, "preset_modes": ["Auto", "Sleep"]])
        #expect(try DeviceCommand.power(true).message(for: fan)["service"] as? String == "turn_on")
        #expect(try DeviceCommand.power(false).message(for: fan)["service"] as? String == "turn_off")
        let speed = try DeviceCommand.percentage(40).message(for: fan)
        #expect(speed["domain"] as? String == "fan")
        #expect(speed["service"] as? String == "set_percentage")
        #expect(speed["service_data"] as? [String: Int] == ["percentage": 40])
        let preset = try DeviceCommand.preset("Auto").message(for: fan)
        #expect(preset["service"] as? String == "set_preset_mode")
        #expect(preset["service_data"] as? [String: String] == ["preset_mode": "Auto"])
        #expect(throws: ServiceCallError.unsupported) { try DeviceCommand.preset("Missing").message(for: fan) }
        let unavailable = try entity(attributes: [:], state: "unavailable")
        #expect(throws: ServiceCallError.unavailable) { try DeviceCommand.power(true).message(for: unavailable) }
    }

    @Test
    /** Check switch symbols, power requests, availability, and rejection of expanded controls. */
    func switchCommands() throws {
        let outlet = try entity("switch.plug", attributes: ["device_class": "outlet"])
        #expect(outlet.symbol == "powerplug")
        #expect(try entity("switch.generic", attributes: [:]).symbol == "switch.2")
        for on in [true, false] {
            let message = try DeviceCommand.power(on).message(for: outlet)
            #expect(message["type"] as? String == "call_service")
            #expect(message["domain"] as? String == "switch")
            #expect(message["service"] as? String == (on ? "turn_on" : "turn_off"))
            #expect(message["target"] as? [String: String] == ["entity_id": "switch.plug"])
            #expect((message["service_data"] as? [String: String])?.isEmpty == true)
        }
        for state in ["unavailable", "unknown"] {
            let unavailable = try entity("switch.plug", attributes: [:], state: state)
            #expect(!unavailable.isAvailable)
            #expect(throws: ServiceCallError.unavailable) { try DeviceCommand.power(true).message(for: unavailable) }
        }
        for command in [DeviceCommand.brightness(50), .temperature(3000), .percentage(50), .preset("Auto")] {
            #expect(throws: ServiceCallError.unsupported) { try command.message(for: outlet) }
        }
    }

    @Test
    /** Hide unsupported controls and require a valid reported Kelvin range. */
    func capabilities() throws {
        let basic = try entity(attributes: ["supported_color_modes": ["onoff"]])
        #expect(!basic.attributes.supportsBrightness)
        #expect(basic.attributes.temperatureRange == nil)
        #expect(throws: ServiceCallError.unsupported) { try DeviceCommand.brightness(50).message(for: basic) }
        let rgb = try entity(attributes: ["supported_color_modes": ["rgb"]])
        #expect(rgb.attributes.supportsBrightness)
        #expect(rgb.attributes.temperatureRange == nil)
        let invalid = try entity(attributes: ["supported_color_modes": ["color_temp"], "min_color_temp_kelvin": 6500, "max_color_temp_kelvin": 2000])
        #expect(invalid.attributes.temperatureRange == nil)
        let fan = try entity("fan.basic", attributes: ["supported_features": 48, "percentage": NSNull(), "preset_modes": ["Auto"]])
        #expect(!fan.attributes.supportsFanSpeed)
        #expect(fan.attributes.fanPresets.isEmpty)
        #expect(throws: ServiceCallError.unsupported) { try DeviceCommand.percentage(30).message(for: fan) }
        #expect(throws: ServiceCallError.unsupported) { try DeviceCommand.preset("Auto").message(for: fan) }
        let noPower = try entity("fan.readonly", attributes: ["supported_features": 0])
        #expect(throws: ServiceCallError.unsupported) { try DeviceCommand.power(true).message(for: noPower) }
    }

    @Test
    /** Merge live control values, nulls, and removed capabilities without retaining stale attributes. */
    func liveControlAttributes() throws {
        let store = EntityStore()
        try store.applyCompressed(["a": ["light.desk": ["s": "on", "a": [
            "supported_color_modes": ["color_temp"], "brightness": 255, "color_temp_kelvin": 3500,
            "min_color_temp_kelvin": 2200, "max_color_temp_kelvin": 6500]]]], initial: true)
        try store.applyCompressed(["c": ["light.desk": ["+": ["a": ["brightness": 128, "color_temp_kelvin": 4000]]]]], initial: false)
        #expect(store.entities.first?.attributes.brightness == 128)
        #expect(store.entities.first?.attributes.color_temp_kelvin == 4000)
        #expect(store.entities.first?.attributes.temperatureRange == 2200...6500)
        try store.applyCompressed(["c": ["light.desk": ["+": ["a": ["brightness": NSNull()]],
            "-": ["a": ["supported_color_modes", "max_color_temp_kelvin"]]]]], initial: false)
        #expect(store.entities.first?.attributes.brightness == nil)
        #expect(store.entities.first?.attributes.supportsBrightness == false)
        #expect(store.entities.first?.attributes.temperatureRange == nil)
        try store.applyLegacy(["data": ["entity_id": "fan.air", "new_state": ["state": "on", "attributes": [
            "supported_features": 57, "percentage": 40, "preset_modes": ["Auto"], "preset_mode": "Auto"]]]])
        #expect(store.entities.first { $0.id == "fan.air" }?.attributes.percentage == 40)
        #expect(store.entities.first { $0.id == "fan.air" }?.attributes.preset_mode == "Auto")
    }

    @Test
    /** Match concurrent results out of order on one socket while discovery and state updates continue. */
    func serviceRouting() async throws {
        let socket = ScriptedSocket([#"{"type":"auth_required"}"#, #"{"type":"auth_ok"}"#])
        var opened = 0
        let client = HomeAssistantClient(factory: { _ in opened += 1; return socket })
        let store = EntityStore()
        let run = Task { try await client.run(address: ServerAddress("http://home.local"), token: "test", entities: store) { _ in } }
        defer { client.disconnect(); run.cancel() }
        try await wait { socket.sent.count == 5 }
        let light = try entity(attributes: [:])
        let first = Task { try await client.callService(.power(true), entity: light) }
        try await wait { socket.sent.count == 6 }
        let second = Task { try await client.callService(.power(false), entity: light) }
        try await wait { socket.sent.count == 7 }
        let frames = try socket.sent.dropFirst().map { try #require(JSONSerialization.jsonObject(with: $0) as? [String: Any]) }
        #expect(frames.compactMap { $0["id"] as? Int } == [1, 2, 3, 4, 5, 6])
        socket.push(#"{"id":6,"type":"result","success":false,"error":{"message":"secret text"}}"#)
        await #expect(throws: ServiceCallError.rejected) { try await second.value }
        socket.push(#"{"id":4,"type":"result","success":true,"result":[]}"#)
        try await wait { socket.sent.count == 8 }
        let subscription = try #require(JSONSerialization.jsonObject(with: socket.sent[7]) as? [String: Any])
        #expect(subscription["id"] as? Int == 7)
        socket.push(#"{"id":5,"type":"result","success":true,"result":null}"#)
        try await first.value
        socket.push(#"{"id":7,"type":"event","event":{"a":{"light.desk":{"s":"off","a":{"brightness":128}}}}}"#)
        try await wait { store.entities.first?.attributes.brightness == 128 }
        #expect(store.entities.first?.state == "off")
        #expect(opened == 1)
        #expect(store.errors.isEmpty)
    }

    @Test
    /** Bound stalled requests and release cancelled or disconnected callers without changing cached state. */
    func serviceLifecycle() async throws {
        let socket = ScriptedSocket([#"{"type":"auth_required"}"#, #"{"type":"auth_ok"}"#])
        let client = HomeAssistantClient(serviceTimeout: .milliseconds(50), factory: { _ in socket })
        let light = try entity(attributes: [:])
        await #expect(throws: ServiceCallError.unavailable) { try await client.callService(.power(true), entity: light) }
        var ready = false
        let run = Task { try await client.run(address: ServerAddress("http://home.local"), token: "test") { _ in ready = true } }
        defer { client.disconnect(); run.cancel() }
        try await wait { ready }
        socket.failSends = true
        await #expect(throws: ServiceCallError.unavailable) { try await client.callService(.power(true), entity: light) }
        socket.failSends = false
        await #expect(throws: ServiceCallError.timeout) { try await client.callService(.power(true), entity: light) }
        let cancelled = Task { try await client.callService(.power(true), entity: light) }
        try await wait { socket.sent.count == 3 }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        let pending = Task { try await client.callService(.power(false), entity: light) }
        try await wait { socket.sent.count == 4 }
        client.disconnect()
        await #expect(throws: ServiceCallError.unavailable) { try await pending.value }
        #expect(light.state == "on")
    }
}
