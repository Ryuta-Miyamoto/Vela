//
//  FileTableNSView.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/04/22.
//

import SwiftUI
import AppKit
import Quartz
import UniformTypeIdentifiers

// MARK: - Sort State

struct FileSortState: Equatable {
    var key: String       // "name" | "date" | "size"
    var ascending: Bool
    static let `default` = FileSortState(key: "name", ascending: true)
}

// MARK: - NSViewRepresentable

struct FileTableNSView: NSViewRepresentable {
    let items: [FileItem]
    var viewModel: FileExplorerViewModel
    var sortState: FileSortState
    var onSortChange: (FileSortState) -> Void
    var onAddToFavorites: ((FileItem) -> Void)?

    func makeCoordinator() -> FileTableCoordinator { FileTableCoordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSScrollView()
        sv.documentView = context.coordinator.tableView
        sv.hasVerticalScroller = true
        sv.autohidesScrollers = true
        sv.borderType = .noBorder
        return sv
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let c = context.coordinator
        c.viewModel = viewModel
        c.onSortChange = onSortChange
        c.onAddToFavorites = onAddToFavorites
        c.reloadIfNeeded(newItems: items)
        c.applySortIndicator(sortState)
    }
}

// MARK: - Coordinator

final class FileTableCoordinator: NSObject {

    var items: [FileItem] = []
    var viewModel: FileExplorerViewModel?
    var onSortChange: ((FileSortState) -> Void)?
    var onAddToFavorites: ((FileItem) -> Void)?

    private var currentSortState = FileSortState(key: "", ascending: true)
    private var isUpdatingSortIndicator = false

    let tableView = ResponsiveTableView()

    private let nameID = NSUserInterfaceItemIdentifier("name")
    private let dateID = NSUserInterfaceItemIdentifier("date")
    private let sizeID = NSUserInterfaceItemIdentifier("size")

    override init() {
        super.init()
        setupTableView()
    }

    // MARK: - Setup

    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsColumnReordering = false
        tableView.allowsMultipleSelection = true
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.rowHeight = 20

