import HomeBarCore
import SwiftUI

struct ClimateControlView: View {
    let entity: HAEntity
    let connection: ConnectionViewModel
    @State private var pending = false
    @State private var requestedTarget: Double?
    @State private var error: String?

    private var target: Double? { requestedTarget ?? entity.attributes.temperature }
    private var controlsEnabled: Bool { entity.isAvailable && connection.entities.isLive && !pending }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: entity.symbol)
                    .foregroundStyle(.secondary).frame(width: 20)
                    .accessibilityHidden(true)
                Text(entity.name).lineLimit(2)
                Spacer(minLength: 0)
                if entity.isHeating {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Heating")
                        .help("Heating")
                } else if entity.isCooling {
                    Image(systemName: "snowflake")
                        .foregroundStyle(.blue)
                        .accessibilityLabel("Cooling")
                        .help("Cooling")
                }
                if entity.isAvailable {
                    Text(temperatureLabel(entity.attributes.current_temperature))
                        .foregroundStyle(.secondary).monospacedDigit()
                        .accessibilityLabel("Current temperature")
                } else {
                    Text(entity.stateLabel).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Text("Target")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 0) {
                    adjustmentButton(increasing: false)
                    Text(temperatureLabel(target))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .frame(minWidth: 58)
                        .accessibilityLabel("Target temperature")
                    adjustmentButton(increasing: true)
                }
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.leading, 30)
            if let modes = entity.attributes.hvac_modes, !modes.isEmpty {
                modePicker("Mode", current: entity.state, options: modes) { .hvacMode($0) }
            }
            if !entity.attributes.climatePresets.isEmpty {
                modePicker("Preset", current: entity.attributes.preset_mode, options: entity.attributes.climatePresets) { .preset($0) }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .padding(.vertical, 4)
        .onDisappear { requestedTarget = nil }
        .onChange(of: entity.attributes.temperature) { requestedTarget = nil }
        .onChange(of: entity.state) { requestedTarget = nil }
        .onChange(of: entity.attributes.preset_mode) { requestedTarget = nil }
        .onChange(of: controlsEnabled) {
            if !entity.isAvailable || !connection.entities.isLive { requestedTarget = nil }
        }
    }

    /** Create a compact picker for the reported options and send the selected command. */
    private func modePicker(_ title: String, current: String?, options: [String], command: @escaping (String) -> DeviceCommand) -> some View {
        Picker(title, selection: Binding(
            get: { current ?? "" },
            set: { value in
                pending = true
                requestedTarget = nil
                Task {
                    defer { pending = false }
                    do {
                        try await connection.control(entity.id, command: command(value))
                        error = nil
                    } catch {
                        self.error = (error as? ServiceCallError ?? .unavailable).message
                    }
                }
            }
        )) {
            if current == nil {
                Text("—").tag("").disabled(true)
            } else if let current, !options.contains(current) {
                Text(modeLabel(current)).tag(current).disabled(true)
            }
            ForEach(options, id: \.self) { Text(modeLabel($0)).tag($0) }
        }
        .pickerStyle(.menu)
        .controlSize(.small)
        .font(.caption)
        .padding(.leading, 30)
        .disabled(!controlsEnabled)
    }

    /** Return a readable label for a reported mode or preset without changing its service value. */
    private func modeLabel(_ value: String) -> String {
        switch value {
        case "heat_cool": "Heat/Cool"
        case "fan_only": "Fan only"
        default: value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /** Format an optional temperature in the unit reported by Home Assistant. */
    private func temperatureLabel(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...2))) + (entity.attributes.temperature_unit ?? entity.unit ?? "°")
    }

    /** Create a bounded target adjustment button for the supplied direction. */
    private func adjustmentButton(increasing: Bool) -> some View {
        let next = target.flatMap { entity.attributes.adjustedTargetTemperature(from: $0, increasing: increasing) }
        return Button {
            guard let next else { return }
            pending = true
            requestedTarget = next
            Task {
                defer { pending = false }
                do {
                    try await connection.control(entity.id, command: .targetTemperature(next))
                    error = nil
                } catch {
                    requestedTarget = nil
                    self.error = (error as? ServiceCallError ?? .unavailable).message
                }
            }
        } label: {
            Image(systemName: increasing ? "plus" : "minus")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!controlsEnabled || entity.state == "heat_cool" || next == nil || next == target)
        .accessibilityLabel(increasing ? "Increase target temperature" : "Decrease target temperature")
    }
}
