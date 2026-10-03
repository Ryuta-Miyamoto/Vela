//
//  FileOperations.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/10/03.
//

import AppKit

// 取り消し（⌘Z）できるファイル操作。各操作は実行と同時に「逆操作」を UndoManager に登録する。
// 逆操作もまた自分の逆操作を登録するので、やり直し（⇧⌘Z）も自然に成り立つ。
//   移動 a→b        ⇄ 移動 b→a
//   ゴミ箱へ a      → ゴミ箱内の t から a へ移動（その逆はまた t への移動）
//   コピー・新規作成 → 作ったものをゴミ箱へ（Finder と同じく完全には消さない）
// Finder と同じく、取り消し履歴はウインドウやタブをまたいでアプリ全体で 1 つ持つ
enum FileOperations {
    static let undoManager = UndoManager()

    // registerUndo(withTarget:) に渡す参照型のダミー
    private final class Anchor {}
    private static let anchor = Anchor()

    static func move(from source: URL, to dest: URL, actionName: String) throws {
        try FileManager.default.moveItem(at: source, to: dest)
        register(actionName: actionName) {
            try move(from: dest, to: source, actionName: actionName)
        }
    }

    static func trash(_ url: URL) throws {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        guard let trashedURL = resulting as URL? else { return }
        register(actionName: L10n.moveToTrash) {
            try move(from: trashedURL, to: url, actionName: L10n.moveToTrash)
        }
    }

    static func copy(from source: URL, to dest: URL, actionName: String = L10n.copy) throws {
        try FileManager.default.copyItem(at: source, to: dest)
        registerCreation(of: dest, actionName: actionName)
    }

    // Finder の「エイリアスを作成」と同じ形式（ブックマークファイル）。元の項目が移動しても追従できる
    static func makeAlias(of source: URL, at dest: URL) throws {
        let data = try source.bookmarkData(options: .suitableForBookmarkFile)
        try URL.writeBookmarkData(data, to: dest)
        registerCreation(of: dest, actionName: L10n.makeAlias)
    }

    static func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        registerCreation(of: url, actionName: L10n.newFolder)
    }

    // ZIP 圧縮のように外部プロセスが作ったファイルを、作成操作として履歴に載せる
    static func registerCreation(of url: URL, actionName: String) {
        register(actionName: actionName) {
            var resulting: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
            guard let trashedURL = resulting as URL? else { return }
            register(actionName: actionName) {
                try move(from: trashedURL, to: url, actionName: actionName)
            }
        }
    }

    private static func register(actionName: String, inverse: @escaping () throws -> Void) {
        undoManager.registerUndo(withTarget: anchor) { _ in
            MainActor.assumeIsolated {
                do {
                    try inverse()
                } catch {
                    // 取り消し対象が既に別の場所へ動かされている等。履歴はそのまま進めて警告音だけ鳴らす
                    NSLog("Failed to undo/redo file operation: \(error)")
                    NSSound.beep()
                }
            }
        }
        undoManager.setActionName(actionName)
    }
}
