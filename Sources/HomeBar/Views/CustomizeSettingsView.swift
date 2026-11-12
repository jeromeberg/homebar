import AppKit
import HomeBarCore
import SwiftUI

struct CustomizeSettingsView: View {
    @Bindable var store: EntityStore
    @State private var renamingEntity: HAEntity?
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        Group {
            if let entity = renamingEntity {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Rename Entity").font(.headline)
                    TextField("Display name", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                        .onSubmit(saveName)
                    Text("Only changes the name in HomeBar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Use default name") {
                        store.setLocalName("", for: entity.id)
                        renamingEntity = nil
                    }
                    HStack {
                        Button("Cancel") { renamingEntity = nil }
                        Spacer()
                        Button("Save", action: saveName)
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .onAppear { nameFocused = true }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Customize dashboard").font(.headline)
                    Text("Drag to reorder. Double-click a row to rename.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if store.selectedIDs.isEmpty {
                        ContentUnavailableView("No selected entities", systemImage: "checklist",
                            description: Text("Add entities to customize their order and names."))
                    } else {
                        EntityCustomizationTable(store: store, entities: store.selectedEntities) { entity in
                            draftName = entity.name
                            renamingEntity = entity
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    Text("Changes are saved locally in HomeBar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: store.selectedIDs) { _, selectedIDs in
            if let entity = renamingEntity, !selectedIDs.contains(entity.id) {
                renamingEntity = nil
            }
        }
    }

    /** Save the draft for the entity being renamed and return to the customization list. */
    private func saveName() {
        guard let entity = renamingEntity else { return }
        store.setLocalName(draftName, for: entity.id)
        renamingEntity = nil
    }
}

private struct EntityCustomizationTable: NSViewRepresentable {
    let store: EntityStore
    let entities: [HAEntity]
    let renameEntity: (HAEntity) -> Void

    /** Create the native table's data source using the current store and displayed entities. */
    func makeCoordinator() -> Coordinator {
        Coordinator(store: store, entities: entities)
    }

    /** Create a scrolling table for reordering and renaming selected entities. */
    func makeNSView(context: Context) -> NSScrollView {
        let table = EntityCustomizationTableView(frame: NSRect(x: 0, y: 0, width: 340,
            height: CGFloat(entities.count) * EntityCustomizationTableView.rowHeightWithSpacing))
        table.autoresizingMask = [.width]
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("entity"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.rowHeight = EntityCustomizationTableView.rowHeightWithSpacing - EntityCustomizationTableView.rowSpacing
        table.intercellSpacing = NSSize(width: 0, height: EntityCustomizationTableView.rowSpacing)
        table.backgroundColor = .clear
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.moveRow = { [coordinator = context.coordinator] source, destination in
            guard coordinator.entities.map(\.id) == coordinator.store.selectedIDs else { return }
            coordinator.store.moveSelected(fromOffsets: IndexSet(integer: source), toOffset: destination)
            coordinator.entities = coordinator.store.selectedEntities
        }
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = table
        return scroll
    }

    /** Refresh native rows when the selected order or entity values change. */
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? EntityCustomizationTableView else { return }
        table.renameRow = { [coordinator = context.coordinator] row in
            guard coordinator.entities.indices.contains(row) else { return }
            renameEntity(coordinator.entities[row])
        }
        guard context.coordinator.entities != entities else { return }
        context.coordinator.entities = entities
        table.reloadData()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        let store: EntityStore
        var entities: [HAEntity]

        /** Retain the selection store and the table's displayed entity snapshot. */
        init(store: EntityStore, entities: [HAEntity]) {
            self.store = store
            self.entities = entities
        }

        /** Return the number of selected entities displayed in the supplied table. */
        func numberOfRows(in tableView: NSTableView) -> Int {
            entities.count
        }

        /** Create a noninteractive native label for the entity at the supplied row. */
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let entity = entities[row]
            let label = NSTextField(labelWithString: "")
            label.stringValue = "\(entity.name)\n\(entity.stateLabel)"
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 2
            label.setAccessibilityLabel(entity.name)
            let cell = NSTableCellView()
            let handle = NSImageView()
            handle.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)
            handle.contentTintColor = .secondaryLabelColor
            cell.addSubview(label)
            cell.addSubview(handle)
            cell.textField = label
            label.translatesAutoresizingMaskIntoConstraints = false
            handle.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 18),
                label.trailingAnchor.constraint(equalTo: handle.leadingAnchor, constant: -10),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                handle.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -18),
                handle.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                handle.widthAnchor.constraint(equalToConstant: 16)
            ])
            return cell
        }
    }
}
