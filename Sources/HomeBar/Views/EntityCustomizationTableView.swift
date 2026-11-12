import AppKit

@MainActor
final class EntityCustomizationTableView: NSTableView {
    static let rowHeightWithSpacing: CGFloat = 56
    static let rowSpacing: CGFloat = 2

    var moveRow: ((Int, Int) -> Void)?
    var renameRow: ((Int) -> Void)?
    private var sourceRow: Int?
    private var insertionRow: Int?
    private var startPoint = NSPoint.zero

    /** Route row clicks to the table so labels and handles use the same mouse tracking. */
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    /** Start row movement on a click, or request renaming on a double-click. */
    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        let row = row(at: startPoint)
        sourceRow = row >= 0 ? row : nil
        insertionRow = nil
        if let sourceRow { selectRowIndexes(IndexSet(integer: sourceRow), byExtendingSelection: false) }
        if event.clickCount == 2, let sourceRow {
            self.sourceRow = nil
            renameRow?(sourceRow)
        }
    }

    /** Track vertical movement, scroll near the edges, and show the pending insertion position. */
    override func mouseDragged(with event: NSEvent) {
        guard sourceRow != nil else { return }
        autoscroll(with: event)
        let point = convert(event.locationInWindow, from: nil)
        guard abs(point.y - startPoint.y) >= 4 else {
            insertionRow = nil
            needsDisplay = true
            return
        }
        let row = row(at: point)
        if row >= 0 {
            insertionRow = row + (point.y >= rect(ofRow: row).midY ? 1 : 0)
        } else {
            insertionRow = point.y <= 0 ? 0 : numberOfRows
        }
        needsDisplay = true
    }

    /** Save the pending move on mouse release inside the table's visible area. */
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let sourceRow, let insertionRow, bounds.contains(point), visibleRect.contains(point) {
            moveRow?(sourceRow, insertionRow)
            reloadData()
            deselectAll(nil)
        }
        sourceRow = nil
        insertionRow = nil
        needsDisplay = true
    }

    /** Draw an insertion line between rows while the mouse is dragging. */
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let insertionRow else { return }
        let y = insertionRow < numberOfRows ? rect(ofRow: insertionRow).minY : rect(ofRow: numberOfRows - 1).maxY
        NSColor.controlAccentColor.setFill()
        NSRect(x: 12, y: y - 1, width: max(0, bounds.width - 24), height: 2).fill()
    }

    /** Cancel any unfinished movement when the customization table leaves its window. */
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            sourceRow = nil
            insertionRow = nil
        }
    }
}
