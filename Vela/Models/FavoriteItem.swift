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

    var url: URL { URL(fileURLWithPath: path) }
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
        let home = FileManager.default.homeDirectoryForCurrentUser
        items = [
            FavoriteItem(id: UUID(), name: "ホーム",          path: home.path,                                     systemImage: "house.fill"),
            FavoriteItem(id: UUID(), name: "デスクトップ",     path: home.appendingPathComponent("Desktop").path,   systemImage: "desktopcomputer"),
            FavoriteItem(id: UUID(), name: "書類",             path: home.appendingPathComponent("Documents").path, systemImage: "doc.fill"),
            FavoriteItem(id: UUID(), name: "ダウンロード",     path: home.appendingPathComponent("Downloads").path, systemImage: "arrow.down.circle.fill"),
            FavoriteItem(id: UUID(), name: "アプリケーション", path: "/Applications",                               systemImage: "square.grid.2x2.fill"),
        ]
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
    }
}
