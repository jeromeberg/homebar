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
    var attributes: Attributes

    struct Attributes: Decodable {
        var friendly_name: String?
        var unit_of_measurement: String?
        var device_class: String?
    }

    /** Create a state from a normal state object or compressed subscription addition. */
    init(id: String, payload: [String: Any], compressed: Bool) throws {
        guard let value = payload[compressed ? "s" : "state"] as? String,
              let attributes = payload[compressed ? "a" : "attributes"] as? [String: Any] else {
            throw ConnectionError.unexpectedResponse
        }
        entity_id = id
        state = value
        self.attributes = try JSONDecoder().decode(Attributes.self, from: JSONSerialization.data(withJSONObject: attributes))
    }

    /** Merge changed state fields and attribute additions/removals from a compressed diff. */
    mutating func apply(_ diff: [String: Any]) {
        let additions = diff["+"] as? [String: Any] ?? [:]
        if let value = additions["s"] as? String { state = value }
        if let attributes = additions["a"] as? [String: Any] {
            if attributes.keys.contains("friendly_name") { self.attributes.friendly_name = attributes["friendly_name"] as? String }
            if attributes.keys.contains("unit_of_measurement") { self.attributes.unit_of_measurement = attributes["unit_of_measurement"] as? String }
            if attributes.keys.contains("device_class") { self.attributes.device_class = attributes["device_class"] as? String }
        }
        let removals = (diff["-"] as? [String: Any])?["a"] as? [String] ?? []
        for key in removals {
            switch key {
            case "friendly_name": attributes.friendly_name = nil
            case "unit_of_measurement": attributes.unit_of_measurement = nil
            case "device_class": attributes.device_class = nil
            default: break
            }
        }
    }
}

public struct HAEntity: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let areaID: String?
    public let room: String
    public let state: String
    public let unit: String?
    public let deviceClass: String?
    public let isHidden: Bool

    public var domain: String { String(id.prefix(while: { $0 != "." })) }

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
