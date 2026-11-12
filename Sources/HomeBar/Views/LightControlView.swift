import HomeBarCore
import SwiftUI

struct LightControlView: View {
    let entity: HAEntity
    let send: (DeviceCommand) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DeviceHeaderView(entity: entity, send: send)
            VStack(spacing: 8) {
                if entity.attributes.supportsBrightness {
                    ControlSliderView(title: "Brightness", value: entity.attributes.brightnessPercent,
                                      range: 0...100, unit: "%") { await send(.brightness($0)) }
                }
                if let range = entity.attributes.temperatureRange {
                    ControlSliderView(title: "Temperature", value: entity.attributes.color_temp_kelvin,
                                      range: range, unit: " K") { await send(.temperature($0)) }
                }
            }
            .padding(.leading, 30)
        }
    }
}
