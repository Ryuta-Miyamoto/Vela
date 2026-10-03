//
//  FavoriteItem.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/04/22.
//

import Foundation
import SwiftUI

struct FavoriteItem: Identifiable, Codable, Equatable {
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

// サイドバーの見出し（タグ）と、その配下に並ぶお気に入り
struct FavoriteGroup: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var items: [FavoriteItem]
    var isExpanded: Bool
    // 初期グループのみ true。名前を変更するまでは表示名を表示言語に合わせて切り替える
    var isDefault: Bool

    var displayName: String { isDefault ? L10n.favorites : name }
}

@Observable
final class FavoritesStore {
    private static let udKey = "Vela.favoriteGroups.v2"
    // グループ導入前の保存形式（[FavoriteItem]）。初回起動時に既定グループへ移す
    private static let legacyUDKey = "Vela.favorites.v1"
    private(set) var groups: [FavoriteGroup] = []

    init() {
        load()
        if groups.isEmpty { seedDefaults() }
    }

    // MARK: Items

    func add(name: String, url: URL, toGroup groupID: UUID, systemImage: String = "folder.fill") {
        guard let g = groups.firstIndex(where: { $0.id == groupID }),
              !groups[g].items.contains(where: { $0.path == url.path }) else { return }
        groups[g].items.append(FavoriteItem(id: UUID(), name: name, path: url.path, systemImage: systemImage))
        save()
    }

    func removeItem(id: UUID) {
        for g in groups.indices { groups[g].items.removeAll { $0.id == id } }
        save()
    }

    // index は移動前の並びで数えた挿入位置（NSOutlineView のドロップ位置をそのまま渡せる）
    func moveItem(id: UUID, toGroup groupID: UUID, at index: Int) {
        guard let (g, i) = locateItem(id: id),
              groups.contains(where: { $0.id == groupID }) else { return }
        var destIndex = index
        if groups[g].id == groupID && i < destIndex { destIndex -= 1 }
        let item = groups[g].items.remove(at: i)
        guard let dest = groups.firstIndex(where: { $0.id == groupID }) else { return }
        // 移動先のグループに同じフォルダがあれば重複させず、移動元から取り除くだけにする
        if !(groups[g].id != groupID && groups[dest].items.contains(where: { $0.path == item.path })) {
            groups[dest].items.insert(item, at: min(max(destIndex, 0), groups[dest].items.count))
        }
        save()
    }

    private func locateItem(id: UUID) -> (Int, Int)? {
        for g in groups.indices {
            if let i = groups[g].items.firstIndex(where: { $0.id == id }) { return (g, i) }
        }
        return nil
    }

    // MARK: Groups

    func addGroup(name: String) {
        groups.append(FavoriteGroup(id: UUID(), name: name, items: [], isExpanded: true, isDefault: false))
        save()
    }

    func renameGroup(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let g = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[g].name = trimmed
        groups[g].isDefault = false
        save()
    }

    // 「お気に入りに追加」の追加先がなくなるため、最後の 1 つは削除できない
    var canRemoveGroup: Bool { groups.count > 1 }

    func removeGroup(id: UUID) {
        guard canRemoveGroup else { return }
        groups.removeAll { $0.id == id }
        save()
    }

    func moveGroup(id: UUID, to index: Int) {
        guard let from = groups.firstIndex(where: { $0.id == id }) else { return }
        var destIndex = index
        if from < destIndex { destIndex -= 1 }
        let group = groups.remove(at: from)
        groups.insert(group, at: min(max(destIndex, 0), groups.count))
        save()
    }

    func setExpanded(_ expanded: Bool, groupID: UUID) {
        guard let g = groups.firstIndex(where: { $0.id == groupID }),
              groups[g].isExpanded != expanded else { return }
        groups[g].isExpanded = expanded
        save()
    }

    // MARK: Defaults

    // どのグループにも残っていない初期項目（同じパスを手動で登録していれば残っているとみなす）
    var missingDefaults: [DefaultFavorite] {
        let allItems = groups.flatMap(\.items)
        return DefaultFavorite.allCases.filter { key in
            !allItems.contains { $0.defaultKey == key || $0.path == key.url.path }
        }
    }

    // 欠けている初期項目だけを先頭のグループの末尾に戻す
    func restoreDefaults() {
        guard !groups.isEmpty else { return seedDefaults() }
        let missing = missingDefaults
        let restored = Self.defaultItems().filter { item in missing.contains { $0 == item.defaultKey } }
        guard !restored.isEmpty else { return }
        groups[0].items.append(contentsOf: restored)
        save()
    }

    // MARK: Persistence

    private static func defaultItems() -> [FavoriteItem] {
        DefaultFavorite.allCases.map {
            FavoriteItem(id: UUID(), name: $0.localizedName, path: $0.url.path, systemImage: $0.systemImage, defaultKey: $0)
        }
    }

    private static func defaultGroup(items: [FavoriteItem]) -> FavoriteGroup {
        FavoriteGroup(id: UUID(), name: L10n.favorites, items: items, isExpanded: true, isDefault: true)
    }

    private func seedDefaults() {
        groups = [Self.defaultGroup(items: Self.defaultItems())]
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        UserDefaults.standard.set(data, forKey: Self.udKey)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.udKey),
           let decoded = try? JSONDecoder().decode([FavoriteGroup].self, from: data) {
            groups = decoded
            return
        }
        migrateFromLegacyItems()
    }

    private func migrateFromLegacyItems() {
        guard let data = UserDefaults.standard.data(forKey: Self.legacyUDKey),
              var items = try? JSONDecoder().decode([FavoriteItem].self, from: data) else { return }
        Self.migrateLegacyDefaults(&items)
        groups = [Self.defaultGroup(items: items)]
        // 旧キーは消さずに残し、以前のバージョンに戻しても登録が失われないようにする
        save()
    }

    private static func migrateLegacyDefaults(_ items: inout [FavoriteItem]) {
        for index in items.indices where items[index].defaultKey == nil {
            guard let key = DefaultFavorite.allCases.first(where: {
                $0.legacyJapaneseName == items[index].name && $0.url.path == items[index].path
            }) else { continue }
            items[index].defaultKey = key
        }
    }
}
