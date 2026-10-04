//
//  SidebarView.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/04/20.
//

import SwiftUI
import AppKit

// グループの開閉、グループをまたぐ並べ替え、挿入位置の表示を SwiftUI の List では安定して扱えないため、
// ファイル一覧と同じく AppKit（NSOutlineView）で実装する
struct SidebarView: NSViewRepresentable {
    var viewModel: FileExplorerViewModel
    var favoritesStore: FavoritesStore
    var onOpenInNewTab: ((URL) -> Void)?

    func makeCoordinator() -> SidebarCoordinator { SidebarCoordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSScrollView()
        sv.documentView = context.coordinator.outlineView
        sv.hasVerticalScroller = true
        sv.autohidesScrollers = true
        sv.borderType = .noBorder
        sv.drawsBackground = false
        return sv
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let c = context.coordinator
        c.viewModel = viewModel
        c.store = favoritesStore
        c.onOpenInNewTab = onOpenInNewTab
        // groups と表示言語をここで読むことで、変更時に updateNSView が呼ばれるようにする
        c.reloadIfNeeded(groups: favoritesStore.groups, language: LanguageSettings.shared.language)
    }
}

// MARK: - Coordinator

final class SidebarCoordinator: NSObject {

    // NSOutlineView は項目を参照の同一性で追跡するため、id ごとに同じインスタンスを使い回す
    final class Node: NSObject {
        enum Kind { case group, item }
        let id: UUID
        let kind: Kind
        init(id: UUID, kind: Kind) { self.id = id; self.kind = kind }
    }

    // サイドバー内の並べ替え専用の型。.fileURL を載せないことで、ファイル一覧やお気に入りフォルダへの
    // ファイルのドロップ（移動/コピー）と取り違えないようにする
    static let favoriteDragType = NSPasteboard.PasteboardType("com.vela.favorite-node")

    var viewModel: FileExplorerViewModel?
    var store: FavoritesStore?
    var onOpenInNewTab: ((URL) -> Void)?

    let outlineView = SidebarOutlineView()

    private var groups: [FavoriteGroup] = []
    private var language: AppLanguage?
    private var nodes: [UUID: Node] = [:]
    // reload 中に展開状態を復元すると開閉の通知が飛ぶため、その間は保存しない
    private var isApplyingExpansion = false

    private let columnID = NSUserInterfaceItemIdentifier("favorite")
    private let groupCellID = NSUserInterfaceItemIdentifier("groupCell")
    private let itemCellID = NSUserInterfaceItemIdentifier("itemCell")

    override init() {
        super.init()
        let column = NSTableColumn(identifier: columnID)
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.backgroundColor = .clear
        outlineView.floatsGroupRows = false
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(handleClick)
        outlineView.registerForDraggedTypes([Self.favoriteDragType, .fileURL])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
        outlineView.setDraggingSourceOperationMask([], forLocal: false)

        let menu = NSMenu()
        menu.delegate = self
        outlineView.menu = menu

        outlineView.onMiddleClick = { [weak self] row in
            guard let self, let item = self.favoriteItem(atRow: row) else { return }
            self.onOpenInNewTab?(item.url)
        }
    }

    func reloadIfNeeded(groups newGroups: [FavoriteGroup], language newLanguage: AppLanguage) {
        guard newGroups != groups || newLanguage != language else { return }
        groups = newGroups
        language = newLanguage
        outlineView.reloadData()
        isApplyingExpansion = true
        for group in groups {
            let node = node(for: group.id, kind: .group)
            if group.isExpanded { outlineView.expandItem(node) } else { outlineView.collapseItem(node) }
        }
        isApplyingExpansion = false
    }

    // MARK: Lookup

    private func node(for id: UUID, kind: Node.Kind) -> Node {
        if let node = nodes[id] { return node }
        let node = Node(id: id, kind: kind)
        nodes[id] = node
        return node
    }

    private func group(for node: Node) -> FavoriteGroup? {
        groups.first { $0.id == node.id }
    }

    private func groupIndex(of id: UUID) -> Int? {
        groups.firstIndex { $0.id == id }
    }

    private func favoriteItem(for node: Node) -> FavoriteItem? {
        for group in groups {
            if let item = group.items.first(where: { $0.id == node.id }) { return item }
        }
        return nil
    }

    private func favoriteItem(atRow row: Int) -> FavoriteItem? {
        guard row >= 0, let node = outlineView.item(atRow: row) as? Node, node.kind == .item else { return nil }
        return favoriteItem(for: node)
    }

