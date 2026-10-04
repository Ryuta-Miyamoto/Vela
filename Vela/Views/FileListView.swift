//
//  FileListView.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/04/20.
//

import SwiftUI

struct FileListView: View {
    var viewModel: FileExplorerViewModel
    var favoriteGroups: (() -> [FavoriteGroup])?
    var onAddToFavorites: ((FileItem, UUID) -> Void)?
    var onOpenInNewTab: ((URL) -> Void)?

    @State private var sortState = FileSortState.default

    private func sorted(_ items: [FileItem]) -> [FileItem] {
        let sorted = items.sorted {
            switch sortState.key {
            case "date": return sortState.ascending ? $0.modifiedDate < $1.modifiedDate : $0.modifiedDate > $1.modifiedDate
            case "size": return sortState.ascending ? $0.size < $1.size : $0.size > $1.size
            case "created": return sortState.ascending ? $0.createdDate < $1.createdDate : $0.createdDate > $1.createdDate
            case "kind" where $0.kind != $1.kind:
                let cmp = $0.kind.localizedStandardCompare($1.kind)
                return sortState.ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            case "location" where $0.url.deletingLastPathComponent() != $1.url.deletingLastPathComponent():
                let cmp = $0.url.deletingLastPathComponent().path.localizedStandardCompare($1.url.deletingLastPathComponent().path)
                return sortState.ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            default:
                let cmp = $0.name.localizedStandardCompare($1.name)
                return sortState.ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        }
        return sorted.sorted { $0.isDirectory && !$1.isDirectory }
    }

    private var displayedItems: [FileItem] {
        if viewModel.isSubfolderSearchActive { return sorted(viewModel.searchResults) }
        guard !viewModel.searchText.isEmpty else { return sorted(viewModel.items) }
        return sorted(viewModel.items).filter { $0.name.localizedCaseInsensitiveContains(viewModel.searchText) }
    }

    var body: some View {
        let items = displayedItems
        VStack(spacing: 0) {
            FileTableNSView(
                items: items,
                viewModel: viewModel,
                sortState: sortState,
                language: LanguageSettings.shared.language,
                // Results from subfolders show where each item is, relative to the folder being searched
                locationRoot: viewModel.isSubfolderSearchActive ? viewModel.currentURL : nil,
                onSortChange: { sortState = $0 },
                favoriteGroups: favoriteGroups,
                onAddToFavorites: onAddToFavorites,
                onOpenInNewTab: onOpenInNewTab
            )

            if !viewModel.searchText.isEmpty {
                HStack(spacing: 6) {
                    Text(L10n.searchResult(query: viewModel.searchText, count: items.count))
                    if viewModel.isSubfolderSearchActive {
                        if viewModel.isSearching {
                            ProgressView().controlSize(.mini)
                            Text(L10n.searchingSubfolders)
                        } else if viewModel.searchReachedLimit {
                            Text(L10n.searchLimitReached(SubfolderSearch.resultLimit))
                        }
                    }
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.bar)
                .overlay(alignment: .top) { Divider() }
            }
        }
    }
}
