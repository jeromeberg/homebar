import Foundation

public enum DeviceCommand: Equatable, Sendable {
    case power(Bool)
    case brightness(Int)
    case temperature(Int)
    case targetTemperature(Double)
    case percentage(Int)
    case preset(String)

    /** Build a supported service request for the latest entity state, or reject stale controls. */
    func message(for entity: HAEntity) throws -> [String: Any] {
        guard entity.isAvailable else { throw ServiceCallError.unavailable }
        var service: String
        var data: [String: Any] = [:]
        switch self {
        case .power(let on) where ["light", "fan", "switch"].contains(entity.domain):
            if entity.domain == "fan" {
                let flag = on ? 32 : 16
                guard (entity.attributes.supported_features ?? 0) & flag != 0 else { throw ServiceCallError.unsupported }
            }
            service = on ? "turn_on" : "turn_off"
        case .brightness(let value) where entity.domain == "light" && entity.attributes.supportsBrightness:
            service = "turn_on"
            data["brightness_pct"] = min(100, max(0, value))
        case .temperature(let value) where entity.domain == "light":
            guard let range = entity.attributes.temperatureRange else { throw ServiceCallError.unsupported }
            service = "turn_on"
            data["color_temp_kelvin"] = Int(min(range.upperBound, max(range.lowerBound, Double(value))))
        case .targetTemperature(let value) where entity.domain == "climate":
            guard value.isFinite, entity.state != "heat_cool",
                  entity.attributes.temperature != nil,
                  let range = entity.attributes.targetTemperatureRange else { throw ServiceCallError.unsupported }
            service = "set_temperature"
            data["temperature"] = min(range.upperBound, max(range.lowerBound, value))
        case .percentage(let value) where entity.domain == "fan" && entity.attributes.supportsFanSpeed:
            service = "set_percentage"
            data["percentage"] = min(100, max(0, value))
        case .preset(let value) where entity.domain == "fan" && entity.attributes.fanPresets.contains(value):
            service = "set_preset_mode"
            data["preset_mode"] = value
        default: throw ServiceCallError.unsupported
        }
        return ["type": "call_service", "domain": entity.domain, "service": service,
                "target": ["entity_id": entity.id], "service_data": data]
    }
}

public enum ServiceCallError: Error, Equatable, Sendable {
    case unavailable
    case unsupported
    case rejected
    case timeout

    public var message: String {
        switch self {
        case .unavailable: "Device controls are unavailable. Check the connection and try again."
        case .unsupported: "This control is no longer supported by the device."
        case .rejected: "Home Assistant could not apply the change. Check the device and account permissions."
        case .timeout: "The command timed out. Check the device state before trying again."
        }
    }
}
