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
        }
    }
}

// ファイルメニューのタブ操作。⌘T / ⌘W をメニュー経由で確実にタブ操作へ割り当てる。
// 標準の「新規ウインドウ(⌘N)」はそのまま残し、⌘W と重なる標準の「閉じる」は ⇧⌘W に移す
private struct TabCommands: Commands {
    @FocusedValue(\.appState) private var appState

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("新規タブ") { appState?.addTab() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(appState == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("ウインドウを閉じる") {
                (NSApp.keyWindow ?? NSApp.mainWindow)?.performClose(nil)
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])

            Button("タブを閉じる") {
                guard let appState else { return }
                appState.closeTab(at: appState.selectedIndex)
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(appState == nil)
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
