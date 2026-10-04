//
//  ContentView.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/04/20.
//

import SwiftUI
import AppKit
import Combine

@Observable
final class FileExplorerViewModel {
    let id = UUID()
    var currentURL: URL {
        didSet { startWatching() }
    }
    var items: [FileItem] = []
    var searchText: String = "" {
        didSet { if searchText != oldValue { scheduleSearch() } }
    }
    var selectedItems: [FileItem] = []

    // Results of a search that includes subfolders (a search in the current folder just filters items)
    private(set) var searchResults: [FileItem] = []
    private(set) var isSearching = false
    private(set) var searchReachedLimit = false

    private var backStack: [URL] = []
    private var forwardStack: [URL] = []
    // 他のアプリでの変更も一覧に反映するため、表示中のディレクトリを監視する（背面のタブも含む）
    @ObservationIgnored private var watcher: DirectoryWatcher?
    @ObservationIgnored private var search: SubfolderSearch?
    @ObservationIgnored private var searchDebounce: DispatchWorkItem?

    var trimmedSearchText: String { searchText.trimmingCharacters(in: .whitespaces) }
    var isSubfolderSearchActive: Bool {
        FileDisplaySettings.shared.searchIncludesSubfolders && !trimmedSearchText.isEmpty
    }

    var canGoBack: Bool    { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool      { currentURL.pathComponents.count > 1 }
    var tabTitle: String   { currentURL.lastPathComponent.isEmpty ? "/" : currentURL.lastPathComponent }

    init(url: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.currentURL = url
        reload()
        startWatching()
    }

    private func startWatching() {
        watcher = DirectoryWatcher(url: currentURL) { [weak self] in self?.reload() }
    }

    func navigate(to url: URL) {
        searchText = ""
        backStack.append(currentURL)
        forwardStack.removeAll()
        currentURL = url
        reload()
    }

    func goBack() {
        guard let prev = backStack.popLast() else { return }
        searchText = ""
        forwardStack.append(currentURL)
        currentURL = prev
        reload()
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        searchText = ""
        backStack.append(currentURL)
        currentURL = next
        reload()
    }

    func goUp() {
        let parent = currentURL.deletingLastPathComponent()
        guard parent != currentURL else { return }
        navigate(to: parent)
    }

    // Goes home if the current folder is on the given (unmounted) volume
    func leaveIfInside(_ volumeURL: URL) {
        let volumePath = volumeURL.standardizedFileURL.path
        let path = currentURL.standardizedFileURL.path
        guard path == volumePath || path.hasPrefix(volumePath + "/") else { return }
        navigate(to: FileManager.default.homeDirectoryForCurrentUser)
    }

    deinit { search?.cancel() }

    func reload() {
        items = FileService.shared.contents(of: currentURL, includeHidden: FileDisplaySettings.shared.showHiddenFiles)
        // Re-running a deep search on every change would be too slow, so only drop results that are gone
        // (trashed, moved away)
        if !searchResults.isEmpty {
            let remaining = searchResults.filter { FileManager.default.fileExists(atPath: $0.url.path) }
            if remaining.count != searchResults.count { searchResults = remaining }
        }
    }

    // MARK: - Subfolder Search

    // Restarts the search, e.g. after the scope or the hidden files setting changed
    func refreshSearch() {
        searchDebounce?.cancel()
        startSearch()
    }

    private func scheduleSearch() {
        searchDebounce?.cancel()
        guard isSubfolderSearchActive else { return startSearch() }
        // Wait until typing pauses so every keystroke doesn't start a new walk of the folder tree
        let work = DispatchWorkItem { [weak self] in self?.startSearch() }
        searchDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func startSearch() {
        search?.cancel()
        search = nil
        searchResults = []
        searchReachedLimit = false
        guard isSubfolderSearchActive else {
            isSearching = false
            return
        }
        isSearching = true
        let task = SubfolderSearch()
        search = task
        task.start(root: currentURL, query: trimmedSearchText,
                   includeHidden: FileDisplaySettings.shared.showHiddenFiles,
                   onBatch: { [weak self] batch in
                       guard let self, self.search === task else { return }
                       self.searchResults.append(contentsOf: batch)
                   },
                   onFinish: { [weak self] reachedLimit in
                       guard let self, self.search === task else { return }
                       self.isSearching = false
                       self.searchReachedLimit = reachedLimit
                       self.search = nil
                   })
    }

    // MARK: - File Operations

    func openItem(_ item: FileItem) {
        // .app などのパッケージはディレクトリでもダブルクリックで起動する（Finder と同じ挙動）
        if item.isDirectory && !item.isPackage { navigate(to: item.url) } else { NSWorkspace.shared.open(item.url) }
    }

    // パッケージの中身をファイルブラウザとして開く（右クリック「パッケージの内容を表示」用）
    func showPackageContents(_ item: FileItem) {
        navigate(to: item.url)
    }

    // 右クリック「プロパティ」用：自前のダイアログではなく Finder 本物の「情報を見る」ウインドウを開く。
    // Finder への Apple Event 送信となるため、初回は Automation の許可が必要（Info.plist に説明文を用意済み）。
    func openFinderInfoWindow(for item: FileItem) {
        let escapedPath = item.url.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Finder"
            activate
            open information window of (POSIX file "\(escapedPath)" as alias)
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            NSLog("Failed to open Finder info window: \(error)")
        }
    }

    // 右クリック「ZIPに圧縮」用：Finderの「圧縮」と同じくditto(-c -k)でzipを作成する。
    // zip/unzipコマンドよりHFS+のメタデータ（リソースフォーク等）を正しく保持できる。
    func compressToZip(_ item: FileItem) {
        let parentDir = item.url.deletingLastPathComponent()
        let baseName = item.url.lastPathComponent
        var destURL = parentDir.appendingPathComponent("\(baseName).zip")
        var counter = 2
        while FileManager.default.fileExists(atPath: destURL.path) {
            destURL = parentDir.appendingPathComponent("\(baseName) \(counter).zip")
            counter += 1
        }

        let process = Process()
        process.currentDirectoryURL = parentDir
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", baseName, destURL.path]
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                if proc.terminationStatus == 0 {
                    FileOperations.registerCreation(of: destURL, actionName: L10n.compressToZip)
                } else {
                    NSLog("ZIP compression failed (exit code: \(proc.terminationStatus))")
                }
                self?.reload()
            }
        }
        do {
            try process.run()
        } catch {
            NSLog("Failed to start ZIP compression: \(error)")
        }
    }

    func renameItem(_ item: FileItem, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != item.name else { return }
        let dest = item.url.deletingLastPathComponent().appendingPathComponent(trimmed)
        do {
            try FileOperations.move(from: item.url, to: dest, actionName: L10n.rename)
            // Keep a renamed search result in the list under its new name
            if let index = searchResults.firstIndex(of: item), let renamed = FileService.item(at: dest) {
                searchResults[index] = renamed
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L10n.renameFailed
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
        reload()
    }

    func copyItems(_ items: [FileItem]) {
        guard !items.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(items.map { $0.url as NSURL })
    }

    // Finder の ⌘D と同じく、同じフォルダに「<名前> copy」を作る
    func duplicateItems(_ items: [FileItem]) {
        let requests = items.map {
            FileOperationQueue.Request(source: $0.url,
                                       destinationFolder: $0.url.deletingLastPathComponent(),
                                       nameRule: .uniqueCopy(suffix: L10n.copySuffix))
        }
        FileOperationQueue.shared.enqueue(.copy, requests, actionName: L10n.duplicate) { [weak self] in self?.reload() }
    }

    // Finder と同じく、拡張子も含めた名前の後ろに「alias」を付ける（例: "Report.pdf alias"）
    func makeAliases(for items: [FileItem]) {
        for item in items {
            let dest = FileOperations.uniqueURL(in: item.url.deletingLastPathComponent(),
                                                baseName: item.name, pathExtension: "",
                                                suffix: L10n.aliasSuffix)
            do {
                try FileOperations.makeAlias(of: item.url, at: dest)
            } catch {
                NSLog("Failed to make alias: \(error)")
            }
        }
        reload()
    }

    func openInTerminal(_ url: URL) {
        guard let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        // フォルダを Terminal で開くと、そのフォルダをカレントディレクトリにした新しいウインドウが開く
        NSWorkspace.shared.open([url], withApplicationAt: terminalURL, configuration: NSWorkspace.OpenConfiguration())
    }

    // URL は末尾の "/" の有無で == が一致しないことがあるため、パスで比べる
    private static func isParent(_ folder: URL, of url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL.path == folder.standardizedFileURL.path
    }

    func moveItem(_ item: FileItem) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L10n.moveHere
        panel.message = L10n.chooseMoveDestination(name: item.name)
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        moveURLs([item.url], to: dest)
    }

    func trashItem(_ item: FileItem) {
        try? FileOperations.trash(item.url)
        reload()
    }

    func createFolder() {
        let baseName = L10n.newFolder
        var name = baseName
        var counter = 2
        var newURL = currentURL.appendingPathComponent(name)
        while FileManager.default.fileExists(atPath: newURL.path) {
            name = "\(baseName) \(counter)"
            newURL = currentURL.appendingPathComponent(name)
            counter += 1
        }
        try? FileOperations.createDirectory(at: newURL)
        reload()
    }

    // Copies and moves run in the background (FileOperationQueue); the list reloads when the job ends
    func moveURLs(_ sources: [URL], to destFolder: URL) {
        let requests = sources
            .filter {
                $0 != destFolder && !Self.isParent(destFolder, of: $0) && !destFolder.path.hasPrefix($0.path + "/")
            }
            .map { FileOperationQueue.Request(source: $0, destinationFolder: destFolder, nameRule: .keep) }
        FileOperationQueue.shared.enqueue(.move, requests, actionName: L10n.move) { [weak self] in self?.reload() }
    }

    func copyURLs(_ sources: [URL], to destFolder: URL) {
        let requests = sources
            .filter { $0 != destFolder && !destFolder.path.hasPrefix($0.path + "/") }
            .map {
                // 同じフォルダへのペーストは名前がぶつかるので、Finder と同じく複製として扱う
                FileOperationQueue.Request(source: $0, destinationFolder: destFolder,
                                           nameRule: Self.isParent(destFolder, of: $0) ? .uniqueCopy(suffix: L10n.copySuffix) : .keep)
            }
        FileOperationQueue.shared.enqueue(.copy, requests, actionName: L10n.copy) { [weak self] in self?.reload() }
    }
}

