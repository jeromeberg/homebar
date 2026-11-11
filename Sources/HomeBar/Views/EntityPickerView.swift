import HomeBarCore
import SwiftUI

struct EntityPickerView: View {
    @Bindable var store: EntityStore
    let connected: Bool
    @State private var search = ""
    @State private var showHidden = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search entities by name", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search entities by name")
            Toggle("Show disabled, hidden, and diagnostic entities", isOn: $showHidden)
                .toggleStyle(.checkbox)
                .font(.caption)
            if !connected {
                Label("Connect to Home Assistant to browse current entities.", systemImage: "wifi.slash")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if store.isLoading { ProgressView("Loading entities…").controlSize(.small) }
            ForEach(store.errors, id: \.self) { error in
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
            let groups = store.groups(search: search, showHidden: showHidden)
            if groups.isEmpty && !store.isLoading {
                ContentUnavailableView("No entities found", systemImage: "line.3.horizontal.decrease",
                    description: Text("Only lights, fans, and sensors are supported. Try another search or include hidden entities."))
            } else {
                List {
                    ForEach(groups) { group in
                        Section(group.name) {
                            ForEach(group.entities) { entity in
                                Toggle(isOn: Binding(
                                    get: { store.selectedIDs.contains(entity.id) },
                                    set: { store.setSelected(entity.id, selected: $0) }
                                )) {
                                    EntityRowView(entity: entity)
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                }.listStyle(.inset)
            }
            Text("\(store.selectedIDs.count) selected · Changes are saved automatically")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20)
    }
}