        let nameCol = NSTableColumn(identifier: nameID)
        nameCol.title = "名前"
        nameCol.minWidth = 160
        nameCol.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true)
        tableView.addTableColumn(nameCol)

        let dateCol = NSTableColumn(identifier: dateID)
        dateCol.title = "更新日"
        dateCol.width = 180
        dateCol.minWidth = 100
        dateCol.resizingMask = .userResizingMask
        dateCol.sortDescriptorPrototype = NSSortDescriptor(key: "date", ascending: true)
        tableView.addTableColumn(dateCol)

        let sizeCol = NSTableColumn(identifier: sizeID)
        sizeCol.title = "サイズ"
        sizeCol.width = 90
        sizeCol.minWidth = 60
        sizeCol.resizingMask = .userResizingMask
        sizeCol.sortDescriptorPrototype = NSSortDescriptor(key: "size", ascending: true)
        tableView.addTableColumn(sizeCol)

        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)

        tableView.onSpaceKey   = { [weak self] in self?.handleSpaceKey() }
        tableView.onReturnKey  = { [weak self] in self?.handleReturnKey() }
        tableView.onDeleteKey  = { [weak self] in self?.handleDeleteKey() }
        tableView.onCmdUp      = { [weak self] in self?.viewModel?.goUp() }
        tableView.onCmdDown    = { [weak self] in self?.handleCmdDown() }
        tableView.onCmdC       = { [weak self] in self?.handleCmdC() }
        tableView.onCmdV       = { [weak self] in self?.handleCmdV() }
        tableView.onCmdShiftN  = { [weak self] in self?.viewModel?.createFolder() }

        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu

        tableView.setDraggingSourceOperationMask([.move, .copy], forLocal: false)
        tableView.registerForDraggedTypes([.fileURL])
    }

    // MARK: - Data Update

    func reloadIfNeeded(newItems: [FileItem]) {
        guard newItems.map(\.id) != items.map(\.id) else { return }
        let selectedURLs = Set(tableView.selectedRowIndexes.compactMap {
            $0 < items.count ? items[$0].id : nil
        })
        items = newItems
        tableView.reloadData()
        let newSelection = IndexSet(newItems.indices.filter { selectedURLs.contains(newItems[$0].id) })
        tableView.selectRowIndexes(newSelection, byExtendingSelection: false)
        viewModel?.selectedItems = newSelection.compactMap { newItems[$0] }
    }

    func applySortIndicator(_ state: FileSortState) {
        guard state != currentSortState else { return }
        currentSortState = state
        isUpdatingSortIndicator = true
        defer { isUpdatingSortIndicator = false }
        let colID: NSUserInterfaceItemIdentifier
        switch state.key {
        case "date": colID = dateID
        case "size": colID = sizeID
        default:     colID = nameID
        }
        tableView.sortDescriptors = [NSSortDescriptor(key: state.key, ascending: state.ascending)]
        tableView.highlightedTableColumn = tableView.tableColumn(withIdentifier: colID)
    }

    // MARK: - Key Handlers

    @objc private func handleDoubleClick() {
        guard tableView.clickedRow >= 0, tableView.clickedRow < items.count else { return }
        viewModel?.openItem(items[tableView.clickedRow])
    }

    private func handleSpaceKey() {
        guard tableView.selectedRow >= 0, tableView.selectedRow < items.count else { return }
        let url = items[tableView.selectedRow].url
        tableView.quickLookURL = url
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().reloadData()
        } else {
            QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
        }
    }

    private func handleReturnKey() {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return }
        let item = items[row]
        if item.isDirectory {
            viewModel?.openItem(item)
        } else {
            let col = tableView.column(withIdentifier: nameID)
            guard let cell = tableView.view(atColumn: col, row: row, makeIfNecessary: false) as? FileNameCellView else { return }
            cell.beginEditing()
        }
    }

    private func handleDeleteKey() {
        let selectedRows = tableView.selectedRowIndexes
        let targets = selectedRows.compactMap { $0 < items.count ? items[$0] : nil }
        guard !targets.isEmpty else { return }
        showTrashAlert(for: targets)
    }

    private func handleCmdDown() {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return }
        viewModel?.openItem(items[row])
    }

    private func handleCmdC() {
        let paths = tableView.selectedRowIndexes
            .compactMap { $0 < items.count ? items[$0].url.path : nil }
        guard !paths.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
    }

    private func handleCmdV() {
        guard let currentURL = viewModel?.currentURL else { return }
        guard let urls = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else { return }
        for url in urls { viewModel?.copyURL(url, to: currentURL) }
    }

    // MARK: - Trash (shared between key and menu)

    private func showTrashAlert(for targets: [FileItem]) {
        let alert = NSAlert()
        alert.messageText = "ゴミ箱に入れますか？"
        alert.informativeText = targets.count == 1
            ? "「\(targets[0].name)」をゴミ箱に入れます。"
            : "\(targets.count)個の項目をゴミ箱に入れます。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "ゴミ箱に入れる")
        alert.addButton(withTitle: "キャンセル")
        guard let window = tableView.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                targets.forEach { self?.viewModel?.trashItem($0) }
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

// MARK: - NSTableViewDataSource

extension FileTableCoordinator: NSTableViewDataSource {

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard row < items.count else { return nil }
        return items[row].url as NSURL
    }

    func tableView(_ tableView: NSTableView,
                   validateDrop info: NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        guard op == .on, row >= 0, row < items.count, items[row].isDirectory else { return [] }
        let destURL = items[row].url
        let sources = info.draggingPasteboard
            .readObjects(forClasses: [NSURL.self], options: nil)?
            .compactMap { $0 as? URL } ?? []
        for src in sources {
            if src == destURL || destURL.path.hasPrefix(src.path + "/") { return [] }
        }
        return NSEvent.modifierFlags.contains(.option) ? .copy : .move
    }

    func tableView(_ tableView: NSTableView,
                   acceptDrop info: NSDraggingInfo,
                   row: Int,
                   dropOperation op: NSTableView.DropOperation) -> Bool {
        guard op == .on, row >= 0, row < items.count, items[row].isDirectory else { return false }
        let destURL = items[row].url
        let isCopy = NSEvent.modifierFlags.contains(.option)
        let sources = info.draggingPasteboard
            .readObjects(forClasses: [NSURL.self], options: nil)?
            .compactMap { $0 as? URL } ?? []
        for src in sources {
            if isCopy { viewModel?.copyURL(src, to: destURL) }
            else      { viewModel?.moveURL(src, to: destURL) }
        }
        return true
    }

    func tableView(_ tableView: NSTableView,
                   sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !isUpdatingSortIndicator,
              let sd = tableView.sortDescriptors.first,
              let key = sd.key else { return }
        let newState = FileSortState(key: key, ascending: sd.ascending)
        guard newState != currentSortState else { return }
        currentSortState = newState
        onSortChange?(newState)
    }
}