// MARK: - Pane State (Tab Management)

// The tabs of one file list pane. A window has one pane, or two side by side in dual pane mode
@Observable
final class PaneState {
    let id = UUID()
    var tabs: [FileExplorerViewModel]
    var selectedIndex: Int

    var currentTab: FileExplorerViewModel { tabs[selectedIndex] }

    init(tabs: [FileExplorerViewModel], selectedIndex: Int) {
        self.tabs = tabs
        self.selectedIndex = tabs.indices.contains(selectedIndex) ? selectedIndex : 0
    }

    convenience init(url: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(tabs: [FileExplorerViewModel(url: url)], selectedIndex: 0)
    }

    func addTab() {
        tabs.append(FileExplorerViewModel())
        selectedIndex = tabs.count - 1
    }

    // ホイールクリック用。ブラウザのバックグラウンドタブと同様に、表示中のタブは切り替えずに末尾へ追加する
    func openInNewTab(_ url: URL) {
        tabs.append(FileExplorerViewModel(url: url))
    }

    // 端まで来たら反対側へ回り込む（Finder / Safari と同じ挙動）
    func selectNextTab() {
        selectedIndex = (selectedIndex + 1) % tabs.count
    }

    func selectPreviousTab() {
        selectedIndex = (selectedIndex - 1 + tabs.count) % tabs.count
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectedIndex = index
    }

