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
    /** Detect active cooling from device activity rather than its selected mode. */
    func coolingActivity() throws {
        for state in ["cool", "heat_cool", "auto"] {
            let cooling = try entity("climate.room", attributes: ["hvac_action": "cooling"], state: state)
            #expect(cooling.isCooling)
            #expect(!cooling.isHeating)
        }
        for state in ["off", "unknown", "unavailable"] {
            #expect(try !entity("climate.room", attributes: ["hvac_action": "cooling"], state: state).isCooling)
        }
        for action in ["idle", "heating", "off"] {
            #expect(try !entity("climate.room", attributes: ["hvac_action": action], state: "cool").isCooling)
        }
        #expect(try !entity("climate.room", attributes: [:], state: "cool").isCooling)
        #expect(try !entity("fan.air", attributes: ["hvac_action": "cooling"]).isCooling)
    }

    @Test
    /** Validate advertised climate modes and presets, including custom preset values and off devices. */
    func climateModesAndPresets() throws {
        let modes = ["off", "heat", "cool", "heat_cool", "auto", "dry", "fan_only"]
        let attributes: [String: Any] = ["hvac_modes": modes, "supported_features": 16,
            "preset_modes": ["none", "eco", "Custom Preset"], "preset_mode": "eco"]
        let climate = try entity("climate.room", attributes: attributes, state: "off")
        #expect(climate.attributes.hvac_modes == modes)
        #expect(climate.attributes.climatePresets == ["none", "eco", "Custom Preset"])
        for mode in modes {
            let message = try DeviceCommand.hvacMode(mode).message(for: climate)
            #expect(message["type"] as? String == "call_service")
            #expect(message["domain"] as? String == "climate")
            #expect(message["target"] as? [String: String] == ["entity_id": "climate.room"])
            #expect(message["service"] as? String == "set_hvac_mode")
            #expect(message["service_data"] as? [String: String] == ["hvac_mode": mode])
        }
        for preset in climate.attributes.climatePresets {
            let message = try DeviceCommand.preset(preset).message(for: climate)
            #expect(message["domain"] as? String == "climate")
            #expect(message["service"] as? String == "set_preset_mode")
            #expect(message["service_data"] as? [String: String] == ["preset_mode": preset])
        }
        #expect(throws: ServiceCallError.unsupported) { try DeviceCommand.hvacMode("missing").message(for: climate) }
        #expect(throws: ServiceCallError.unsupported) { try DeviceCommand.preset("missing").message(for: climate) }
        let basic = try entity("climate.room", attributes: ["supported_features": 8, "preset_modes": ["eco"]], state: "heat")
        #expect(basic.attributes.climatePresets.isEmpty)
        #expect(throws: ServiceCallError.unsupported) { try DeviceCommand.preset("eco").message(for: basic) }
        #expect(throws: ServiceCallError.unsupported) { try DeviceCommand.hvacMode("heat").message(for: basic) }
        let fan = try entity("fan.air", attributes: attributes)
        #expect(throws: ServiceCallError.unsupported) { try DeviceCommand.hvacMode("cool").message(for: fan) }
        for state in ["unknown", "unavailable"] {
            let unavailable = try entity("climate.room", attributes: attributes, state: state)
            #expect(throws: ServiceCallError.unavailable) { try DeviceCommand.hvacMode("cool").message(for: unavailable) }
            #expect(throws: ServiceCallError.unavailable) { try DeviceCommand.preset("eco").message(for: unavailable) }
        }
        let cooling = try entity("climate.room", attributes: ["supported_features": 1,
            "temperature": 24, "min_temp": 16, "max_temp": 30], state: "cool")
        #expect(try DeviceCommand.targetTemperature(23).message(for: cooling)["service_data"] as? [String: Double] == ["temperature": 23])
    }

    @Test
    /** Use half-degree steps by default and preserve valid Home Assistant steps. */
    func thermostatTemperatureStep() {
        var attributes = EntityAttributes()
        #expect(attributes.targetTemperatureStep == 0.5)
        for invalid in [0.0, -1.0, Double.nan, Double.infinity] {
            attributes.target_temp_step = invalid
            #expect(attributes.targetTemperatureStep == 0.5)
        }
        for step in [0.1, 0.5, 1.0] {
            attributes.target_temp_step = step
            #expect(attributes.targetTemperatureStep == step)
        }
    }

    @Test
    /** Check thermostat service payloads, fractional steps, bounds, and unsupported modes. */
    func thermostatCommands() throws {
        let attributes: [String: Any] = ["supported_features": 1, "temperature": 20.5,
            "current_temperature": 19.2, "min_temp": 7, "max_temp": 30, "target_temp_step": 0.5,
            "temperature_unit": "°C", "hvac_action": "heating"]
        let thermostat = try entity("climate.room", attributes: attributes, state: "heat")
        #expect(thermostat.isAvailable)
        #expect(thermostat.isHeating)
        #expect(thermostat.symbol == "thermometer.medium")
        #expect(thermostat.attributes.current_temperature == 19.2)
        #expect(thermostat.attributes.temperature_unit == "°C")
        #expect(thermostat.attributes.adjustedTargetTemperature(from: 20.5, increasing: true) == 21)
        #expect(thermostat.attributes.adjustedTargetTemperature(from: 20.5, increasing: false) == 20)
        #expect(thermostat.attributes.adjustedTargetTemperature(from: 30, increasing: true) == 30)
        #expect(thermostat.attributes.adjustedTargetTemperature(from: 7, increasing: false) == 7)
        let message = try DeviceCommand.targetTemperature(21.5).message(for: thermostat)
        #expect(message["type"] as? String == "call_service")
        #expect(message["domain"] as? String == "climate")
        #expect(message["service"] as? String == "set_temperature")
        #expect(message["target"] as? [String: String] == ["entity_id": "climate.room"])
        #expect(message["service_data"] as? [String: Double] == ["temperature": 21.5])
        #expect(try DeviceCommand.targetTemperature(100).message(for: thermostat)["service_data"] as? [String: Double] == ["temperature": 30])
        #expect(try DeviceCommand.targetTemperature(-100).message(for: thermostat)["service_data"] as? [String: Double] == ["temperature": 7])
        #expect(throws: ServiceCallError.unsupported) { try DeviceCommand.targetTemperature(.nan).message(for: thermostat) }
        for state in ["off", "idle", "cool", "auto", "heat_cool"] {
            let other = try entity("climate.room", attributes: attributes, state: state)
            #expect(other.isAvailable)
            if state == "off" { #expect(!other.isHeating) }
            if state == "heat_cool" {
                #expect(throws: ServiceCallError.unsupported) { try DeviceCommand.targetTemperature(21).message(for: other) }
            }
        }
        for state in ["unknown", "unavailable"] {
            let unavailable = try entity("climate.room", attributes: attributes, state: state)
            #expect(!unavailable.isHeating)
            #expect(throws: ServiceCallError.unavailable) { try DeviceCommand.targetTemperature(21).message(for: unavailable) }
        }
        for invalid: [String: Any] in [[:], ["supported_features": 2],
            ["supported_features": 1, "temperature": 20, "min_temp": 30, "max_temp": 7]] {
            let unsupported = try entity("climate.room", attributes: invalid, state: "heat")
            #expect(throws: ServiceCallError.unsupported) { try DeviceCommand.targetTemperature(21).message(for: unsupported) }
        }
        #expect(throws: ServiceCallError.unsupported) { try DeviceCommand.power(true).message(for: thermostat) }
        let light = try entity(attributes: [:])
        #expect(throws: ServiceCallError.unsupported) { try DeviceCommand.targetTemperature(21).message(for: light) }
    }

    @Test
    /** Track thermostat selection, live activity and mode changes, removed attributes, and disconnection. */
    func liveThermostatAttributes() throws {
        let defaults = UserDefaults(suiteName: "ThermostatTests.\(UUID().uuidString)")!
        let store = EntityStore(defaults: defaults)
        store.setSelected("climate.room", selected: true)
        #expect(EntityStore(defaults: defaults).selectedIDs == ["climate.room"])
        try store.applyCompressed(["a": ["climate.room": ["s": "heat", "a": [
            "temperature": 20.5, "current_temperature": 19, "hvac_action": "idle",
            "supported_features": 1, "min_temp": 7, "max_temp": 30]]]], initial: true)
        #expect(store.selectedEntities.first?.isHeating == false)
        try store.applyCompressed(["c": ["climate.room": ["+": ["a": [
            "temperature": 21, "hvac_action": "heating"]]]]], initial: false)
        #expect(store.selectedEntities.first?.isHeating == true)
        #expect(store.selectedEntities.first?.attributes.temperature == 21)
        try store.applyCompressed(["c": ["climate.room": ["+": ["s": "cool", "a": [
            "hvac_action": "cooling", "hvac_modes": ["off", "cool"], "supported_features": 17,
            "preset_modes": ["none", "eco"], "preset_mode": "eco"]]]]], initial: false)
        #expect(store.selectedEntities.first?.isCooling == true)
        #expect(store.selectedEntities.first?.isHeating == false)
        #expect(store.selectedEntities.first?.state == "cool")
        #expect(store.selectedEntities.first?.attributes.hvac_modes == ["off", "cool"])
        #expect(store.selectedEntities.first?.attributes.climatePresets == ["none", "eco"])
        #expect(store.selectedEntities.first?.attributes.preset_mode == "eco")
        try store.applyCompressed(["c": ["climate.room": ["+": ["a": ["temperature": NSNull()]],
            "-": ["a": ["hvac_action", "supported_features", "hvac_modes", "preset_modes", "preset_mode"]]]]], initial: false)
        #expect(store.selectedEntities.first?.isHeating == false)
        #expect(store.selectedEntities.first?.isCooling == false)
        #expect(store.selectedEntities.first?.attributes.hvac_modes == nil)
        #expect(store.selectedEntities.first?.attributes.climatePresets.isEmpty == true)
        #expect(store.selectedEntities.first?.attributes.preset_mode == nil)
        #expect(store.selectedEntities.first?.attributes.temperature == nil)
        #expect(store.selectedEntities.first?.attributes.targetTemperatureRange == nil)
        try store.applyLegacy(["data": ["entity_id": "climate.room", "new_state": ["state": "heat", "attributes": [
            "temperature": 70, "temperature_unit": "°F", "hvac_action": "heating"]]]])
        #expect(store.selectedEntities.first?.attributes.temperature_unit == "°F")
        #expect(store.selectedEntities.first?.isHeating == true)
        store.disconnected()
        #expect(store.selectedEntities.first?.isAvailable == false)
        #expect(store.selectedEntities.first?.isHeating == false)
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
    /** Send thermostat commands over the existing socket and receive authoritative live updates. */
    func thermostatServiceRouting() async throws {
        let socket = ScriptedSocket([#"{"type":"auth_required"}"#, #"{"type":"auth_ok"}"#])
        let client = HomeAssistantClient(factory: { _ in socket })
        let store = EntityStore()
        let run = Task { try await client.run(address: ServerAddress("http://home.local"), token: "test", entities: store) { _ in } }
        defer { client.disconnect(); run.cancel() }
        try await wait { socket.sent.count == 5 }
        for id in 1...3 {
            socket.push("{\"id\":\(id),\"type\":\"result\",\"success\":true,\"result\":[]}")
        }
        socket.push(#"{"id":4,"type":"result","success":true,"result":[]}"#)
        try await wait { socket.sent.count == 6 }
        socket.push(#"{"id":5,"type":"result","success":true,"result":null}"#)
        socket.push(#"{"id":5,"type":"event","event":{"a":{"climate.room":{"s":"heat","a":{"temperature":20,"current_temperature":19,"min_temp":7,"max_temp":30,"supported_features":1,"hvac_action":"idle"}}}}}"#)
        try await wait { store.isLive && store.entities.first?.attributes.temperature == 20 }
        let thermostat = try #require(store.entities.first)
        let command = Task { try await client.callService(.targetTemperature(20.5), entity: thermostat) }
        try await wait { socket.sent.count == 7 }
        let request = try #require(JSONSerialization.jsonObject(with: socket.sent[6]) as? [String: Any])
        #expect(request["domain"] as? String == "climate")
        #expect(request["service"] as? String == "set_temperature")
        #expect(request["service_data"] as? [String: Double] == ["temperature": 20.5])
        #expect(store.entities.first?.attributes.temperature == 20)
        socket.push(#"{"id":6,"type":"result","success":true,"result":null}"#)
        try await command.value
        #expect(store.entities.first?.attributes.temperature == 20)
        socket.push(#"{"id":5,"type":"event","event":{"c":{"climate.room":{"+":{"a":{"temperature":20.5,"hvac_action":"heating"}}}}}}"#)
        try await wait { store.entities.first?.isHeating == true }
        #expect(store.entities.first?.attributes.temperature == 20.5)
        #expect(socket.sentTypes.filter { $0 == "auth" }.count == 1)
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
