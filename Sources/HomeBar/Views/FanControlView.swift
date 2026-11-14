import HomeBarCore
import SwiftUI

struct FanControlView: View {
    let entity: HAEntity
    let send: (DeviceCommand) async -> Void
    @State private var pendingPreset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if entity.attributes.supportsFanSpeed {
                ControlSliderView(title: "Speed", value: entity.attributes.percentage,
                                  range: 0...100, unit: "%") { await send(.percentage($0)) }
                    .help(entity.updateHelp)
            }
            if !entity.attributes.fanPresets.isEmpty {
                Picker("Mode", selection: Binding(
                    get: { entity.attributes.preset_mode ?? "" },
                    set: { mode in
                        pendingPreset = true
                        Task {
                            await send(.preset(mode))
                            pendingPreset = false
                        }
                    }
                )) {
                    if let current = entity.attributes.preset_mode, !entity.attributes.fanPresets.contains(current) {
                        Text(current).tag(current)
                    }
                    Text("None").tag("")
                        .disabled(true)
                    ForEach(entity.attributes.fanPresets, id: \.self) { Text($0).tag($0) }
                }
                .disabled(pendingPreset)
                .controlSize(.small)
                .font(.caption)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .center)
                .help(entity.updateHelp)
            }
        }
    }
}