    // タブの並べ替え。destination は移動後の配列でのインデックス。選択中のタブは移動後も選択したままにする
    func moveTab(from source: Int, to destination: Int) {
        guard tabs.indices.contains(source), tabs.indices.contains(destination), source != destination else { return }
        let selectedID = currentTab.id
        let tab = tabs.remove(at: source)
        tabs.insert(tab, at: destination)
        selectedIndex = tabs.firstIndex { $0.id == selectedID } ?? 0
    }

    // Removes a tab when it isn't the last one. Closing the last tab is decided by AppState
    func removeTab(at index: Int) {
        guard tabs.count > 1, tabs.indices.contains(index) else { return }
        tabs.remove(at: index)
        if selectedIndex > index {
            selectedIndex -= 1
        } else if selectedIndex >= tabs.count {
            selectedIndex = tabs.count - 1
        }
    }
}

// MARK: - App State

@Observable
final class AppState {
    // panes[0] is the left pane and panes[1] the right one. The second pane is created the first time dual
    // pane mode is turned on and kept (hidden) when it's turned off, so turning it back on restores its tabs
    private(set) var panes: [PaneState]
    private(set) var activePaneIndex: Int
    private(set) var isDualPane: Bool

    // The toolbar, sidebar, status bar and menu commands act on the active pane
    var activePane: PaneState { panes[activePaneIndex] }
    var currentTab: FileExplorerViewModel { activePane.currentTab }
    var allTabs: [FileExplorerViewModel] { panes.flatMap(\.tabs) }

