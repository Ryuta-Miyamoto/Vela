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
        c.reloadIfNeeded(groups: favoritesStore.groups,
                         volumes: VolumesStore.shared.volumes,
                         language: LanguageSettings.shared.language)
    }
}

// MARK: - Coordinator

final class SidebarCoordinator: NSObject {

    // NSOutlineView は項目を参照の同一性で追跡するため、id ごとに同じインスタンスを使い回す
    final class Node: NSObject {
        // volumesHeader / volume make up the Locations section below the favorite groups
        enum Kind { case group, item, volumesHeader, volume }
        let id: UUID
        let kind: Kind
        init(id: UUID, kind: Kind) { self.id = id; self.kind = kind }

        var isHeader: Bool { kind == .group || kind == .volumesHeader }
    }

    // サイドバー内の並べ替え専用の型。.fileURL を載せないことで、ファイル一覧やお気に入りフォルダへの
    // ファイルのドロップ（移動/コピー）と取り違えないようにする
    static let favoriteDragType = NSPasteboard.PasteboardType("com.vela.favorite-node")

    var viewModel: FileExplorerViewModel?
    var store: FavoritesStore?
    var onOpenInNewTab: ((URL) -> Void)?

    let outlineView = SidebarOutlineView()

    private var groups: [FavoriteGroup] = []
    private var volumes: [VolumeItem] = []
    private var language: AppLanguage?
    private var nodes: [UUID: Node] = [:]
    private let volumesHeaderNode = Node(id: UUID(), kind: .volumesHeader)
    // Volumes have no UUID of their own, so each mount point gets a stable node
    private var volumeNodes: [URL: Node] = [:]
    // reload 中に展開状態を復元すると開閉の通知が飛ぶため、その間は保存しない
    private var isApplyingExpansion = false

    private static let volumesExpandedKey = "Vela.sidebar.volumesExpanded"

