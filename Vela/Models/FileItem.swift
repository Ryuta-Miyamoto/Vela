//
//  FileItem.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/04/20.
//

import Foundation

struct FileItem: Identifiable, Equatable, Hashable {
    // URL を ID にすることで、リロード後も同じファイルが同じ Identity を持つ。
    // UUID だと毎回新規行と判定されて全行再描画が発生する。
    var id: URL { url }

    let name: String
    let url: URL
    let size: Int64
    let modifiedDate: Date
    let isDirectory: Bool
    // .app や .bundle など、Finder 上では単一ファイルとして扱われるディレクトリ
    let isPackage: Bool

    // id ベースの比較で SwiftUI の差分計算コストを最小化
    static func == (lhs: FileItem, rhs: FileItem) -> Bool { lhs.url == rhs.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }
}
