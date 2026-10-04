//
//  FileDisplaySettings.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/10/04.
//

import Foundation

// ファイル一覧の表示設定。全ウインドウ・全タブで共有し、UserDefaults に保存して再起動後も引き継ぐ
@Observable
final class FileDisplaySettings {
    static let shared = FileDisplaySettings()
    private static let showHiddenFilesKey = "Vela.showHiddenFiles"
    private static let searchIncludesSubfoldersKey = "Vela.searchIncludesSubfolders"

    var showHiddenFiles: Bool {
        didSet { UserDefaults.standard.set(showHiddenFiles, forKey: Self.showHiddenFilesKey) }
    }

    // Search scope: only the current folder (filtering the list) or everything below it too
    var searchIncludesSubfolders: Bool {
        didSet { UserDefaults.standard.set(searchIncludesSubfolders, forKey: Self.searchIncludesSubfoldersKey) }
    }

    private init() {
        showHiddenFiles = UserDefaults.standard.bool(forKey: Self.showHiddenFilesKey)
        searchIncludesSubfolders = UserDefaults.standard.bool(forKey: Self.searchIncludesSubfoldersKey)
    }
}
