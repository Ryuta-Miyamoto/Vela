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
    var onOpenInNewTab: ((URL) -> Void)?
    @State private var dropTargetURL: URL? = nil

    var body: some View {
        List {
            Section(L10n.favorites) {
                ForEach(favoritesStore.items) { item in
                    Label(item.displayName, systemImage: item.systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .padding(.vertical, 2)
                        .background(
                            dropTargetURL == item.url
                                ? RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.15))
                                : nil
                        )
                        .onTapGesture { viewModel.navigate(to: item.url) }
                        .overlay { MiddleClickCatcher { onOpenInNewTab?(item.url) } }
                        .onDrop(
                            of: [.fileURL],
                            isTargeted: Binding(
                                get: { dropTargetURL == item.url },
                                set: { dropTargetURL = $0 ? item.url : nil }
                            )
                        ) { providers in handleDrop(providers, to: item.url) }
                        .contextMenu {
                            Button(L10n.remove, role: .destructive) {
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

// SwiftUI にはホイール（中ボタン）クリックを受け取るジェスチャがないため、AppKit のビューを重ねて拾う
private struct MiddleClickCatcher: NSViewRepresentable {
    var action: () -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }
    func updateNSView(_ view: CatcherView, context: Context) { view.action = action }

    final class CatcherView: NSView {
        var action: (() -> Void)?

        // 中ボタンのクリック以外はヒットテストを素通りさせ、下にある行のタップ・ドラッグ・右クリックを妨げない
        override func hitTest(_ point: NSPoint) -> NSView? {
            switch NSApp.currentEvent?.type {
            case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
                return super.hitTest(point)
            default:
                return nil
            }
        }

        override func otherMouseDown(with event: NSEvent) {
            // buttonNumber 2 = ホイール（中ボタン）
            guard event.buttonNumber == 2 else { return super.otherMouseDown(with: event) }
            action?()
        }
    }
}