// MARK: - NSTableViewDelegate

extension FileTableCoordinator: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard row < items.count else { return nil }
        let item = items[row]

        switch tableColumn?.identifier {
        case nameID:
            let cell = (tableView.makeView(withIdentifier: nameID, owner: nil) as? FileNameCellView)
                       ?? FileNameCellView()
            cell.identifier = nameID
            cell.configure(with: item) { [weak self] newName in
                self?.viewModel?.renameItem(item, to: newName)
            }
            return cell

        case dateID:
            let cell = (tableView.makeView(withIdentifier: dateID, owner: nil) as? FileLabelCellView)
                       ?? FileLabelCellView()
            cell.identifier = dateID
            cell.set(text: Self.dateFormatter.string(from: item.modifiedDate))
            return cell

        case sizeID:
            let cell = (tableView.makeView(withIdentifier: sizeID, owner: nil) as? FileLabelCellView)
                       ?? FileLabelCellView()
            cell.identifier = sizeID
            let text = item.isDirectory
                ? "—"
                : ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)
            cell.set(text: text)
            return cell

        default:
            return nil
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let selected = tableView.selectedRowIndexes.compactMap { $0 < items.count ? items[$0] : nil }
        viewModel?.selectedItems = selected
    }
}

// MARK: - NSMenuDelegate (Context Menu)

