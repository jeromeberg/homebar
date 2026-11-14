import Foundation

struct HAArea: Decodable {
    let area_id: String
    let name: String
}

struct HADevice: Decodable {
    let id: String
    let area_id: String?
    let disabled_by: String?
}

struct HARegistryEntity: Decodable {
    let entity_id: String
    let name: String?
    let original_name: String?
    let area_id: String?
    let device_id: String?
    let disabled_by: String?
    let hidden_by: String?
    let entity_category: String?
}

struct HAState: Decodable {
    let entity_id: String
    var state: String
    var attributes: EntityAttributes
    var lastUpdated: Date?

    private enum CodingKeys: String, CodingKey {
        case entity_id, state, attributes, last_updated
    }

    /** Decode a state snapshot and its optional Home Assistant update timestamp. */
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        entity_id = try values.decode(String.self, forKey: .entity_id)
        state = try values.decode(String.self, forKey: .state)
        attributes = try values.decode(EntityAttributes.self, forKey: .attributes)
        lastUpdated = Self.updateDate(try values.decodeIfPresent(String.self, forKey: .last_updated))
    }

    /** Parse an optional ISO 8601 timestamp, with or without fractional seconds. */
    private static func updateDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    /** Create a state from a normal state object or compressed subscription addition. */
    init(id: String, payload: [String: Any], compressed: Bool) throws {
        guard let value = payload[compressed ? "s" : "state"] as? String,
              let attributes = payload[compressed ? "a" : "attributes"] as? [String: Any] else {
            throw ConnectionError.unexpectedResponse
        }
        entity_id = id
        state = value
        self.attributes = try JSONDecoder().decode(EntityAttributes.self, from: JSONSerialization.data(withJSONObject: attributes))
        if compressed {
            lastUpdated = ((payload["lu"] ?? payload["lc"]) as? Double).map { Date(timeIntervalSince1970: $0) }
        } else {
            lastUpdated = Self.updateDate(payload["last_updated"] as? String)
        }
    }

    /** Merge changed state fields and attribute additions/removals from a compressed diff. */
    mutating func apply(_ diff: [String: Any]) {
        let additions = diff["+"] as? [String: Any] ?? [:]
        if let value = additions["s"] as? String { state = value }
        if let timestamp = (additions["lu"] ?? additions["lc"]) as? Double {
            lastUpdated = Date(timeIntervalSince1970: timestamp)
        }
        guard let data = try? JSONEncoder().encode(attributes),
              var merged = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        for (key, value) in additions["a"] as? [String: Any] ?? [:] { merged[key] = value }
        for key in (diff["-"] as? [String: Any])?["a"] as? [String] ?? [] { merged.removeValue(forKey: key) }
        if let data = try? JSONSerialization.data(withJSONObject: merged),
           let updated = try? JSONDecoder().decode(EntityAttributes.self, from: data) { attributes = updated }
    }
}

public struct HAEntity: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let areaID: String?
    public let room: String
    public let state: String
    public let lastUpdated: Date?
    public let unit: String?
    public let deviceClass: String?
    public let isHidden: Bool

    public let attributes: EntityAttributes

    public var isAvailable: Bool {
        domain == "climate" ? !["unknown", "unavailable"].contains(state) : state == "on" || state == "off"
    }
    public var domain: String { String(id.prefix(while: { $0 != "." })) }
    public var isHeating: Bool { domain == "climate" && isAvailable && state != "off" && attributes.hvac_action == "heating" }
    public var isCooling: Bool { domain == "climate" && isAvailable && state != "off" && attributes.hvac_action == "cooling" }

    public var stateLabel: String {
        switch state {
        case "on": "On"
        case "off": "Off"
        case "unknown": "Unknown"
        case "unavailable": "Unavailable"
        default: unit.map { state + (["°C", "°F", "%"].contains($0) ? "" : " ") + $0 } ?? state
        }
    }

    public var symbol: String {
        switch domain {
        case "light": "lightbulb"
        case "fan": "fan"
        case "climate": "thermometer.medium"
        case "switch": deviceClass == "outlet" ? "powerplug" : "switch.2"
        default:
            switch deviceClass {
            case "temperature": "thermometer.medium"
            case "humidity": "humidity"
            case "pm25", "pm10": "aqi.medium"
            default: "gauge.with.dots.needle.50percent"
            }
        }
    }
}

public struct EntityGroup: Identifiable {
    public let id: String
    public let name: String
    public let entities: [HAEntity]
}

public struct EntityAttributes: Codable, Equatable, Sendable {
    public var friendly_name: String?
    public var unit_of_measurement: String?
    public var device_class: String?
    public var supported_color_modes: [String]?
    public var brightness: Double?
    public var color_temp_kelvin: Double?
    public var min_color_temp_kelvin: Double?
    public var max_color_temp_kelvin: Double?
    public var supported_features: Int?
    public var percentage: Double?
    public var preset_modes: [String]?
    public var preset_mode: String?
    public var temperature: Double?
    public var current_temperature: Double?
    public var temperature_unit: String?
    public var target_temp_step: Double?
    public var min_temp: Double?
    public var max_temp: Double?
    public var hvac_action: String?
    public var hvac_modes: [String]?

    public var climatePresets: [String] { (supported_features ?? 0) & 16 != 0 ? preset_modes ?? [] : [] }

    public var targetTemperatureRange: ClosedRange<Double>? {
        guard (supported_features ?? 0) & 1 != 0,
              let minimum = min_temp, let maximum = max_temp,
              minimum.isFinite, maximum.isFinite, maximum > minimum else { return nil }
        return minimum...maximum
    }

    public var targetTemperatureStep: Double {
        guard let step = target_temp_step, step.isFinite, step > 0 else { return 0.5 }
        return step
    }

    /** Return a bounded target after moving the supplied temperature by one reported step. */
    public func adjustedTargetTemperature(from value: Double, increasing: Bool) -> Double? {
        guard value.isFinite, let range = targetTemperatureRange else { return nil }
        let adjusted = value + (increasing ? targetTemperatureStep : -targetTemperatureStep)
        return min(range.upperBound, max(range.lowerBound, (adjusted * 1_000_000).rounded() / 1_000_000))
    }

    public var supportsBrightness: Bool {
        (supported_color_modes ?? []).contains { ["brightness", "color_temp", "hs", "xy", "rgb", "rgbw", "rgbww"].contains($0) }
    }

    public var temperatureRange: ClosedRange<Double>? {
        guard supported_color_modes?.contains("color_temp") == true,
              let minimum = min_color_temp_kelvin, let maximum = max_color_temp_kelvin,
              minimum.isFinite, maximum.isFinite, minimum > 0, maximum > minimum else { return nil }
        return minimum...maximum
    }

    public var supportsFanSpeed: Bool { (supported_features ?? 0) & 1 != 0 }
    public var fanPresets: [String] { (supported_features ?? 0) & 8 != 0 ? preset_modes ?? [] : [] }
    public var brightnessPercent: Double? { brightness.map { min(100, max(0, $0 / 255 * 100)) } }
}