    // 前回終了時のタブを復元するのは起動直後の最初のウインドウだけ。⌘N で開く追加のウインドウはホームから始める
    private static var hasRestoredSession = false

    init() {
        let restored = Self.hasRestoredSession ? nil : SavedSession.load()
        Self.hasRestoredSession = true
        let first = restored.flatMap { Self.restorePane(paths: $0.paths, selectedIndex: $0.selectedIndex) }
        let second = restored.flatMap { session in
            session.secondPanePaths.flatMap { Self.restorePane(paths: $0, selectedIndex: session.secondPaneSelectedIndex ?? 0) }
        }
        var restoredPanes = [first, second].compactMap { $0 }
        if restoredPanes.isEmpty { restoredPanes = [PaneState()] }
        panes = restoredPanes
        isDualPane = restoredPanes.count == 2 && restored?.isDualPane == true
        activePaneIndex = max(0, min(restored?.activePaneIndex ?? 0, restoredPanes.count - 1))
    }

    // 前回から消えた・移動されたフォルダのタブは開かない
    private static func restorePane(paths: [String], selectedIndex: Int) -> PaneState? {
        let urls = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { url in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            }
        guard !urls.isEmpty else { return nil }
        let selectedPath = paths.indices.contains(selectedIndex) ? paths[selectedIndex] : nil
        return PaneState(tabs: urls.map { FileExplorerViewModel(url: $0) },
                         selectedIndex: urls.firstIndex { $0.path == selectedPath } ?? 0)
    }

    // 保存対象（ペインごとのタブの表示中フォルダと選択中のタブ、2ペイン表示の状態）。ContentView が変化を監視して保存する
    var session: SavedSession {
        let second = panes.count > 1 ? panes[1] : nil
        return SavedSession(paths: panes[0].tabs.map(\.currentURL.path),
                            selectedIndex: panes[0].selectedIndex,
                            secondPanePaths: second?.tabs.map(\.currentURL.path),
                            secondPaneSelectedIndex: second?.selectedIndex,
                            isDualPane: isDualPane,
                            activePaneIndex: activePaneIndex)
    }

    // MARK: Tabs of the active pane (menu commands and shortcuts)

    func addTab() { activePane.addTab() }
    func openInNewTab(_ url: URL) { activePane.openInNewTab(url) }
    func selectNextTab() { activePane.selectNextTab() }
    func selectPreviousTab() { activePane.selectPreviousTab() }
    func selectTab(at index: Int) { activePane.selectTab(at: index) }
    func closeCurrentTab() { closeTab(at: activePane.selectedIndex, in: activePane) }

    func closeTab(at index: Int, in pane: PaneState) {
        if pane.tabs.count > 1 {
            pane.removeTab(at: index)
            return
        }
        // Closing the last tab of one of two panes closes that pane
        if isDualPane, let paneIndex = panes.firstIndex(where: { $0 === pane }) {
            panes.remove(at: paneIndex)
            activePaneIndex = 0
            isDualPane = false
            return
        }
        // 残り1タブを閉じるのはウインドウを閉じる操作に相当するため、アプリを終了する
        NSApplication.shared.terminate(nil)
    }

    // MARK: Dual Pane

