//
//  FileItem.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/04/20.
//

import Foundation

// Nonisolated so the subfolder search can build items on its background queue
nonisolated struct FileItem: Identifiable, Equatable, Hashable, Sendable {
    // URL を ID にすることで、リロード後も同じファイルが同じ Identity を持つ。
    // UUID だと毎回新規行と判定されて全行再描画が発生する。
    var id: URL { url }

    let name: String
    let url: URL
    let size: Int64
    let modifiedDate: Date
    let createdDate: Date
    // 「フォルダ」「PDF書類」など。macOS のシステム言語で返る（アプリの表示言語には追従しない）
    let kind: String
    let isDirectory: Bool
    // .app や .bundle など、Finder 上では単一ファイルとして扱われるディレクトリ
    let isPackage: Bool
    // ドットファイルや隠しフラグの付いた項目。隠しファイル表示中は一覧で薄く表示する
    let isHidden: Bool

    // id ベースの比較で SwiftUI の差分計算コストを最小化
    static func == (lhs: FileItem, rhs: FileItem) -> Bool { lhs.url == rhs.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }
}
