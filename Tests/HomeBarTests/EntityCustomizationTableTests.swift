import AppKit
import Foundation
import HomeBarCore
import Testing
@testable import HomeBar

@MainActor
struct EntityCustomizationTableTests {
    @MainActor
    private final class Rows: NSObject, NSTableViewDataSource {
        /** Supply three rows for mouse interaction tests. */
        func numberOfRows(in tableView: NSTableView) -> Int { 3 }
    }

    /** Create a mouse event at the supplied table position without a system drag session. */
    private func event(_ type: NSEvent.EventType, at point: NSPoint, in table: NSTableView, clickCount: Int = 1) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: table.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                                       windowNumber: 0, context: nil, eventNumber: 0, clickCount: clickCount, pressure: 1))
    }

    @Test
    /** Keep visibility buttons clickable and toggle the current row without changing selection or order. */
    func visibilityButtonHidesAndShowsCurrentRow() throws {
        let defaults = UserDefaults(suiteName: "HomeBarVisibilityTests.\(UUID().uuidString)")!
        let store = EntityStore(defaults: defaults)
        let ids = ["light.desk", "fan.bedroom"]
        for id in ids { store.setSelected(id, selected: true) }
        let coordinator = EntityCustomizationTable.Coordinator(store: store, entities: store.selectedEntities)
        let table = EntityCustomizationTableView(frame: NSRect(x: 0, y: 0, width: 480, height: 100))
        let column = NSTableColumn(identifier: .init("entity"))
        column.width = 448
        table.addTableColumn(column)
        table.rowHeight = 44
        table.dataSource = coordinator
        table.delegate = coordinator
        let scroll = NSScrollView(frame: table.frame)
        scroll.documentView = table
        table.reloadData()
        let cell = try #require(table.view(atColumn: 0, row: 1, makeIfNecessary: true))
        cell.layoutSubtreeIfNeeded()
        let hide = try #require(cell.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == "Hide from dashboard" })
        let point = table.superview!.convert(NSPoint(x: hide.bounds.midX, y: hide.bounds.midY), from: hide)
        let hit = table.hitTest(point)
        #expect(hit === hide || hit?.isDescendant(of: hide) == true)
        hide.performClick(nil)
        #expect(store.hiddenIDs == [ids[1]])
        #expect(store.selectedIDs == ids)
        #expect(store.dashboardEntities.map(\.id) == [ids[0]])
        let updatedCell = try #require(table.view(atColumn: 0, row: 1, makeIfNecessary: true))
        let show = try #require(updatedCell.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == "Show on dashboard" })
        show.performClick(nil)
        #expect(store.hiddenIDs.isEmpty)
        #expect(store.dashboardEntities.map(\.id) == ids)
        withExtendedLifetime((coordinator, scroll)) {}
    }

    @Test
    /** Keep the pencil clickable and rename its current row without starting a reorder. */
    func pencilRenamesCurrentRow() throws {
        let defaults = UserDefaults(suiteName: "HomeBarPencilTests.\(UUID().uuidString)")!
        let store = EntityStore(defaults: defaults)
        store.setSelected("light.desk", selected: true)
        store.setSelected("fan.bedroom", selected: true)
        let coordinator = EntityCustomizationTable.Coordinator(store: store, entities: store.selectedEntities)
        let table = EntityCustomizationTableView(frame: NSRect(x: 0, y: 0, width: 340, height: 100))
        table.addTableColumn(NSTableColumn(identifier: .init("entity")))
        table.rowHeight = 44
        table.dataSource = coordinator
        table.delegate = coordinator
        let scroll = NSScrollView(frame: table.frame)
        scroll.documentView = table
        table.reloadData()
        let cell = try #require(table.view(atColumn: 0, row: 1, makeIfNecessary: true))
        cell.layoutSubtreeIfNeeded()
        let pencil = try #require(cell.subviews.compactMap { $0 as? NSButton }.first)
        var renamedRow: Int?
        var moves = 0
        table.renameRow = { renamedRow = $0 }
        table.moveRow = { _, _ in moves += 1 }
        let point = table.superview!.convert(NSPoint(x: pencil.bounds.midX, y: pencil.bounds.midY), from: pencil)
        let hit = table.hitTest(point)
        #expect(hit === pencil || hit?.isDescendant(of: pencil) == true)
        pencil.performClick(nil)
        #expect(renamedRow == 1)
        #expect(moves == 0)
        withExtendedLifetime((coordinator, scroll)) {}
    }

    @Test
    /** Drag a row down and up using real mouse event handlers, then verify the persisted order. */
    func mouseReleaseSavesOrder() throws {
        let defaults = UserDefaults(suiteName: "HomeBarReorderTests.\(UUID().uuidString)")!
        let store = EntityStore(defaults: defaults)
        let original = ["light.desk", "switch.plug", "sensor.air"]
        for id in original { store.setSelected(id, selected: true) }
        let table = EntityCustomizationTableView(frame: NSRect(x: 0, y: 0, width: 340, height: 200))
        let rows = Rows()
        table.addTableColumn(NSTableColumn(identifier: .init("entity")))
        table.dataSource = rows
        table.rowHeight = EntityCustomizationTableView.rowHeightWithSpacing - EntityCustomizationTableView.rowSpacing
        table.intercellSpacing = NSSize(width: 0, height: EntityCustomizationTableView.rowSpacing)
        table.reloadData()
        table.moveRow = { source, destination in
            store.moveSelected(fromOffsets: IndexSet(integer: source), toOffset: destination)
        }
        let first = NSPoint(x: 30, y: table.rect(ofRow: 0).midY)
        let bottom = NSPoint(x: 30, y: table.rect(ofRow: 2).maxY - 2)
        try table.mouseDown(with: event(.leftMouseDown, at: first, in: table))
        try table.mouseDragged(with: event(.leftMouseDragged, at: bottom, in: table))
        try table.mouseUp(with: event(.leftMouseUp, at: bottom, in: table))
        #expect(store.selectedIDs == ["switch.plug", "sensor.air", "light.desk"])
        #expect(EntityStore(defaults: defaults).selectedIDs == store.selectedIDs)

        let last = NSPoint(x: 30, y: table.rect(ofRow: 2).midY)
        let top = NSPoint(x: 30, y: table.rect(ofRow: 0).minY + 2)
        try table.mouseDown(with: event(.leftMouseDown, at: last, in: table))
        try table.mouseDragged(with: event(.leftMouseDragged, at: top, in: table))
        try table.mouseUp(with: event(.leftMouseUp, at: top, in: table))
        #expect(store.selectedIDs == original)
        #expect(EntityStore(defaults: defaults).selectedIDs == original)
        withExtendedLifetime(rows) {}
    }

    @Test
    /** Request renaming on double-click without allowing that click to start a reorder. */
    func doubleClickRenamesWithoutMoving() throws {
        let table = EntityCustomizationTableView(frame: NSRect(x: 0, y: 0, width: 340, height: 200))
        let rows = Rows()
        table.addTableColumn(NSTableColumn(identifier: .init("entity")))
        table.dataSource = rows
        table.reloadData()
        var renamedRow: Int?
        var moves = 0
        table.renameRow = { renamedRow = $0 }
        table.moveRow = { _, _ in moves += 1 }
        let point = NSPoint(x: 30, y: table.rect(ofRow: 1).midY)
        try table.mouseDown(with: event(.leftMouseDown, at: point, in: table))
        try table.mouseUp(with: event(.leftMouseUp, at: point, in: table))
        #expect(renamedRow == nil)
        try table.mouseDown(with: event(.leftMouseDown, at: point, in: table, clickCount: 2))
        let away = NSPoint(x: 30, y: table.rect(ofRow: 2).midY)
        try table.mouseDragged(with: event(.leftMouseDragged, at: away, in: table))
        try table.mouseUp(with: event(.leftMouseUp, at: away, in: table))
        #expect(renamedRow == 1)
        #expect(moves == 0)
        withExtendedLifetime(rows) {}
    }

    @Test(arguments: [0, 2])
    /** Cancel a pending move when dragging back within the starting threshold from either direction. */
    func returningToStartCancelsMove(startRow: Int) throws {
        let table = EntityCustomizationTableView(frame: NSRect(x: 0, y: 0, width: 340, height: 200))
        let rows = Rows()
        table.addTableColumn(NSTableColumn(identifier: .init("entity")))
        table.dataSource = rows
        table.reloadData()
        var moves = 0
        table.moveRow = { _, _ in moves += 1 }
        let start = NSPoint(x: 30, y: table.rect(ofRow: startRow).midY)
        let away = NSPoint(x: 30, y: table.rect(ofRow: 2 - startRow).midY)
        let returned = NSPoint(x: start.x, y: start.y + 2)
        try table.mouseDown(with: event(.leftMouseDown, at: start, in: table))
        try table.mouseDragged(with: event(.leftMouseDragged, at: away, in: table))
        try table.mouseDragged(with: event(.leftMouseDragged, at: returned, in: table))
        try table.mouseUp(with: event(.leftMouseUp, at: returned, in: table))
        #expect(moves == 0)
        withExtendedLifetime(rows) {}
    }

    @Test
    /** Ignore clicks and releases outside the table, and clear a cancelled drag before the next click. */
    func clicksAndCancelledMoves() throws {
        let table = EntityCustomizationTableView(frame: NSRect(x: 0, y: 0, width: 340, height: 200))
        let rows = Rows()
        table.addTableColumn(NSTableColumn(identifier: .init("entity")))
        table.dataSource = rows
        table.reloadData()
        var moves = 0
        table.moveRow = { _, _ in moves += 1 }
        let first = NSPoint(x: 30, y: table.rect(ofRow: 0).midY)
        #expect(moves == 0)
        try table.mouseDown(with: event(.leftMouseDown, at: first, in: table))
        try table.mouseUp(with: event(.leftMouseUp, at: first, in: table))
        #expect(moves == 0)
        let outside = NSPoint(x: -20, y: table.rect(ofRow: 2).midY)
        try table.mouseDown(with: event(.leftMouseDown, at: first, in: table))
        try table.mouseDragged(with: event(.leftMouseDragged, at: outside, in: table))
        try table.mouseUp(with: event(.leftMouseUp, at: outside, in: table))
        #expect(moves == 0)
        try table.mouseDown(with: event(.leftMouseDown, at: first, in: table))
        try table.mouseUp(with: event(.leftMouseUp, at: first, in: table))
        #expect(moves == 0)
        withExtendedLifetime(rows) {}
    }
}
