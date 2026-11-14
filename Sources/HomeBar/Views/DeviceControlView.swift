import HomeBarCore
import SwiftUI

struct DeviceControlView: View {
    let entity: HAEntity
    let connection: ConnectionViewModel
    @State private var error: String?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DeviceHeaderView(entity: entity, isExpanded: $isExpanded, send: send)
            if isExpanded && entity.domain != "switch" {
                Group {
                    if entity.domain == "light" {
                        LightControlView(entity: entity, send: send)
                    } else {
                        FanControlView(entity: entity, send: send)
                    }
                }
                .padding(.leading, 30)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(!entity.isAvailable || !connection.entities.isLive)
        .padding(.vertical, 4)
    }

    /** Send one command through the connection model and show a fixed failure message. */
    private func send(_ command: DeviceCommand) async {
        do {
            try await connection.control(entity.id, command: command)
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = (error as? ServiceCallError ?? .unavailable).message
        }
    }
}

struct DeviceHeaderView: View {
    let entity: HAEntity
    @Binding var isExpanded: Bool
    let send: (DeviceCommand) async -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pending = false

    private var canToggle: Bool {
        ["light", "switch"].contains(entity.domain) || (entity.attributes.supported_features ?? 0) & (entity.state == "on" ? 16 : 32) != 0
    }

    var body: some View {
        HStack(spacing: 10) {
            if entity.domain == "switch" {
                label
            } else {
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    label
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entity.name)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint(isExpanded ? "Hide controls" : "Show controls")
            }
            if !entity.isAvailable {
                Text(entity.stateLabel).foregroundStyle(.secondary)
                    .help(entity.updateHelp)
            }
            Toggle(entity.stateLabel, isOn: Binding(
                get: { entity.state == "on" },
                set: { value in
                    pending = true
                    Task {
                        await send(.power(value))
                        pending = false
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(pending || !canToggle)
            .accessibilityLabel(entity.name)
            .help(entity.updateHelp)
        }
        .font(.subheadline)
    }

    private var label: some View {
        HStack(spacing: 10) {
            Image(systemName: entity.symbol).foregroundStyle(.secondary).frame(width: 20)
            Text(entity.name).lineLimit(2)
            Spacer(minLength: 0)
            if entity.domain != "switch" {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
        }
        .contentShape(Rectangle())
    }
}

struct ControlSliderView: View {
    let title: String
    let value: Double?
    let range: ClosedRange<Double>
    let unit: String
    let send: (Int) async -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var draft: Double?
    @State private var editing = false
    @State private var revision = 0

    private var displayedValue: Double { min(range.upperBound, max(range.lowerBound, draft ?? value ?? range.lowerBound)) }

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(draft == nil && value == nil ? "—" : "\(Int(displayedValue.rounded()))\(unit)")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.caption)
            Slider(value: Binding(get: { displayedValue }, set: { draft = $0.rounded(); revision += 1 }), in: range) { active in
                editing = active
                if !active, draft != nil { revision += 1 }
            }
            .accessibilityLabel(title)
        }
        .task(id: revision) {
            guard let draft else { return }
            do { try await Task.sleep(for: .milliseconds(200)) }
            catch { return }
            await send(Int(draft.rounded()))
            guard !Task.isCancelled else { return }
            if !editing { self.draft = nil }
        }
        .onDisappear { draft = nil; editing = false }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { draft = nil; editing = false; revision += 1 }
        }
        .onChange(of: range) { draft = nil; editing = false; revision = 0 }
    }
}
