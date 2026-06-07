//
//  SidebarView.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/04/20.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct SidebarView: View {
    var viewModel: FileExplorerViewModel
    @Bindable var favoritesStore: FavoritesStore
    @State private var dropTargetURL: URL? = nil

    var body: some View {
        List {
            Section("よく使う項目") {
                ForEach(favoritesStore.items) { item in
                    Label(item.name, systemImage: item.systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .padding(.vertical, 2)
                        .background(
                            dropTargetURL == item.url
                                ? RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.15))
                                : nil
                        )
                        .onTapGesture { viewModel.navigate(to: item.url) }
                        .onDrop(
                            of: [.fileURL],
                            isTargeted: Binding(
                                get: { dropTargetURL == item.url },
                                set: { dropTargetURL = $0 ? item.url : nil }
                            )
                        ) { providers in handleDrop(providers, to: item.url) }
                        .contextMenu {
                            Button("削除", role: .destructive) {
                                favoritesStore.remove(id: item.id)
                            }
                        }
                }
                .onMove { favoritesStore.move(from: $0, to: $1) }
            }
        }
        .listStyle(.sidebar)
    }

    private func handleDrop(_ providers: [NSItemProvider], to destURL: URL) -> Bool {
        let isCopy = NSEvent.modifierFlags.contains(.option)
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let sourceURL = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    if isCopy { viewModel.copyURL(sourceURL, to: destURL) }
                    else      { viewModel.moveURL(sourceURL, to: destURL) }
                }
            }
        }
        return true
    }
}