    // MARK: Actions

    @objc private func handleClick() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? Node else { return }
        switch node.kind {
        case .item:
            guard let item = favoriteItem(for: node) else { return }
            viewModel?.navigate(to: item.url)
        case .group:
            if outlineView.isItemExpanded(node) { outlineView.animator().collapseItem(node) }
            else { outlineView.animator().expandItem(node) }
        }
    }

    @objc private func menuNewGroup() {
        promptGroupName(title: L10n.newGroup, initialName: L10n.newGroupName, confirmTitle: L10n.create) { [weak self] name in
            self?.store?.addGroup(name: name)
        }
    }

    @objc private func menuRenameGroup(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let group = groups.first(where: { $0.id == id }) else { return }
        promptGroupName(title: L10n.renameGroup, initialName: group.displayName, confirmTitle: L10n.renameConfirm) { [weak self] name in
            self?.store?.renameGroup(id: id, to: name)
        }
    }

    @objc private func menuDeleteGroup(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let group = groups.first(where: { $0.id == id }) else { return }
        guard !group.items.isEmpty else {
            store?.removeGroup(id: id)
            return
        }
        let alert = NSAlert()
        alert.messageText = L10n.deleteGroupConfirm(name: group.displayName)
        alert.informativeText = L10n.deleteGroupMessage(count: group.items.count)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.delete)
        alert.addButton(withTitle: L10n.cancel)
        guard let window = outlineView.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.store?.removeGroup(id: id)
        }
    }

    @objc private func menuRestoreDefaults() {
        store?.restoreDefaults()
    }

    @objc private func menuRemoveItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        store?.removeItem(id: id)
    }

    private func promptGroupName(title: String, initialName: String, confirmTitle: String, completion: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = L10n.groupNamePrompt
        alert.alertStyle = .informational
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: L10n.cancel)

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        textField.stringValue = initialName
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        guard let window = outlineView.window else { return }
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            completion(name)
        }
        DispatchQueue.main.async { textField.selectText(nil) }
    }

    // MARK: Cells

    private func makeGroupCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = groupCellID
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func makeItemCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = itemCellID
        let imageView = NSImageView()
        imageView.contentTintColor = .controlAccentColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(imageView)
        cell.addSubview(label)
        cell.imageView = imageView
        cell.textField = label
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

// MARK: - NSOutlineViewDataSource

extension SidebarCoordinator: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? Node else { return groups.count }
        return node.kind == .group ? (group(for: node)?.items.count ?? 0) : 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? Node, let group = group(for: node) else {
            return self.node(for: groups[index].id, kind: .group)
        }
        return self.node(for: group.items[index].id, kind: .item)
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? Node)?.kind == .group
    }

    // MARK: Drag & Drop

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let node = item as? Node else { return nil }
        let pbItem = NSPasteboardItem()
        pbItem.setString(node.id.uuidString, forType: Self.favoriteDragType)
        return pbItem
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo,
                     proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        if let dragged = draggedNode(from: info) {
            return validateReorder(dragged, proposedItem: item as? Node, proposedChildIndex: index)
        }
        // ファイル一覧などからのファイルは、お気に入りのフォルダの上にドロップしたときだけ移動/コピーする
        guard let target = item as? Node, target.kind == .item,
              index == NSOutlineViewDropOnItemIndex else { return [] }
        return NSEvent.modifierFlags.contains(.option) ? .copy : .move
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo,
                     item: Any?, childIndex index: Int) -> Bool {
        if let dragged = draggedNode(from: info) {
            switch dragged.kind {
            case .item:
                guard let target = item as? Node, target.kind == .group else { return false }
                store?.moveItem(id: dragged.id, toGroup: target.id, at: index)
            case .group:
                store?.moveGroup(id: dragged.id, to: index)
            }
            return true
        }

        guard let target = item as? Node, let destItem = favoriteItem(for: target),
              let urls = info.draggingPasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return false }
        let isCopy = NSEvent.modifierFlags.contains(.option)
        if isCopy { viewModel?.copyURLs(urls, to: destItem.url) }
        else      { viewModel?.moveURLs(urls, to: destItem.url) }
        return true
    }

    private func draggedNode(from info: NSDraggingInfo) -> Node? {
        guard (info.draggingSource as? NSOutlineView) === outlineView,
              let idString = info.draggingPasteboard.string(forType: Self.favoriteDragType),
              let id = UUID(uuidString: idString) else { return nil }
        return nodes[id]
    }

    private func validateReorder(_ dragged: Node, proposedItem target: Node?, proposedChildIndex index: Int) -> NSDragOperation {
        switch dragged.kind {
        case .item:
            guard let target else { return [] }
            switch target.kind {
            case .group where index == NSOutlineViewDropOnItemIndex:
                // 見出しの上に落としたらそのグループの末尾へ
                let count = group(for: target)?.items.count ?? 0
                outlineView.setDropItem(target, dropChildIndex: count)
            case .group:
                break
            case .item:
                // 項目の上に落としたらその項目の直後へ
                guard let parent = outlineView.parent(forItem: target) as? Node else { return [] }
                outlineView.setDropItem(parent, dropChildIndex: outlineView.childIndex(forItem: target) + 1)
            }
            return .move

        case .group:
            // グループはトップレベルの並びの中でだけ動かす
            if target == nil, index != NSOutlineViewDropOnItemIndex { return .move }
            guard let target, target.kind == .group, let groupIndex = groupIndex(of: target.id) else { return [] }
            outlineView.setDropItem(nil, dropChildIndex: groupIndex)
            return .move
        }
    }
}

