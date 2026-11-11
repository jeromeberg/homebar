import HomeBarCore
import SwiftUI

struct EntityRowView: View {
    let entity: HAEntity

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entity.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(entity.name).lineLimit(2)
            Spacer(minLength: 8)
            Text(entity.stateLabel)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .font(.subheadline)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