extension FileTableCoordinator: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = tableView.clickedRow

        if row < 0 {
            addMenuItem(to: menu, title: "新規フォルダ作成", action: #selector(menuCreateFolder))
        } else {
            let item = items[row]
            addMenuItem(to: menu, title: "開く",       action: #selector(menuOpenItem))
            menu.addItem(.separator())
            addMenuItem(to: menu, title: "名前を変更", action: #selector(menuRenameItem))
            addMenuItem(to: menu, title: "コピー",     action: #selector(menuCopyItem))
            addMenuItem(to: menu, title: "移動",       action: #selector(menuMoveItem))
            if item.isDirectory {
                menu.addItem(.separator())
                addMenuItem(to: menu, title: "お気に入りに追加", action: #selector(menuAddToFavorites))
            }
            menu.addItem(.separator())

            let trashTitle: String
            let selectedCount = tableView.selectedRowIndexes.count
            if tableView.selectedRowIndexes.contains(row) && selectedCount > 1 {
                trashTitle = "\(selectedCount)個をゴミ箱に入れる"
            } else {
                trashTitle = "ゴミ箱に入れる"
            }
            addMenuItem(to: menu, title: trashTitle, action: #selector(menuTrashItem))
        }
    }

    @discardableResult
    private func addMenuItem(to menu: NSMenu, title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func menuCreateFolder() { viewModel?.createFolder() }

    @objc private func menuOpenItem() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        viewModel?.openItem(items[row])
    }

    @objc private func menuRenameItem() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        let col = tableView.column(withIdentifier: nameID)
        guard let cell = tableView.view(atColumn: col, row: row, makeIfNecessary: false) as? FileNameCellView else { return }
        cell.beginEditing()
    }

    @objc private func menuCopyItem() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        viewModel?.copyItem(items[row])
    }

    @objc private func menuMoveItem() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        viewModel?.moveItem(items[row])
    }

    @objc private func menuAddToFavorites() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        onAddToFavorites?(items[row])
    }

    @objc private func menuTrashItem() {
        let clickedRow = tableView.clickedRow
        guard clickedRow >= 0, clickedRow < items.count else { return }

        let targets: [FileItem]
        if tableView.selectedRowIndexes.contains(clickedRow) && tableView.selectedRowIndexes.count > 1 {
            targets = tableView.selectedRowIndexes.compactMap { $0 < items.count ? items[$0] : nil }
        } else {
            targets = [items[clickedRow]]
        }
        showTrashAlert(for: targets)
    }
}

// MARK: - ResponsiveTableView

final class ResponsiveTableView: NSTableView, QLPreviewPanelDataSource {
    var onSpaceKey:  (() -> Void)?
    var onReturnKey: (() -> Void)?
    var onDeleteKey: (() -> Void)?
    var onCmdUp:     (() -> Void)?
    var onCmdDown:   (() -> Void)?
    var onCmdC:      (() -> Void)?
    var onCmdV:      (() -> Void)?
    var onCmdShiftN: (() -> Void)?
    var quickLookURL: URL?

    override func keyDown(with event: NSEvent) {
        let cmd = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 49:      // Space
            onSpaceKey?()
        case 36, 76:  // Return, numpad Enter
            onReturnKey?()
        case 51, 117: // Delete (backspace), Forward Delete
            onDeleteKey?()
        case 125 where cmd: // Cmd+↓
            onCmdDown?()
        case 126 where cmd: // Cmd+↑
            onCmdUp?()
        default:
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else { return super.performKeyEquivalent(with: event) }
        let shift = flags.contains(.shift)

        switch event.keyCode {
        case 125: onCmdDown?(); return true   // Cmd+↓
        case 126: onCmdUp?();   return true   // Cmd+↑
        default: break
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c" where !shift: onCmdC?(); return true
        case "v" where !shift: onCmdV?(); return true
        case "n" where shift:  onCmdShiftN?(); return true
        default: break
        }

        return super.performKeyEquivalent(with: event)
    }

    // QL responder chain
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { quickLookURL != nil }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = self }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {}

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { quickLookURL != nil ? 1 : 0 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        quickLookURL.map { $0 as NSURL }
    }
}

// MARK: - FileNameCellView

final class FileNameCellView: NSTableCellView, NSTextFieldDelegate {
    private let icon = NSImageView()
    private let nameField = NSTextField()
    private var onCommit: ((String) -> Void)?
    private var originalName = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        nameField.isBezeled = false
        nameField.drawsBackground = false
        nameField.isEditable = false
        nameField.isSelectable = false
        nameField.lineBreakMode = .byTruncatingMiddle
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.delegate = self

        addSubview(icon)
        addSubview(nameField)
        imageView = icon
        textField = nameField

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            nameField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
            nameField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(with item: FileItem, onCommit: @escaping (String) -> Void) {
        originalName = item.name
        self.onCommit = onCommit
        nameField.stringValue = item.name
        let img = NSWorkspace.shared.icon(forFile: item.url.path)
        img.size = NSSize(width: 16, height: 16)
        icon.image = img
    }

    func beginEditing() {
        nameField.isEditable = true
        nameField.isBezeled = true
        nameField.drawsBackground = true
        window?.makeFirstResponder(nameField)
        nameField.selectText(nil)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        nameField.isEditable = false
        nameField.isBezeled = false
        nameField.drawsBackground = false
        let newName = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        if !newName.isEmpty, newName != originalName {
            onCommit?(newName)
        } else {
            nameField.stringValue = originalName
        }
    }

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy selector: Selector) -> Bool {
        if selector == #selector(cancelOperation(_:)) {
            nameField.stringValue = originalName
            nameField.abortEditing()
            nameField.isEditable = false
            nameField.isBezeled = false
            nameField.drawsBackground = false
            return true
        }
        return false
    }
}

// MARK: - FileLabelCellView

final class FileLabelCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(text: String) { label.stringValue = text }
}