    func toggleDualPane() {
        if isDualPane {
            // Keep showing the pane that was being used
            isDualPane = false
            return
        }
        if panes.count < 2 {
            panes.append(PaneState(url: currentTab.currentURL))
        }
        isDualPane = true
    }

    // The pane across from the given one, while both are shown
    func otherPane(of pane: PaneState) -> PaneState? {
        guard isDualPane else { return nil }
        return panes.first { $0 !== pane }
    }

    func activate(_ pane: PaneState) {
        guard let index = panes.firstIndex(where: { $0 === pane }), index != activePaneIndex else { return }
        activePaneIndex = index
    }

    func activateOtherPane() {
        guard isDualPane else { return }
        activePaneIndex = 1 - activePaneIndex
    }

    func showSameFolderInOtherPane() {
        guard let other = otherPane(of: activePane) else { return }
        let url = currentTab.currentURL
        guard other.currentTab.currentURL != url else { return }
        other.currentTab.navigate(to: url)
    }

    // The active pane stays active after moving to the other side
    func swapPanes() {
        guard isDualPane, panes.count == 2 else { return }
        panes.swapAt(0, 1)
        activePaneIndex = 1 - activePaneIndex
    }
}

// MARK: - Session (Tab Restoration)

// ウインドウが複数あるときは、最後に操作したウインドウのタブが保存される
struct SavedSession: Codable, Equatable {
    private static let udKey = "Vela.session.v1"

    // The first (left) pane
    var paths: [String]
    var selectedIndex: Int
    // Added with dual pane mode. Optional so that sessions saved by earlier versions still load
    var secondPanePaths: [String]?
    var secondPaneSelectedIndex: Int?
    var isDualPane: Bool?
    var activePaneIndex: Int?

    static func load() -> SavedSession? {
        guard let data = UserDefaults.standard.data(forKey: udKey) else { return nil }
        return try? JSONDecoder().decode(SavedSession.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.udKey)
    }
}

// MARK: - Content View

struct ContentView: View {
    @State private var appState = AppState()
    @State private var favoritesStore = FavoritesStore()

    var body: some View {
        VStack(spacing: 0) {
            // In dual pane mode each pane has its own tab bar and address bar instead
            if !appState.isDualPane {
                TabBarView(pane: appState.activePane,
                           onClose: { appState.closeTab(at: $0, in: appState.activePane) })
            }
            ToolbarView(viewModel: appState.currentTab,
                        showsAddressBar: !appState.isDualPane,
                        isDualPane: appState.isDualPane,
                        onToggleDualPane: { appState.toggleDualPane() })
            Divider()
            NavigationSplitView {
                SidebarView(
                    viewModel: appState.currentTab,
                    favoritesStore: favoritesStore,
                    onOpenInNewTab: { appState.openInNewTab($0) }
                )
                    .navigationSplitViewColumnWidth(min: 150, ideal: 200)
            } detail: {
                if appState.isDualPane {
                    DualPaneView(appState: appState, favoritesStore: favoritesStore)
                } else {
                    PaneFileList(appState: appState, pane: appState.activePane, favoritesStore: favoritesStore)
                }
            }
            StatusBarView(viewModel: appState.currentTab)
        }
        .background { tabShortcuts }
        .onChange(of: appState.session) { _, session in session.save() }
        // 隠しファイルの表示設定は全タブ共通のため、背面のタブも含めて読み込み直す
        .onChange(of: FileDisplaySettings.shared.showHiddenFiles) { _, _ in
            appState.allTabs.forEach {
                $0.reload()
                if $0.isSubfolderSearchActive { $0.refreshSearch() }
            }
        }
        // The search scope is shared too; tabs with a query switch between filtering and searching subfolders
        .onChange(of: FileDisplaySettings.shared.searchIncludesSubfolders) { _, _ in
            appState.allTabs.forEach { $0.refreshSearch() }
        }
        // A tab showing a folder on a volume that was just ejected would be left on a missing folder
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { notification in
            guard let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            appState.allTabs.forEach { $0.leaveIfInside(volumeURL) }
        }
        .frame(minWidth: 800, minHeight: 520)
        .navigationTitle(appState.currentTab.tabTitle)
        // ⌘T / ⌘W のメニューコマンド（VelaApp の TabCommands）から参照する
        .focusedSceneValue(\.appState, appState)
    }

