import AppKit
import ApplicationServices

/// Searchable command palette over the frontmost app's menu bar (spec item #6).
/// Opened from Radial 2; type (Wispr or keyboard) to filter, click a row to fire
/// the menu item via AXPress. Escape, clicking outside, or losing key closes it.
///
/// The panel is a `.nonactivatingPanel` that CAN become key (Spotlight-style):
/// the search field gets keystrokes without activating Whisker, so the target
/// app stays frontmost and its menu items stay valid.
@MainActor
final class PaletteController: NSObject, NSSearchFieldDelegate, NSTableViewDataSource,
                               NSTableViewDelegate, NSWindowDelegate {
    private final class KeyablePanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override func cancelOperation(_ sender: Any?) {
            (delegate as? PaletteController)?.close()
        }
    }

    private var panel: NSPanel?
    private var searchField: NSSearchField?
    private var tableView: NSTableView?
    private var targetApp: NSRunningApplication?
    private var allCommands: [PaletteCommand] = []
    private var filtered: [PaletteCommand] = []

    private let panelSize = NSSize(width: 560, height: 420)

    func open() {
        close()

        // Capture the target BEFORE our panel takes key: its menu bar is what we scan.
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        targetApp = app
        allCommands = MenuScanner.commands(forPID: app.processIdentifier)
        filtered = allCommands

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let origin = NSPoint(x: screen.frame.midX - panelSize.width / 2,
                             y: screen.frame.midY - panelSize.height / 2 + 60)

        let panel = KeyablePanel(contentRect: NSRect(origin: origin, size: panelSize),
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.delegate = self
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        content.material = .hudWindow
        content.blendingMode = .behindWindow
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = 16
        content.layer?.masksToBounds = true

        let search = NSSearchField(frame: NSRect(x: 16, y: panelSize.height - 46,
                                                 width: panelSize.width - 32, height: 30))
        search.placeholderString = "Search \(app.localizedName ?? "app") menus…"
        search.delegate = self
        search.focusRingType = .none
        content.addSubview(search)
        searchField = search

        let table = NSTableView()
        table.headerView = nil
        table.rowHeight = 26
        table.style = .plain
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        column.width = panelSize.width - 32
        table.addTableColumn(column)

        let scroll = NSScrollView(frame: NSRect(x: 8, y: 8,
                                                width: panelSize.width - 16,
                                                height: panelSize.height - 62))
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        content.addSubview(scroll)
        tableView = table

        panel.contentView = content
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(search)
        table.reloadData()
    }

    func close() {
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        searchField = nil
        tableView = nil
        targetApp = nil
        allCommands = []
        filtered = []
    }

    // MARK: - Filtering

    func controlTextDidChange(_ obj: Notification) {
        let query = searchField?.stringValue ?? ""
        filtered = allCommands.filter { MenuScanner.matches(path: $0.path, query: query) }
        tableView?.reloadData()
        if !filtered.isEmpty { tableView?.scrollRowToVisible(0) }
    }

    /// Enter in the search field fires the top match; Escape closes.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            fire(row: tableView?.selectedRow ?? 0)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveUp(_:)):
            moveSelection(down: selector == #selector(NSResponder.moveDown(_:)))
            return true
        default:
            return false
        }
    }

    private func moveSelection(down: Bool) {
        guard let table = tableView, !filtered.isEmpty else { return }
        let current = max(table.selectedRow, 0)
        let next = min(max(current + (down ? 1 : -1), 0), filtered.count - 1)
        table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        table.scrollRowToVisible(next)
    }

    // MARK: - Firing

    @objc private func rowClicked() {
        fire(row: tableView?.clickedRow ?? -1)
    }

    private func fire(row: Int) {
        let index = row >= 0 ? row : 0
        guard filtered.indices.contains(index) else { return }
        let command = filtered[index]
        let app = targetApp
        close()
        // Make sure the target app is frontmost again before pressing its menu item.
        app?.activate()
        AXUIElementPerformAction(command.element, "AXPress" as CFString)
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard filtered.indices.contains(row) else { return nil }
        let id = NSUserInterfaceItemIdentifier("cell")
        let text: NSTextField
        if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField {
            text = reused
        } else {
            text = NSTextField(labelWithString: "")
            text.identifier = id
            text.font = .systemFont(ofSize: 13)
            text.lineBreakMode = .byTruncatingTail
        }
        text.stringValue = filtered[row].path
        return text
    }

    // MARK: - Window

    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}
