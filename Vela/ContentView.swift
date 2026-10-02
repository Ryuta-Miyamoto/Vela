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

    init() {
        self.currentURL = FileManager.default.homeDirectoryForCurrentUser
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
            NSLog("Finder情報ウインドウを開けませんでした: \(error)")
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
                    NSLog("ZIP圧縮に失敗しました（終了コード: \(proc.terminationStatus)）")
                }
                self?.reload()
            }
        }
        do {
            try process.run()
        } catch {
            NSLog("ZIP圧縮の起動に失敗しました: \(error)")
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
            alert.messageText = "名前を変更できませんでした"
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
        panel.prompt = "ここに移動"
        panel.message = "「\(item.name)」の移動先フォルダを選択"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        try? FileManager.default.moveItem(at: item.url, to: dest.appendingPathComponent(item.name))
        reload()
    }

    func trashItem(_ item: FileItem) {
        try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        reload()
    }

    func createFolder() {
        var name = "新規フォルダ"
        var counter = 2
        var newURL = currentURL.appendingPathComponent(name)
        while FileManager.default.fileExists(atPath: newURL.path) {
            name = "新規フォルダ \(counter)"
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
                SidebarView(viewModel: appState.currentTab, favoritesStore: favoritesStore)
                    .navigationSplitViewColumnWidth(min: 150, ideal: 200)
            } detail: {
                FileListView(
                    viewModel: appState.currentTab,
                    onAddToFavorites: { item in
                        favoritesStore.add(name: item.name, url: item.url)
                    }
                )
                .id(appState.currentTab.id)
            }
            StatusBarView(viewModel: appState.currentTab)
        }
        .frame(minWidth: 800, minHeight: 520)
        .navigationTitle(appState.currentTab.tabTitle)
        // ⌘T / ⌘W のメニューコマンド（VelaApp の TabCommands）から参照する
        .focusedSceneValue(\.appState, appState)
    }
}

#Preview {
    ContentView()
}
