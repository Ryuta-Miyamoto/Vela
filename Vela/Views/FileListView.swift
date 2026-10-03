//
//  FileListView.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/04/20.
//

import SwiftUI

struct FileListView: View {
    var viewModel: FileExplorerViewModel
    var onAddToFavorites: ((FileItem) -> Void)?
    var onOpenInNewTab: ((URL) -> Void)?

    @State private var sortState = FileSortState.default

    private var sortedItems: [FileItem] {
        let sorted = viewModel.items.sorted {
            switch sortState.key {
            case "date": return sortState.ascending ? $0.modifiedDate < $1.modifiedDate : $0.modifiedDate > $1.modifiedDate
            case "size": return sortState.ascending ? $0.size < $1.size : $0.size > $1.size
            default:
                let cmp = $0.name.localizedStandardCompare($1.name)
                return sortState.ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        }
        return sorted.sorted { $0.isDirectory && !$1.isDirectory }
    }

    private var filteredItems: [FileItem] {
        guard !viewModel.searchText.isEmpty else { return sortedItems }
        return sortedItems.filter { $0.name.localizedCaseInsensitiveContains(viewModel.searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            FileTableNSView(
                items: filteredItems,
                viewModel: viewModel,
                sortState: sortState,
                language: LanguageSettings.shared.language,
                onSortChange: { sortState = $0 },
                onAddToFavorites: onAddToFavorites,
                onOpenInNewTab: onOpenInNewTab
            )

            if !viewModel.searchText.isEmpty {
                HStack {
                    Text(L10n.searchResult(query: viewModel.searchText, count: filteredItems.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.bar)
                .overlay(alignment: .top) { Divider() }
            }
        }
    }
}
