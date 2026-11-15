import AppKit
import HomeBarCore
import SwiftUI

struct CustomizeSettingsView: View {
    @Bindable var store: EntityStore
    @State private var renamingEntity: HAEntity?
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Customize dashboard").font(.headline)
            Text("Drag to reorder. Click the pencil to rename.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if store.selectedIDs.isEmpty {
                ContentUnavailableView {
                    Text("No selected entities")
                } description: {
                    Text("Add entities to customize their order and names.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EntityCustomizationTable(store: store, entities: store.selectedEntities) { entity in
                    draftName = entity.name
                    renamingEntity = entity
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                }
            }
            Text("Changes are saved locally in HomeBar.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $renamingEntity) { entity in
            VStack(alignment: .leading, spacing: 16) {
                Text("Rename in HomeBar").font(.headline)
                Text("Home Assistant name: \(entity.defaultName)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("Display name", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .onSubmit(saveName)
                Text("Only changes the name in HomeBar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Use Home Assistant name") {
                        store.setLocalName("", for: entity.id)
                        renamingEntity = nil
                    }
                    Spacer()
                    Button("Cancel") { renamingEntity = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("Save", action: saveName)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 440)
            .onAppear { nameFocused = true }
        }
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

struct EntityCustomizationTable: NSViewRepresentable {
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
        table.gridStyleMask = .solidHorizontalGridLineMask
        table.gridColor = .separatorColor
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

        /** Request renaming for the entity in the supplied button's current table row. */
        @objc private func rename(_ sender: NSButton) {
            guard let table = sender.enclosingScrollView?.documentView as? EntityCustomizationTableView else { return }
            let row = table.row(for: sender)
            guard entities.indices.contains(row) else { return }
            table.renameRow?(row)
        }

        /** Create an icon, name hierarchy, rename button, and drag handle for the supplied row. */
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let entity = entities[row]
            let label = NSTextField(labelWithString: entity.name)
            label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            label.lineBreakMode = .byTruncatingTail
            let names = NSStackView(views: [label])
            names.orientation = .vertical
            names.alignment = .leading
            names.spacing = 2
            if entity.name != entity.defaultName {
                let original = NSTextField(labelWithString: entity.defaultName)
                original.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
                original.textColor = .secondaryLabelColor
                original.lineBreakMode = .byTruncatingTail
                names.addArrangedSubview(original)
                original.widthAnchor.constraint(lessThanOrEqualTo: names.widthAnchor).isActive = true
            }
            let icon = NSImageView()
            icon.image = NSImage(systemSymbolName: entity.symbol, accessibilityDescription: nil)
            icon.contentTintColor = .secondaryLabelColor
            let pencil = NSButton(title: "", target: self, action: #selector(rename(_:)))
            pencil.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Rename")
            pencil.isBordered = false
            pencil.contentTintColor = .secondaryLabelColor
            pencil.toolTip = "Rename in HomeBar"
            pencil.setAccessibilityLabel("Rename \(entity.name)")
            let handle = NSImageView()
            handle.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)
            handle.contentTintColor = .tertiaryLabelColor
            let cell = NSTableCellView()
            for view in [icon, names, pencil, handle] {
                cell.addSubview(view)
                view.translatesAutoresizingMaskIntoConstraints = false
            }
            cell.textField = label
            cell.toolTip = entity.name
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                icon.widthAnchor.constraint(equalToConstant: 20),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                names.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
                names.trailingAnchor.constraint(equalTo: pencil.leadingAnchor, constant: -12),
                names.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                label.widthAnchor.constraint(lessThanOrEqualTo: names.widthAnchor),
                pencil.widthAnchor.constraint(equalToConstant: 24),
                pencil.heightAnchor.constraint(equalToConstant: 24),
                pencil.trailingAnchor.constraint(equalTo: handle.leadingAnchor, constant: -8),
                pencil.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                handle.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
                handle.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                handle.widthAnchor.constraint(equalToConstant: 16)
            ])
            return cell
        }
    }
}
