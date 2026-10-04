//
//  VelaApp.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/04/20.
//

import SwiftUI

@main
struct VelaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            TabCommands()
            ViewCommands()
            LanguageCommands()
        }
    }
}

// 表示メニュー。隠しファイルの切り替えは Finder と同じ ⌘⇧. に割り当てる
private struct ViewCommands: Commands {
    @Bindable private var settings = FileDisplaySettings.shared
    @FocusedValue(\.appState) private var appState

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button(settings.showHiddenFiles ? L10n.hideHiddenFiles : L10n.showHiddenFiles) {
                settings.showHiddenFiles.toggle()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            Divider()

            // ⌥⌘D is taken by the system (Dock) and ⌘⇧D is Finder's Go to Desktop, so "2" for two panes
            Toggle(L10n.dualPane, isOn: Binding(
                get: { appState?.isDualPane ?? false },
                set: { _ in appState?.toggleDualPane() }
            ))
            .keyboardShortcut("2", modifiers: [.control, .command])
            .disabled(appState == nil)
            // Tab in the file list does the same; the menu item is mainly there to be discoverable
            Button(L10n.switchPane) { appState?.activateOtherPane() }
                .disabled(appState?.isDualPane != true)
            Button(L10n.sameFolderInOtherPane) { appState?.showSameFolderInOtherPane() }
                .disabled(appState?.isDualPane != true)
            Button(L10n.swapPanes) { appState?.swapPanes() }
                .disabled(appState?.isDualPane != true)
            Divider()
        }
    }
}

// ファイルメニューのタブ操作。⌘T / ⌘W をメニュー経由で確実にタブ操作へ割り当てる。
// 標準の「New Window (⌘N)」はそのまま残し、⌘W と重なる標準の「Close」は「Close Window (⇧⌘W)」に移す
private struct TabCommands: Commands {
    @FocusedValue(\.appState) private var appState

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(L10n.newTab) { appState?.addTab() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(appState == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button(L10n.closeWindow) {
                (NSApp.keyWindow ?? NSApp.mainWindow)?.performClose(nil)
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])

            Button(L10n.closeTab) { appState?.closeCurrentTab() }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(appState == nil)
        }
        // Finder と同じく、タブの前後移動はウインドウメニューに置く（2ペイン表示ではアクティブなペインのタブ）
        CommandGroup(after: .windowArrangement) {
            Divider()
            Button(L10n.showPreviousTab) { appState?.selectPreviousTab() }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .disabled((appState?.activePane.tabs.count ?? 0) < 2)
            Button(L10n.showNextTab) { appState?.selectNextTab() }
                .keyboardShortcut(.tab, modifiers: .control)
                .disabled((appState?.activePane.tabs.count ?? 0) < 2)
        }
    }
}

// アプリメニュー（Vela）の設定項目の位置に表示言語の切り替えを置く。
// 標準メニュー（About / Quit / Edit など）は macOS 側の表記のまま
private struct LanguageCommands: Commands {
    @Bindable private var settings = LanguageSettings.shared

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Picker(L10n.language, selection: $settings.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
        }
    }
}

private struct AppStateFocusedValueKey: FocusedValueKey {
    typealias Value = AppState
}

extension FocusedValues {
    var appState: AppState? {
        get { self[AppStateFocusedValueKey.self] }
        set { self[AppStateFocusedValueKey.self] = newValue }
    }
}