    private let columnID = NSUserInterfaceItemIdentifier("favorite")
    private let groupCellID = NSUserInterfaceItemIdentifier("groupCell")
    private let itemCellID = NSUserInterfaceItemIdentifier("itemCell")
    private let volumeCellID = NSUserInterfaceItemIdentifier("volumeCell")

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
            guard let self, let url = self.folderURL(atRow: row) else { return }
            self.onOpenInNewTab?(url)
        }
    }

    func reloadIfNeeded(groups newGroups: [FavoriteGroup], volumes newVolumes: [VolumeItem], language newLanguage: AppLanguage) {
        guard newGroups != groups || newVolumes != volumes || newLanguage != language else { return }
        groups = newGroups
        volumes = newVolumes
        language = newLanguage
        volumeNodes = volumeNodes.filter { url, _ in volumes.contains { $0.url == url } }
        outlineView.reloadData()
        isApplyingExpansion = true
        for group in groups {
            let node = node(for: group.id, kind: .group)
            if group.isExpanded { outlineView.expandItem(node) } else { outlineView.collapseItem(node) }
        }
        let volumesExpanded = UserDefaults.standard.object(forKey: Self.volumesExpandedKey) as? Bool ?? true
        if volumesExpanded { outlineView.expandItem(volumesHeaderNode) } else { outlineView.collapseItem(volumesHeaderNode) }
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

    private func volumeNode(for volume: VolumeItem) -> Node {
        if let node = volumeNodes[volume.url] { return node }
        let node = Node(id: UUID(), kind: .volume)
        volumeNodes[volume.url] = node
        return node
    }

    private func volume(for node: Node) -> VolumeItem? {
        guard let url = volumeNodes.first(where: { $0.value === node })?.key else { return nil }
        return volumes.first { $0.url == url }
    }

    // The folder a favorite or volume row points to (headers have none)
    private func folderURL(for node: Node) -> URL? {
        switch node.kind {
        case .item:   return favoriteItem(for: node)?.url
        case .volume: return volume(for: node)?.url
        case .group, .volumesHeader: return nil
        }
    }

    private func folderURL(atRow row: Int) -> URL? {
        guard row >= 0, let node = outlineView.item(atRow: row) as? Node else { return nil }
        return folderURL(for: node)
    }

    // MARK: Actions

    @objc private func handleClick() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? Node else { return }
        if node.isHeader {
            if outlineView.isItemExpanded(node) { outlineView.animator().collapseItem(node) }
            else { outlineView.animator().expandItem(node) }
        } else if let url = folderURL(for: node) {
            viewModel?.navigate(to: url)
        }
    }

    @objc private func menuEject(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL,
              let volume = volumes.first(where: { $0.url == url }) else { return }
        VolumesStore.shared.eject(volume)
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

// MARK: - VolumeCellView

// A volume row: icon, name and an eject button on the right (hidden for disks that can't be ejected)
final class VolumeCellView: NSTableCellView {
    var onEject: (() -> Void)?
    private let ejectButton = NSButton()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        let imageView = NSImageView()
        imageView.contentTintColor = .controlAccentColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        ejectButton.image = NSImage(systemSymbolName: "eject.fill", accessibilityDescription: L10n.eject)
        ejectButton.isBordered = false
        ejectButton.contentTintColor = .secondaryLabelColor
        ejectButton.target = self
        ejectButton.action = #selector(eject)
        ejectButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(imageView)
        addSubview(label)
        addSubview(ejectButton)
        self.imageView = imageView
        textField = label
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(lessThanOrEqualTo: ejectButton.leadingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            ejectButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            ejectButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            ejectButton.widthAnchor.constraint(equalToConstant: 16),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(with volume: VolumeItem) {
        textField?.stringValue = volume.name
        imageView?.image = NSImage(systemSymbolName: volume.systemImage, accessibilityDescription: nil)
        ejectButton.isHidden = !volume.isEjectable
        ejectButton.toolTip = L10n.eject
    }

    @objc private func eject() { onEject?() }
}

// MARK: - NSOutlineViewDataSource

extension SidebarCoordinator: NSOutlineViewDataSource {

    // Top level: the favorite groups, then the Locations header
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? Node else { return groups.count + 1 }
        switch node.kind {
        case .group:         return group(for: node)?.items.count ?? 0
        case .volumesHeader: return volumes.count
        case .item, .volume: return 0
        }
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? Node else {
            return index < groups.count ? self.node(for: groups[index].id, kind: .group) : volumesHeaderNode
        }
        if node.kind == .volumesHeader { return volumeNode(for: volumes[index]) }
        guard let group = group(for: node) else { return volumesHeaderNode }
        return self.node(for: group.items[index].id, kind: .item)
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? Node)?.isHeader == true
    }

    // MARK: Drag & Drop

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        // The Locations section follows the mounted volumes and can't be rearranged
        guard let node = item as? Node, node.kind == .group || node.kind == .item else { return nil }
        let pbItem = NSPasteboardItem()
        pbItem.setString(node.id.uuidString, forType: Self.favoriteDragType)
        return pbItem
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo,
                     proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        if let dragged = draggedNode(from: info) {
            return validateReorder(dragged, proposedItem: item as? Node, proposedChildIndex: index)
        }
        // ファイル一覧などからのファイルは、お気に入りのフォルダ（またはボリューム）の上にドロップしたときだけ移動/コピーする
        guard let target = item as? Node, folderURL(for: target) != nil,
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
            case .volumesHeader, .volume:
                return false
            }
            return true
        }

        guard let target = item as? Node, let destURL = folderURL(for: target),
              let urls = info.draggingPasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return false }
        let isCopy = NSEvent.modifierFlags.contains(.option)
        if isCopy { viewModel?.copyURLs(urls, to: destURL) }
        else      { viewModel?.moveURLs(urls, to: destURL) }
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
            case .volumesHeader, .volume:
                return []
            }
            return .move

        case .group:
            // グループはトップレベルの並びの中でだけ動かす（Locations より下には置かない）
            if target == nil, index != NSOutlineViewDropOnItemIndex {
                if index > groups.count { outlineView.setDropItem(nil, dropChildIndex: groups.count) }
                return .move
            }
            guard let target, target.kind == .group, let groupIndex = groupIndex(of: target.id) else { return [] }
            outlineView.setDropItem(nil, dropChildIndex: groupIndex)
            return .move

        case .volumesHeader, .volume:
            return []
        }
    }
}

// MARK: - NSOutlineViewDelegate

extension SidebarCoordinator: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as? Node)?.isHeader == true
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
        case .volumesHeader:
            let cell = outlineView.makeView(withIdentifier: groupCellID, owner: nil) as? NSTableCellView ?? makeGroupCell()
            cell.textField?.stringValue = L10n.locations
            return cell
        case .volume:
            let cell = outlineView.makeView(withIdentifier: volumeCellID, owner: nil) as? VolumeCellView
                ?? VolumeCellView(identifier: volumeCellID)
            guard let volume = volume(for: node) else { return cell }
            cell.configure(with: volume)
            cell.onEject = { VolumesStore.shared.eject(volume) }
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
        guard !isApplyingExpansion, let node = notification.userInfo?["NSObject"] as? Node else { return }
        if node.kind == .volumesHeader {
            UserDefaults.standard.set(expanded, forKey: Self.volumesExpandedKey)
            return
        }
        guard node.kind == .group, let store else { return }
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
            case .volume:
                if let volume = volume(for: node), volume.isEjectable {
                    let eject = addMenuItem(to: menu, title: L10n.ejectVolume(name: volume.name), action: #selector(menuEject(_:)), id: nil)
                    eject.representedObject = volume.url
                }
            case .volumesHeader:
                break
            }
            if menu.numberOfItems > 0 { menu.addItem(.separator()) }
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
