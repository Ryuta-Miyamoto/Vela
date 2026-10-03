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
    // 表示言語の変更時に updateNSView を走らせ、列見出しを差し替えるために受け取る
    var language: AppLanguage
    var onSortChange: (FileSortState) -> Void
    var onAddToFavorites: ((FileItem) -> Void)?
    var onOpenInNewTab: ((URL) -> Void)?

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
        c.onOpenInNewTab = onOpenInNewTab
        c.reloadIfNeeded(newItems: items)
        c.applySortIndicator(sortState)
        c.applyLanguage(language)
    }
}

// MARK: - Coordinator

final class FileTableCoordinator: NSObject {

    var items: [FileItem] = []
    var viewModel: FileExplorerViewModel?
    var onSortChange: ((FileSortState) -> Void)?
    var onAddToFavorites: ((FileItem) -> Void)?
    var onOpenInNewTab: ((URL) -> Void)?

    private var currentSortState = FileSortState(key: "", ascending: true)
    private var currentLanguage: AppLanguage?
    private var isUpdatingSortIndicator = false
    // show(relativeTo:of:preferredEdge:) はピッカーを保持しないため、表示中は強参照が必要
    private var sharingPicker: NSSharingServicePicker?

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
        nameCol.minWidth = 160
        nameCol.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true)
        tableView.addTableColumn(nameCol)

        let dateCol = NSTableColumn(identifier: dateID)
        dateCol.width = 180
        dateCol.minWidth = 100
        dateCol.resizingMask = .userResizingMask
        dateCol.sortDescriptorPrototype = NSSortDescriptor(key: "date", ascending: true)
        tableView.addTableColumn(dateCol)

        let sizeCol = NSTableColumn(identifier: sizeID)
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
        tableView.onCopy       = { [weak self] in self?.handleCopy() }
        tableView.onPaste      = { [weak self] in self?.handlePaste() }
        tableView.onCmdShiftN  = { [weak self] in self?.viewModel?.createFolder() }
        tableView.onMiddleClick = { [weak self] row in self?.handleMiddleClick(row: row) }
        tableView.onUndoRedo   = { [weak self] in self?.viewModel?.reload() }

        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu

        tableView.setDraggingSourceOperationMask([.move, .copy], forLocal: false)
        tableView.registerForDraggedTypes([.fileURL])
    }

    // MARK: - Data Update

    func reloadIfNeeded(newItems: [FileItem]) {
        // 項目の並びが同じなら、サイズや更新日が変わった行だけを描き直す（フォルダ監視による再読み込み向け）
        guard newItems.map(\.id) != items.map(\.id) else {
            let changedRows = IndexSet(newItems.indices.filter {
                newItems[$0].size != items[$0].size || newItems[$0].modifiedDate != items[$0].modifiedDate
            })
            items = newItems
            if !changedRows.isEmpty {
                tableView.reloadData(forRowIndexes: changedRows,
                                     columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
                // 選択中の項目の合計サイズ（ステータスバー）も最新の値にする
                viewModel?.selectedItems = tableView.selectedRowIndexes.compactMap { $0 < items.count ? items[$0] : nil }
            }
            return
        }
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

    func applyLanguage(_ language: AppLanguage) {
        guard language != currentLanguage else { return }
        currentLanguage = language
        tableView.tableColumn(withIdentifier: nameID)?.title = L10n.columnName
        tableView.tableColumn(withIdentifier: dateID)?.title = L10n.columnDateModified
        tableView.tableColumn(withIdentifier: sizeID)?.title = L10n.columnSize
        // 日付の表記も表示言語に合わせる
        Self.dateFormatter.locale = language.locale
        tableView.reloadData()
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
        // Finder と同様、Return は常に名前変更（フォルダを開くのはダブルクリック／Cmd+↓）
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return }
        promptRename(for: items[row])
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

    // .app などのパッケージはダブルクリックと同じく単一ファイル扱いとし、新規タブでは開かない
    private func handleMiddleClick(row: Int) {
        guard row >= 0, row < items.count else { return }
        let item = items[row]
        guard item.isDirectory, !item.isPackage else { return }
        onOpenInNewTab?(item.url)
    }

    private func handleCopy() {
        let paths = tableView.selectedRowIndexes
            .compactMap { $0 < items.count ? items[$0].url.path : nil }
        copyStrings(paths)
    }

    private func copyStrings(_ strings: [String]) {
        guard !strings.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(strings.joined(separator: "\n"), forType: .string)
    }

    private func handlePaste() {
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
        alert.messageText = L10n.moveToTrashConfirm
        alert.informativeText = targets.count == 1
            ? L10n.moveToTrashMessage(name: targets[0].name)
            : L10n.moveToTrashMessage(count: targets.count)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.moveToTrash)
        alert.addButton(withTitle: L10n.cancel)
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
            cell.configure(with: item)
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

    // 頭文字ジャンプ（type-to-select）。ビューベースの NSTableView は、この照合用の文字列を
    // 返さないと文字キーを打っても行が選ばれない
    func tableView(_ tableView: NSTableView,
                   typeSelectStringFor tableColumn: NSTableColumn?,
                   row: Int) -> String? {
        guard row < items.count, tableColumn == nil || tableColumn?.identifier == nameID else { return nil }
        return items[row].name
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
            addMenuItem(to: menu, title: L10n.newFolder, action: #selector(menuCreateFolder))
        } else {
            let item = items[row]
            addMenuItem(to: menu, title: L10n.open, action: #selector(menuOpenItem))
            if item.isPackage {
                addMenuItem(to: menu, title: L10n.showPackageContents, action: #selector(menuShowPackageContents))
            }
            menu.addItem(.separator())
            addMenuItem(to: menu, title: L10n.share, action: #selector(menuShareItem))
            menu.addItem(.separator())
            addMenuItem(to: menu, title: L10n.rename, action: #selector(menuRenameItem))
            addMenuItem(to: menu, title: L10n.copy, action: #selector(menuCopyItem))
            addMenuItem(to: menu, title: L10n.copyName, action: #selector(menuCopyName))
            addMenuItem(to: menu, title: L10n.copyPath, action: #selector(menuCopyPath))
            addMenuItem(to: menu, title: L10n.move, action: #selector(menuMoveItem))
            addMenuItem(to: menu, title: L10n.compressToZip, action: #selector(menuCompressItem))
            if item.isDirectory {
                menu.addItem(.separator())
                addMenuItem(to: menu, title: L10n.addToFavorites, action: #selector(menuAddToFavorites))
            }
            menu.addItem(.separator())
            addMenuItem(to: menu, title: L10n.properties, action: #selector(menuPropertiesItem))
            menu.addItem(.separator())

            let trashTitle: String
            let selectedCount = tableView.selectedRowIndexes.count
            if tableView.selectedRowIndexes.contains(row) && selectedCount > 1 {
                trashTitle = L10n.moveItemsToTrash(selectedCount)
            } else {
                trashTitle = L10n.moveToTrash
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

    @objc private func menuShowPackageContents() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        viewModel?.showPackageContents(items[row])
    }

    @objc private func menuRenameItem() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        promptRename(for: items[row])
    }

    // 選択中の行のテキストフィールドは NSTableCellView の選択ハイライトに紛れて編集中か見分けが
    // つかないため、インライン編集ではなくダイアログで新しい名前を入力してもらう
    private func promptRename(for item: FileItem) {
        let alert = NSAlert()
        alert.messageText = L10n.rename
        alert.informativeText = L10n.renamePrompt(name: item.name)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.renameConfirm)
        alert.addButton(withTitle: L10n.cancel)

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        textField.stringValue = item.name
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        guard let window = tableView.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.viewModel?.renameItem(item, to: textField.stringValue)
        }
        DispatchQueue.main.async { textField.selectText(nil) }
    }

    @objc private func menuCopyItem() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        viewModel?.copyItem(items[row])
    }

    @objc private func menuCopyName() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        copyStrings(contextTargets(forClickedRow: row).map(\.name))
    }

    @objc private func menuCopyPath() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        copyStrings(contextTargets(forClickedRow: row).map(\.url.path))
    }

    @objc private func menuMoveItem() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        viewModel?.moveItem(items[row])
    }

    @objc private func menuCompressItem() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        viewModel?.compressToZip(items[row])
    }

    @objc private func menuAddToFavorites() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        onAddToFavorites?(items[row])
    }

    @objc private func menuShareItem() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        let urls = contextTargets(forClickedRow: row).map(\.url)
        let picker = NSSharingServicePicker(items: urls)
        sharingPicker = picker
        picker.show(relativeTo: tableView.rect(ofRow: row), of: tableView, preferredEdge: .maxX)
    }

    @objc private func menuPropertiesItem() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        viewModel?.openFinderInfoWindow(for: items[row])
    }

    @objc private func menuTrashItem() {
        let clickedRow = tableView.clickedRow
        guard clickedRow >= 0, clickedRow < items.count else { return }
        showTrashAlert(for: contextTargets(forClickedRow: clickedRow))
    }

    // 右クリックした行が複数選択の一部ならその全選択、そうでなければ単一行を対象にする
    private func contextTargets(forClickedRow row: Int) -> [FileItem] {
        guard row >= 0, row < items.count else { return [] }
        if tableView.selectedRowIndexes.contains(row) && tableView.selectedRowIndexes.count > 1 {
            return tableView.selectedRowIndexes.compactMap { $0 < items.count ? items[$0] : nil }
        }
        return [items[row]]
    }

}

// MARK: - ResponsiveTableView

final class ResponsiveTableView: NSTableView, QLPreviewPanelDataSource {
    var onSpaceKey:  (() -> Void)?
    var onReturnKey: (() -> Void)?
    var onDeleteKey: (() -> Void)?
    var onCmdUp:     (() -> Void)?
    var onCmdDown:   (() -> Void)?
    var onCopy:      (() -> Void)?
    var onPaste:     (() -> Void)?
    var onCmdShiftN: (() -> Void)?
    var onMiddleClick: ((Int) -> Void)?
    var onUndoRedo:  (() -> Void)?
    var quickLookURL: URL?

    override func otherMouseDown(with event: NSEvent) {
        // buttonNumber 2 = ホイール（中ボタン）
        guard event.buttonNumber == 2 else { return super.otherMouseDown(with: event) }
        onMiddleClick?(row(at: convert(event.locationInWindow, from: nil)))
    }

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

        // ⌘C / ⌘V はここで横取りしない。performKeyEquivalent はフォーカスに関係なくウインドウ内の
        // 全ビューに配られるため、ここで処理するとパス欄や検索欄でのコピー＆ペーストが効かなくなる。
        // 代わりに Edit メニュー経由で first responder に届く copy(_:) / paste(_:) で処理する
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "n" where shift:  onCmdShiftN?(); return true
        default: break
        }

        return super.performKeyEquivalent(with: event)
    }

    @objc func copy(_ sender: Any?) { onCopy?() }
    @objc func paste(_ sender: Any?) { onPaste?() }

    // ⌘Z / ⇧⌘Z も ⌘C / ⌘V と同じく Edit メニュー経由で受け取る。パス欄や検索欄の編集中は
    // そちらが first responder になり、文字入力の取り消しが優先される
    @objc func undo(_ sender: Any?) {
        FileOperations.undoManager.undo()
        onUndoRedo?()
    }

    @objc func redo(_ sender: Any?) {
        FileOperations.undoManager.redo()
        onUndoRedo?()
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        let undoManager = FileOperations.undoManager
        switch item.action {
        case #selector(undo(_:)):
            (item as? NSMenuItem)?.title = undoManager.canUndo
                ? L10n.undoAction(undoManager.undoActionName) : L10n.undo
            return undoManager.canUndo
        case #selector(redo(_:)):
            (item as? NSMenuItem)?.title = undoManager.canRedo
                ? L10n.redoAction(undoManager.redoActionName) : L10n.redo
            return undoManager.canRedo
        case #selector(copy(_:)):
            return !selectedRowIndexes.isEmpty
        case #selector(paste(_:)):
            return NSPasteboard.general.canReadObject(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            )
        default:
            return super.validateUserInterfaceItem(item)
        }
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

final class FileNameCellView: NSTableCellView {
    private let icon = NSImageView()
    private let nameField = NSTextField()

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

    func configure(with item: FileItem) {
        nameField.stringValue = item.name
        let img = NSWorkspace.shared.icon(forFile: item.url.path)
        img.size = NSSize(width: 16, height: 16)
        icon.image = img
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
