//
//  TabBarView.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/04/21.
//

import SwiftUI

struct TabBarView: View {
    var appState: AppState

    // ScrollView のスクロール位置的に、まだ右へスクロールできる余地があるか
    @State private var canScrollRight = false

    // 右端の矢印ボタン用に常に確保しておく幅（表示/非表示に関わらず一定にすることで、
    // ScrollView の表示領域幅が変動してちらつくのを防ぐ）
    private let scrollButtonWidth: CGFloat = 28

    var body: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(appState.tabs.enumerated()), id: \.element.id) { index, tab in
                            TabItemView(
                                title: tab.tabTitle,
                                isSelected: appState.selectedIndex == index,
                                onSelect: { appState.selectedIndex = index },
                                onClose: { appState.closeTab(at: index) }
                            )
                            .id(tab.id)
                            Divider().frame(height: 20)
                        }

                        Button(action: { appState.addTab() }) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 33)
                        }
                        .buttonStyle(.plain)
                        .help("新規タブ")
                    }
                }
                .trackCanScrollRight($canScrollRight)

                Group {
                    if canScrollRight {
                        Button(action: {
                            guard let lastID = appState.tabs.last?.id else { return }
                            withAnimation { proxy.scrollTo(lastID, anchor: .trailing) }
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("右のタブを表示")
                    }
                }
                .frame(width: scrollButtonWidth, height: 33)
            }
            .frame(height: 34)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}

private extension View {
    // onScrollGeometryChange は macOS 15 以降のみ。macOS 14 ではスクロール位置を取得できないため、
    // 右スクロールボタンを常に表示する
    @ViewBuilder
    func trackCanScrollRight(_ canScrollRight: Binding<Bool>) -> some View {
        if #available(macOS 15.0, *) {
            onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.x + geometry.containerSize.width < geometry.contentSize.width - 0.5
            } action: { _, newValue in
                canScrollRight.wrappedValue = newValue
            }
        } else {
            onAppear { canScrollRight.wrappedValue = true }
        }
    }
}

private struct TabItemView: View {
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(maxWidth: 130, alignment: .leading)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 14, height: 14)
                    .background(Color.secondary.opacity(isHovered ? 0.25 : 0))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 33)
        .frame(minWidth: 80, maxWidth: 160)
        .background(isSelected ? Color(nsColor: .windowBackgroundColor) : Color.clear)
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle().fill(Color.accentColor).frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovered = $0 }
    }
}
