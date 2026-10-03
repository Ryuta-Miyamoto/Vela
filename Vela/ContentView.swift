//
//  ContentView.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/04/20.
//

import SwiftUI
import AppKit

@Observable
final class FileExplorerViewModel {
    let id = UUID()
    var currentURL: URL {
        didSet { startWatching() }
    }
    var items: [FileItem] = []
    var showHiddenFiles: Bool = false
    var searchText: String = ""
    var selectedItems: [FileItem] = []

    private var backStack: [URL] = []
    private var forwardStack: [URL] = []
    // 他のアプリでの変更も一覧に反映するため、表示中のディレクトリを監視する（背面のタブも含む）
    @ObservationIgnored private var watcher: DirectoryWatcher?

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

    func toggleHiddenFiles() {
        showHiddenFiles.toggle()
        reload()
    }

    func reload() {
        items = FileService.shared.contents(of: currentURL, includeHidden: showHiddenFiles)
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
        for item in items {
            let dest = Self.uniqueURL(in: item.url.deletingLastPathComponent(),
                                      baseName: item.url.deletingPathExtension().lastPathComponent,
                                      pathExtension: item.url.pathExtension,
                                      suffix: L10n.copySuffix)
            try? FileOperations.copy(from: item.url, to: dest, actionName: L10n.duplicate)
        }
        reload()
    }

    // Finder と同じく、拡張子も含めた名前の後ろに「alias」を付ける（例: "Report.pdf alias"）
    func makeAliases(for items: [FileItem]) {
        for item in items {
            let dest = Self.uniqueURL(in: item.url.deletingLastPathComponent(),
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

    // 「<base><suffix>.<ext>」、既にあれば「<base><suffix> 2.<ext>」…と空いている名前を探す
    private static func uniqueURL(in folder: URL, baseName: String, pathExtension: String, suffix: String) -> URL {
        func url(_ name: String) -> URL {
            let u = folder.appendingPathComponent(name)
            return pathExtension.isEmpty ? u : u.appendingPathExtension(pathExtension)
        }
        var candidate = url(baseName + suffix)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url("\(baseName)\(suffix) \(counter)")
            counter += 1
        }
        return candidate
    }

    func moveItem(_ item: FileItem) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L10n.moveHere
        panel.message = L10n.chooseMoveDestination(name: item.name)
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        try? FileOperations.move(from: item.url, to: dest.appendingPathComponent(item.name), actionName: L10n.move)
        reload()
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

    func moveURL(_ source: URL, to destFolder: URL) {
        guard source != destFolder,
              !Self.isParent(destFolder, of: source),
              !destFolder.path.hasPrefix(source.path + "/") else { return }
        let dest = destFolder.appendingPathComponent(source.lastPathComponent)
        try? FileOperations.move(from: source, to: dest, actionName: L10n.move)
        reload()
    }

    func copyURL(_ source: URL, to destFolder: URL) {
        guard source != destFolder,
              !destFolder.path.hasPrefix(source.path + "/") else { return }
        // 同じフォルダへのペーストは名前がぶつかるので、Finder と同じく複製として扱う
        let dest = Self.isParent(destFolder, of: source)
            ? Self.uniqueURL(in: destFolder,
                             baseName: source.deletingPathExtension().lastPathComponent,
                             pathExtension: source.pathExtension,
                             suffix: L10n.copySuffix)
            : destFolder.appendingPathComponent(source.lastPathComponent)
        try? FileOperations.copy(from: source, to: dest)
        if destFolder == currentURL { reload() }
    }
}

// MARK: - App State (Tab Management)

@Observable
final class AppState {
    var tabs: [FileExplorerViewModel]
    var selectedIndex: Int

    var currentTab: FileExplorerViewModel { tabs[selectedIndex] }

    // 前回終了時のタブを復元するのは起動直後の最初のウインドウだけ。⌘N で開く追加のウインドウはホームから始める
    private static var hasRestoredSession = false

    init() {
        let restored = Self.hasRestoredSession ? nil : SavedSession.load()
        Self.hasRestoredSession = true
        // 前回から消えた・移動されたフォルダのタブは開かない
        let urls = (restored?.paths ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { url in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            }
        if let restored, !urls.isEmpty {
            tabs = urls.map { FileExplorerViewModel(url: $0) }
            let selectedPath = restored.paths.indices.contains(restored.selectedIndex)
                ? restored.paths[restored.selectedIndex] : nil
            selectedIndex = urls.firstIndex { $0.path == selectedPath } ?? 0
        } else {
            tabs = [FileExplorerViewModel()]
            selectedIndex = 0
        }
    }

    // 保存対象（タブごとの表示中フォルダと選択中のタブ）。ContentView が変化を監視して保存する
    var session: SavedSession {
        SavedSession(paths: tabs.map(\.currentURL.path), selectedIndex: selectedIndex)
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

    func closeTab(at index: Int) {
        // 残り1タブを閉じるのはウインドウを閉じる操作に相当するため、アプリを終了する
        guard tabs.count > 1 else {
            NSApplication.shared.terminate(nil)
            return
        }
        tabs.remove(at: index)
        if selectedIndex > index {
            selectedIndex -= 1
        } else if selectedIndex >= tabs.count {
            selectedIndex = tabs.count - 1
        }
    }
}

// MARK: - Session (Tab Restoration)

// ウインドウが複数あるときは、最後に操作したウインドウのタブが保存される
struct SavedSession: Codable, Equatable {
    private static let udKey = "Vela.session.v1"

    var paths: [String]
    var selectedIndex: Int

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
            TabBarView(appState: appState)
            ToolbarView(viewModel: appState.currentTab)
            Divider()
            NavigationSplitView {
                SidebarView(
                    viewModel: appState.currentTab,
                    favoritesStore: favoritesStore,
                    onOpenInNewTab: { appState.openInNewTab($0) }
                )
                    .navigationSplitViewColumnWidth(min: 150, ideal: 200)
            } detail: {
                FileListView(
                    viewModel: appState.currentTab,
                    onAddToFavorites: { item in
                        favoritesStore.add(name: item.name, url: item.url)
                    },
                    onOpenInNewTab: { appState.openInNewTab($0) }
                )
                .id(appState.currentTab.id)
            }
            StatusBarView(viewModel: appState.currentTab)
        }
        .background { tabShortcuts }
        .onChange(of: appState.session) { _, session in session.save() }
        .frame(minWidth: 800, minHeight: 520)
        .navigationTitle(appState.currentTab.tabTitle)
        // ⌘T / ⌘W のメニューコマンド（VelaApp の TabCommands）から参照する
        .focusedSceneValue(\.appState, appState)
    }

    // メニューに並べると冗長になる補助ショートカット（Safari と同じ割り当て）。
    // ⌘⇧[ / ⌘⇧] で前後のタブ、⌘1〜⌘8 で n 番目のタブ、⌘9 で最後のタブへ移動する
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
            Button("") { appState.selectTab(at: appState.tabs.count - 1) }
                .keyboardShortcut("9", modifiers: .command)
        }
        .hidden()
    }
}

#Preview {
    ContentView()
}