// MARK: - NSOutlineViewDelegate

extension SidebarCoordinator: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as? Node)?.kind == .group
    }

    // クリックは handleClick で移動に使い、選択状態は持たない（移動後に古いハイライトが残らないように）
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { false }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }
        switch node.kind {
        case .group:
            let cell = outlineView.makeView(withIdentifier: groupCellID, owner: nil) as? NSTableCellView ?? makeGroupCell()
            cell.textField?.stringValue = group(for: node)?.displayName ?? ""
            return cell
        case .item:
            let cell = outlineView.makeView(withIdentifier: itemCellID, owner: nil) as? NSTableCellView ?? makeItemCell()
            let favorite = favoriteItem(for: node)
            cell.textField?.stringValue = favorite?.displayName ?? ""
            cell.imageView?.image = favorite.flatMap {
                NSImage(systemSymbolName: $0.systemImage, accessibilityDescription: nil)
            }
            return cell
        }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        saveExpansion(notification, expanded: true)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        saveExpansion(notification, expanded: false)
    }

    private func saveExpansion(_ notification: Notification, expanded: Bool) {
        guard !isApplyingExpansion,
              let node = notification.userInfo?["NSObject"] as? Node, node.kind == .group,
              let store else { return }
        store.setExpanded(expanded, groupID: node.id)
        // 開閉は画面に反映済みなので、続く updateNSView で作り直さないよう手元の状態も合わせる
        groups = store.groups
    }
}

// MARK: - Context Menu

extension SidebarCoordinator: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = outlineView.clickedRow
        if row >= 0, let node = outlineView.item(atRow: row) as? Node {
            switch node.kind {
            case .item:
                addMenuItem(to: menu, title: L10n.remove, action: #selector(menuRemoveItem(_:)), id: node.id)
            case .group:
                addMenuItem(to: menu, title: L10n.renameGroup, action: #selector(menuRenameGroup(_:)), id: node.id)
                let delete = addMenuItem(to: menu, title: L10n.deleteGroup, action: #selector(menuDeleteGroup(_:)), id: node.id)
                if store?.canRemoveGroup != true {
                    delete.action = nil
                }
            }
            menu.addItem(.separator())
        }
        addMenuItem(to: menu, title: L10n.newGroup, action: #selector(menuNewGroup), id: nil)
        let restore = addMenuItem(to: menu, title: L10n.restoreDefaultFavorites, action: #selector(menuRestoreDefaults), id: nil)
        if store?.missingDefaults.isEmpty != false {
            restore.action = nil
        }
    }

    @discardableResult
    private func addMenuItem(to menu: NSMenu, title: String, action: Selector, id: UUID?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = id
        menu.addItem(item)
        return item
    }
}

// MARK: - SidebarOutlineView

final class SidebarOutlineView: NSOutlineView {
    var onMiddleClick: ((Int) -> Void)?

    override func otherMouseDown(with event: NSEvent) {
        // buttonNumber 2 = ホイール（中ボタン）
        guard event.buttonNumber == 2 else { return super.otherMouseDown(with: event) }
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return }
        onMiddleClick?(row)
    }
}
