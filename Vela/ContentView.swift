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
    var currentURL: URL
    var items: [FileItem] = []
    var showHiddenFiles: Bool = false
    var searchText: String = ""
    var selectedItems: [FileItem] = []

    private var backStack: [URL] = []
    private var forwardStack: [URL] = []

    var canGoBack: Bool    { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool      { currentURL.pathComponents.count > 1 }
    var tabTitle: String   { currentURL.lastPathComponent.isEmpty ? "/" : currentURL.lastPathComponent }

    init(url: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.currentURL = url
        reload()
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
                if proc.terminationStatus != 0 {
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
            try FileManager.default.moveItem(at: item.url, to: dest)
        } catch {
            let alert = NSAlert()
            alert.messageText = L10n.renameFailed
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
        reload()
    }

    func copyItem(_ item: FileItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item.url as NSURL])
    }

    func moveItem(_ item: FileItem) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L10n.moveHere
        panel.message = L10n.chooseMoveDestination(name: item.name)
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        try? FileManager.default.moveItem(at: item.url, to: dest.appendingPathComponent(item.name))
        reload()
    }

    func trashItem(_ item: FileItem) {
        try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
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
        try? FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: false)
        reload()
    }

    func moveURL(_ source: URL, to destFolder: URL) {
        guard source != destFolder,
              !destFolder.path.hasPrefix(source.path + "/") else { return }
        let dest = destFolder.appendingPathComponent(source.lastPathComponent)
        try? FileManager.default.moveItem(at: source, to: dest)
        reload()
    }

    func copyURL(_ source: URL, to destFolder: URL) {
        guard source != destFolder,
              !destFolder.path.hasPrefix(source.path + "/") else { return }
        let dest = destFolder.appendingPathComponent(source.lastPathComponent)
        try? FileManager.default.copyItem(at: source, to: dest)
        if destFolder == currentURL { reload() }
    }
}

// MARK: - App State (Tab Management)

@Observable
final class AppState {
    var tabs: [FileExplorerViewModel] = [FileExplorerViewModel()]
    var selectedIndex: Int = 0

    var currentTab: FileExplorerViewModel { tabs[selectedIndex] }

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
