//
//  TabBarView.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/04/21.
//

import SwiftUI

struct TabBarView: View {
    var appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(appState.tabs.enumerated()), id: \.element.id) { index, tab in
                    TabItemView(
                        title: tab.tabTitle,
                        isSelected: appState.selectedIndex == index,
                        canClose: appState.tabs.count > 1,
                        onSelect: { appState.selectedIndex = index },
                        onClose: { appState.closeTab(at: index) }
                    )
                    Divider().frame(height: 20)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 34)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct TabItemView: View {
    let title: String
    let isSelected: Bool
    let canClose: Bool
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
            .opacity((canClose && isHovered) || (canClose && isSelected) ? 1 : 0)
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
