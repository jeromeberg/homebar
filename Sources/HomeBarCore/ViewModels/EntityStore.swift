import Foundation
import Observation

@MainActor @Observable
public final class EntityStore {
    public private(set) var selectedIDs: [String]
    public private(set) var isLoading = false
    public private(set) var isLive = false
    public private(set) var errors: [String] = []
    private var areas: [String: HAArea] = [:]
    private var devices: [String: HADevice] = [:]
    private var registry: [String: HARegistryEntity] = [:]
    private var states: [String: HAState] = [:]
    private var localNames: [String: String]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var server: String?

    /** Restore saved selections and local names using the supplied preferences store. */
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedIDs = defaults.stringArray(forKey: "selectedEntityIDs") ?? []
        localNames = defaults.dictionary(forKey: "localEntityNames") as? [String: String] ?? [:]
        server = defaults.string(forKey: "selectedEntitiesServer")
    }

    public var entities: [HAEntity] {
        Set(registry.keys).union(states.keys).union(selectedIDs).filter { Self.supports($0) }.map { id in
            let entry = registry[id]
            let state = states[id]
            let device = entry?.device_id.flatMap { devices[$0] }
            let areaID = entry?.area_id ?? device?.area_id
            let area = areaID.flatMap { areas[$0] }
            return HAEntity(id: id,
                name: localNames[id] ?? entry?.name ?? state?.attributes.friendly_name ?? entry?.original_name
                    ?? id.split(separator: ".").last.map { $0.replacingOccurrences(of: "_", with: " ").capitalized } ?? id,
                areaID: area?.area_id, room: area?.name ?? "Other",
                state: state?.state ?? "unavailable", unit: state?.attributes.unit_of_measurement,
                deviceClass: state?.attributes.device_class,
                isHidden: entry?.disabled_by != nil || entry?.hidden_by != nil
                    || entry?.entity_category == "diagnostic" || device?.disabled_by != nil,
                attributes: state?.attributes ?? EntityAttributes())
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public var selectedEntities: [HAEntity] {
        let available = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })
        return selectedIDs.compactMap { available[$0] }
    }

    /** Group supported entities by room, optionally including normally hidden entities and filtering names. */
    public func groups(search: String, showHidden: Bool) -> [EntityGroup] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = entities.filter {
            (showHidden || !$0.isHidden) && (query.isEmpty || $0.name.localizedStandardContains(query))
        }
        return Dictionary(grouping: filtered, by: { $0.areaID ?? "" }).map { id, items in
            EntityGroup(id: id, name: items.first?.room ?? "Other", entities: items)
        }.sorted {
            if $0.id.isEmpty != $1.id.isEmpty { return !$0.id.isEmpty }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /** Update one checkbox selection and persist the IDs in selection order. */
    public func setSelected(_ id: String, selected: Bool) {
        guard Self.supports(id) else { return }
        if selected && !selectedIDs.contains(id) { selectedIDs.append(id) }
        if !selected { selectedIDs.removeAll { $0 == id } }
        defaults.set(selectedIDs, forKey: "selectedEntityIDs")
    }

    /** Save a local display name for an entity ID. An empty name restores the Home Assistant name. */
    public func setLocalName(_ name: String, for id: String) {
        guard Self.supports(id) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        localNames[id] = trimmed.isEmpty ? nil : trimmed
        defaults.set(localNames, forKey: "localEntityNames")
    }

    /** Move the selected IDs at the supplied offsets before the original destination offset and save the order. */
    public func moveSelected(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !source.isEmpty, source.allSatisfy({ selectedIDs.indices.contains($0) }),
              (0...selectedIDs.count).contains(destination) else { return }
        let moved = source.map { selectedIDs[$0] }
        let insertion = destination - source.filter { $0 < destination }.count
        var reordered = selectedIDs.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        reordered.insert(contentsOf: moved, at: insertion)
        selectedIDs = reordered
        defaults.set(selectedIDs, forKey: "selectedEntityIDs")
    }

    /** Start discovery and clear selections and local names when the authenticated server changes. */
    func begin(server: String) {
        if let previous = self.server, previous != server {
            selectedIDs = []
            defaults.set(selectedIDs, forKey: "selectedEntityIDs")
            localNames = [:]
            defaults.set(localNames, forKey: "localEntityNames")
        }
        self.server = server
        defaults.set(server, forKey: "selectedEntitiesServer")
        areas = [:]
        devices = [:]
        registry = [:]
        states = [:]
        errors = []
        isLoading = true
        isLive = false
    }

    /** Mark cached values unavailable when the connection ends, retaining selection and registry names. */
    func disconnected() {
        isLoading = false
        isLive = false
        for id in states.keys { states[id]?.state = "unavailable" }
    }

    /** Record an actionable, fixed API error without including server-provided text. */
    func report(_ message: String) {
        if !errors.contains(message) { errors.append(message) }
    }

    /** Finish initial requests and record whether the live subscription is active. */
    func finish(live: Bool) {
        isLoading = false
        isLive = live
    }

    /** Decode one successful registry or state result. */
    func load(_ result: Any, command: String) throws {
        guard let records = result as? [Any] else { throw ConnectionError.unexpectedResponse }
        let data = try JSONSerialization.data(withJSONObject: records)
        let decoder = JSONDecoder()
        switch command {
        case "config/area_registry/list":
            areas = Dictionary(try decoder.decode([HAArea].self, from: data).map { ($0.area_id, $0) }, uniquingKeysWith: { _, new in new })
        case "config/device_registry/list":
            devices = Dictionary(try decoder.decode([HADevice].self, from: data).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        case "config/entity_registry/list":
            registry = Dictionary(try decoder.decode([HARegistryEntity].self, from: data).map { ($0.entity_id, $0) }, uniquingKeysWith: { _, new in new })
        case "get_states":
            let values = try decoder.decode([HAState].self, from: data).filter { Self.supports($0.entity_id) }
            states = Dictionary(values.map { ($0.entity_id, $0) }, uniquingKeysWith: { _, new in new })
        default: break
        }
    }

    /** Apply a compressed subscription snapshot or diff, including removed entities and attributes. */
    func applyCompressed(_ event: [String: Any], initial: Bool) throws {
        if initial { states = [:] }
        if let additions = event["a"] as? [String: [String: Any]] {
            for (id, payload) in additions where Self.supports(id) {
                states[id] = try HAState(id: id, payload: payload, compressed: true)
            }
        }
        if let changes = event["c"] as? [String: [String: Any]] {
            for (id, diff) in changes { states[id]?.apply(diff) }
        }
        for id in event["r"] as? [String] ?? [] { states.removeValue(forKey: id) }
    }

    /** Apply a legacy state_changed event used when compressed subscriptions are unsupported. */
    func applyLegacy(_ event: [String: Any]) throws {
        guard let data = event["data"] as? [String: Any], let id = data["entity_id"] as? String,
              Self.supports(id) else { return }
        if let payload = data["new_state"] as? [String: Any] {
            states[id] = try HAState(id: id, payload: payload, compressed: false)
        } else { states.removeValue(forKey: id) }
    }

    /** Check whether an entity belongs to a supported domain. */
    private static func supports(_ id: String) -> Bool {
        ["light", "fan", "sensor", "switch", "climate"].contains(String(id.prefix(while: { $0 != "." })))
    }
}