    // メニューに並べると冗長になる補助ショートカット（Safari と同じ割り当て）。
    // ⌘⇧[ / ⌘⇧] で前後のタブ、⌘1〜⌘8 で n 番目のタブ、⌘9 で最後のタブへ移動する（2ペイン表示ではアクティブなペインのタブ）
    private var tabShortcuts: some View {
        Group {
            Button("") { appState.selectPreviousTab() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Button("") { appState.selectNextTab() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            ForEach(1..<9) { number in
                Button("") { appState.selectTab(at: number - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
            }
            Button("") { appState.selectTab(at: appState.activePane.tabs.count - 1) }
                .keyboardShortcut("9", modifiers: .command)
        }
        .hidden()
    }
}

// MARK: - Panes

// The file list of a pane's current tab
private struct PaneFileList: View {
    var appState: AppState
    var pane: PaneState
    var favoritesStore: FavoritesStore

    var body: some View {
        let isDualPane = appState.isDualPane
        FileListView(
            viewModel: pane.currentTab,
            favoriteGroups: { favoritesStore.groups },
            onAddToFavorites: { item, groupID in
                favoritesStore.add(name: item.name, url: item.url, toGroup: groupID)
            },
            onOpenInNewTab: { pane.openInNewTab($0) },
            isActivePane: appState.activePane === pane,
            otherPaneURL: appState.otherPane(of: pane)?.currentTab.currentURL,
            onActivate: isDualPane ? { appState.activate(pane) } : nil,
            onSwitchPane: isDualPane ? { appState.activateOtherPane() } : nil
        )
        .id(pane.currentTab.id)
    }
}

// Two panes side by side with a draggable divider. The split ratio is remembered
private struct DualPaneView: View {
    var appState: AppState
    var favoritesStore: FavoritesStore

    @AppStorage("Vela.dualPaneSplit") private var split: Double = 0.5
    @State private var isHoveringDivider = false

    private static let minPaneWidth: CGFloat = 240
    private static let space = "DualPane"

    var body: some View {
        GeometryReader { geometry in
            let available = max(geometry.size.width - 1, 1)
            HStack(spacing: 0) {
                pane(appState.panes[0])
                    .frame(width: (available * clampedSplit(available: available)).rounded())
                divider(available: available)
                pane(appState.panes[1])
                    .frame(maxWidth: .infinity)
            }
            .coordinateSpace(name: Self.space)
        }
    }

    private func clampedSplit(available: CGFloat) -> Double {
        let minFraction = min(0.5, Self.minPaneWidth / available)
        return min(max(split, minFraction), 1 - minFraction)
    }

    private func pane(_ pane: PaneState) -> some View {
        PaneView(appState: appState, pane: pane, favoritesStore: favoritesStore)
    }

    // A 1pt line with a wider invisible handle; double-click to split evenly
    private func divider(available: CGFloat) -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        guard hovering != isHoveringDivider else { return }
                        isHoveringDivider = hovering
                        if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                            .onChanged { value in split = Double(value.location.x / available) }
                            .onEnded { _ in split = clampedSplit(available: available) }
                    )
                    .onTapGesture(count: 2) { split = 0.5 }
            }
            .zIndex(1)
    }
}

// One pane in dual pane mode: its tab bar, address bar and file list. The active pane is marked with
// an accent line along its top edge; clicking anywhere in a pane makes it active
private struct PaneView: View {
    var appState: AppState
    var pane: PaneState
    var favoritesStore: FavoritesStore

    var body: some View {
        let isActive = appState.activePane === pane
        VStack(spacing: 0) {
            TabBarView(pane: pane, isActivePane: isActive,
                       onClose: { appState.closeTab(at: $0, in: pane) })
            AddressBarView(viewModel: pane.currentTab)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.bar)
            Divider()
            PaneFileList(appState: appState, pane: pane, favoritesStore: favoritesStore)
        }
        .overlay(alignment: .top) {
            if isActive {
                Rectangle().fill(Color.accentColor).frame(height: 2)
            }
        }
        .simultaneousGesture(TapGesture().onEnded { appState.activate(pane) })
    }
}

#Preview {
    ContentView()
}
