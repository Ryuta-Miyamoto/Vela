//
//  FavoriteItem.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/04/22.
//

import Foundation
import SwiftUI

struct FavoriteItem: Identifiable, Codable {
    var id: UUID
    var name: String
    var path: String
    var systemImage: String
    // 初期登録の項目のみ持つ。表示名を表示言語に合わせて切り替えるために使う
    var defaultKey: DefaultFavorite?

    var url: URL { URL(fileURLWithPath: path) }
    var displayName: String { defaultKey?.localizedName ?? name }
}

enum DefaultFavorite: String, Codable, CaseIterable {
    case home, desktop, documents, downloads, applications

    var localizedName: String {
        switch self {
        case .home:         return L10n.favoriteHome
        case .desktop:      return L10n.favoriteDesktop
        case .documents:    return L10n.favoriteDocuments
        case .downloads:    return L10n.favoriteDownloads
        case .applications: return L10n.favoriteApplications
        }
    }

    // 言語切り替え導入前に日本語名で保存された初期項目を判別するための旧名称
    fileprivate var legacyJapaneseName: String {
        switch self {
        case .home:         return "ホーム"
        case .desktop:      return "デスクトップ"
        case .documents:    return "書類"
        case .downloads:    return "ダウンロード"
        case .applications: return "アプリケーション"
        }
    }

    var url: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .home:         return home
        case .desktop:      return home.appendingPathComponent("Desktop")
        case .documents:    return home.appendingPathComponent("Documents")
        case .downloads:    return home.appendingPathComponent("Downloads")
        case .applications: return URL(fileURLWithPath: "/Applications")
        }
    }

    var systemImage: String {
        switch self {
        case .home:         return "house.fill"
        case .desktop:      return "desktopcomputer"
        case .documents:    return "doc.fill"
        case .downloads:    return "arrow.down.circle.fill"
        case .applications: return "square.grid.2x2.fill"
        }
    }
}

@Observable
final class FavoritesStore {
    private static let udKey = "Vela.favorites.v1"
    var items: [FavoriteItem] = []

    init() {
        load()
        if items.isEmpty { seedDefaults() }
    }

    func add(name: String, url: URL, systemImage: String = "folder.fill") {
        guard !items.contains(where: { $0.path == url.path }) else { return }
        items.append(FavoriteItem(id: UUID(), name: name, path: url.path, systemImage: systemImage))
        save()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func seedDefaults() {
        items = DefaultFavorite.allCases.map {
            FavoriteItem(id: UUID(), name: $0.localizedName, path: $0.url.path, systemImage: $0.systemImage, defaultKey: $0)
        }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Self.udKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.udKey),
              let decoded = try? JSONDecoder().decode([FavoriteItem].self, from: data) else { return }
        items = decoded
        migrateLegacyDefaults()
    }

    private func migrateLegacyDefaults() {
        var migrated = false
        for index in items.indices where items[index].defaultKey == nil {
            guard let key = DefaultFavorite.allCases.first(where: {
                $0.legacyJapaneseName == items[index].name && $0.url.path == items[index].path
            }) else { continue }
            items[index].defaultKey = key
            migrated = true
        }
        if migrated { save() }
    }
}
